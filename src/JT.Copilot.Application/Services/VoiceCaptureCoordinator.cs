using System.Diagnostics;
using JT.Copilot.Application.Abstractions;
using JT.Copilot.Application.Hotkeys;
using JT.Copilot.Application.Models;
using JT.Copilot.Domain.Enums;

namespace JT.Copilot.Application.Services;

public sealed class VoiceCaptureCoordinator : IVoiceCaptureCoordinator
{
    private readonly IAudioCaptureService _audioCaptureService;
    private readonly IGlobalHotkeyService _globalHotkeyService;
    private readonly IAppSettingsStore _settingsStore;
    private readonly SemaphoreSlim _stateGate = new(1, 1);
    private readonly object _timerLock = new();

    private Timer? _elapsedTimer;
    private long _recordingStartedAt;
    private bool _hotkeyHeld;
    private bool _startedByHotkey;
    private bool _initialized;
    private bool _disposed;

    public VoiceCaptureCoordinator(
        IAudioCaptureService audioCaptureService,
        IGlobalHotkeyService globalHotkeyService,
        IAppSettingsStore settingsStore)
    {
        _audioCaptureService = audioCaptureService;
        _globalHotkeyService = globalHotkeyService;
        _settingsStore = settingsStore;

        _globalHotkeyService.Pressed += OnHotkeyPressed;
        _globalHotkeyService.Released += OnHotkeyReleased;
        _globalHotkeyService.CancelRequested += OnCancelRequested;
        _audioCaptureService.LevelChanged += OnAudioLevelChanged;
    }

    public event EventHandler<VoiceCaptureStateChangedEventArgs>? StateChanged;

    public event EventHandler<AudioLevelChangedEventArgs>? LevelChanged;

    public VoiceCaptureSnapshot Current { get; private set; } = VoiceCaptureSnapshot.Idle;

    public async Task InitializeAsync(CancellationToken cancellationToken = default)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        cancellationToken.ThrowIfCancellationRequested();

        if (_initialized)
        {
            return;
        }

        try
        {
            // Low-level keyboard hooks must be installed on the UI thread so the
            // WPF dispatcher can deliver hook callbacks.
            var settings = await _settingsStore.LoadAsync(cancellationToken);
            _globalHotkeyService.Start(HotkeyGesture.ParseOrDefault(settings.Hotkey));
            _initialized = true;
        }
        catch (Exception exception)
        {
            Publish(new VoiceCaptureSnapshot(
                VoiceCaptureState.Faulted,
                TimeSpan.Zero,
                ErrorMessage: $"全局快捷键启动失败：{exception.Message}"));
        }
    }

    public async Task StartAsync(CancellationToken cancellationToken = default)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        await _stateGate.WaitAsync(cancellationToken).ConfigureAwait(false);

        try
        {
            if (Current.State == VoiceCaptureState.Recording || _audioCaptureService.IsCapturing)
            {
                return;
            }

            var settings = await _settingsStore.LoadAsync(cancellationToken).ConfigureAwait(false);
            await _audioCaptureService
                .StartAsync(settings.PreferredMicrophoneDeviceId, cancellationToken)
                .ConfigureAwait(false);

            _recordingStartedAt = Stopwatch.GetTimestamp();
            StartElapsedTimer();
            Publish(new VoiceCaptureSnapshot(
                VoiceCaptureState.Recording,
                TimeSpan.Zero,
                ErrorMessage: null));

            // A very quick key tap can release before NAudio has finished starting.
            if (_startedByHotkey && !_hotkeyHeld)
            {
                await StopCoreAsync(cancellationToken).ConfigureAwait(false);
            }
        }
        catch (OperationCanceledException)
        {
            await CancelCoreAsync().ConfigureAwait(false);
            throw;
        }
        catch (Exception exception)
        {
            StopElapsedTimer();
            Publish(new VoiceCaptureSnapshot(
                VoiceCaptureState.Faulted,
                TimeSpan.Zero,
                ErrorMessage: exception.Message));
        }
        finally
        {
            _startedByHotkey = false;
            _stateGate.Release();
        }
    }

    public async Task StopAsync(CancellationToken cancellationToken = default)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        await _stateGate.WaitAsync(cancellationToken).ConfigureAwait(false);

        try
        {
            await StopCoreAsync(cancellationToken).ConfigureAwait(false);
        }
        finally
        {
            _stateGate.Release();
        }
    }

    public async Task CancelAsync(CancellationToken cancellationToken = default)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        await _stateGate.WaitAsync(cancellationToken).ConfigureAwait(false);

        try
        {
            await CancelCoreAsync().ConfigureAwait(false);
        }
        finally
        {
            _stateGate.Release();
        }
    }

    public void UpdateHotkey(HotkeyGesture gesture)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        ArgumentNullException.ThrowIfNull(gesture);

        if (Current.State == VoiceCaptureState.Recording)
        {
            throw new InvalidOperationException("请先结束当前录音，再修改全局快捷键。");
        }

        _globalHotkeyService.Reconfigure(gesture);
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        StopElapsedTimer();
        _globalHotkeyService.Pressed -= OnHotkeyPressed;
        _globalHotkeyService.Released -= OnHotkeyReleased;
        _globalHotkeyService.CancelRequested -= OnCancelRequested;
        _audioCaptureService.LevelChanged -= OnAudioLevelChanged;
        _stateGate.Dispose();
    }

    private async Task StopCoreAsync(CancellationToken cancellationToken)
    {
        if (Current.State != VoiceCaptureState.Recording || !_audioCaptureService.IsCapturing)
        {
            return;
        }

        StopElapsedTimer();
        var result = await _audioCaptureService.StopAsync(cancellationToken).ConfigureAwait(false);
        Publish(new VoiceCaptureSnapshot(
            VoiceCaptureState.Captured,
            result.Duration,
            result.FilePath,
            ErrorMessage: null));
    }

    private Task CancelCoreAsync()
    {
        StopElapsedTimer();
        _audioCaptureService.Cancel();
        Publish(VoiceCaptureSnapshot.Idle);
        return Task.CompletedTask;
    }

    private void StartElapsedTimer()
    {
        lock (_timerLock)
        {
            _elapsedTimer ??= new Timer(OnElapsedTimerTick);
            _elapsedTimer.Change(100, 100);
        }
    }

    private void StopElapsedTimer()
    {
        lock (_timerLock)
        {
            _elapsedTimer?.Change(Timeout.Infinite, Timeout.Infinite);
        }
    }

    private void OnElapsedTimerTick(object? state)
    {
        if (Current.State != VoiceCaptureState.Recording)
        {
            return;
        }

        var elapsed = Stopwatch.GetElapsedTime(_recordingStartedAt);
        Publish(Current with { Elapsed = elapsed });
    }

    private void OnHotkeyPressed(object? sender, EventArgs e)
    {
        _hotkeyHeld = true;
        _startedByHotkey = true;
        _ = StartAsync();
    }

    private void OnHotkeyReleased(object? sender, EventArgs e)
    {
        _hotkeyHeld = false;
        _ = StopAsync();
    }

    private void OnCancelRequested(object? sender, EventArgs e)
    {
        _hotkeyHeld = false;
        _ = CancelAsync();
    }

    private void OnAudioLevelChanged(object? sender, AudioLevelChangedEventArgs e)
    {
        LevelChanged?.Invoke(this, e);
    }

    private void Publish(VoiceCaptureSnapshot snapshot)
    {
        Current = snapshot;
        StateChanged?.Invoke(this, new VoiceCaptureStateChangedEventArgs(snapshot));
    }
}

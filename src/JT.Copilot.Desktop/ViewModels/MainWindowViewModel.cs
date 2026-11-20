using System.Collections.ObjectModel;
using System.Diagnostics;
using System.IO;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using JT.Copilot.Application.Abstractions;
using JT.Copilot.Application.Hotkeys;
using JT.Copilot.Application.Models;
using JT.Copilot.Domain.Enums;
using JT.Copilot.Infrastructure.Storage;
using Microsoft.Extensions.Logging;

namespace JT.Copilot.Desktop.ViewModels;

public partial class MainWindowViewModel : ObservableObject, IDisposable
{
    private readonly IVoiceCaptureCoordinator _voiceCaptureCoordinator;
    private readonly IAppSettingsStore _settingsStore;
    private readonly IAudioCaptureService _audioCaptureService;
    private readonly ILogger<MainWindowViewModel> _logger;

    private AppSettings _settings = new();
    private bool _isInitializing;
    private bool _disposed;

    [ObservableProperty]
    private bool isExpanded = true;

    [ObservableProperty]
    private bool isRecording;

    [ObservableProperty]
    private bool isCaptured;

    [ObservableProperty]
    private bool hasError;

    [ObservableProperty]
    private bool isTopmost = true;

    [ObservableProperty]
    private string statusTitle = "准备就绪";

    [ObservableProperty]
    private string statusDetail = "麦克风待命";

    [ObservableProperty]
    private string statusCode = "IDLE";

    [ObservableProperty]
    private string elapsedText = "00:00";

    [ObservableProperty]
    private string microphoneActionLabel = "开始录音";

    [ObservableProperty]
    private double audioLevel;

    [ObservableProperty]
    private AudioDeviceDescriptor? selectedMicrophone;

    [ObservableProperty]
    private string hotkeyText = AppSettings.DefaultHotkey;

    [ObservableProperty]
    private string hotkeyError = string.Empty;

    [ObservableProperty]
    private string lastRecordingPath = string.Empty;

    public MainWindowViewModel(
        IVoiceCaptureCoordinator voiceCaptureCoordinator,
        IAppSettingsStore settingsStore,
        IAudioCaptureService audioCaptureService,
        ILogger<MainWindowViewModel> logger)
    {
        _voiceCaptureCoordinator = voiceCaptureCoordinator;
        _settingsStore = settingsStore;
        _audioCaptureService = audioCaptureService;
        _logger = logger;

        _voiceCaptureCoordinator.StateChanged += OnVoiceCaptureStateChanged;
        _voiceCaptureCoordinator.LevelChanged += OnAudioLevelChanged;
    }

    public event EventHandler? SettingsRequested;

    public event EventHandler? CloseRequested;

    public ObservableCollection<AudioDeviceDescriptor> AudioDevices { get; } = [];

    public AppSettings Settings => _settings;

    public string RecordingsDirectory => AppPaths.RecordingsDirectory;

    public double WindowWidth => IsExpanded ? 372 : 72;

    public double WindowHeight => IsExpanded ? 166 : 72;

    public double AudioLevelPercent => AudioLevel * 100;

    public async Task InitializeAsync(CancellationToken cancellationToken = default)
    {
        _isInitializing = true;

        try
        {
            _settings = await _settingsStore.LoadAsync(cancellationToken);
            HotkeyText = FormatHotkey(_settings.Hotkey);
            IsTopmost = _settings.IsTopmost;
            IsExpanded = _settings.IsExpanded;

            AudioDevices.Clear();
            foreach (var device in _audioCaptureService.GetInputDevices())
            {
                AudioDevices.Add(device);
            }

            SelectedMicrophone = AudioDevices.FirstOrDefault(
                device => device.Id == _settings.PreferredMicrophoneDeviceId)
                ?? AudioDevices.FirstOrDefault();

            await _voiceCaptureCoordinator.InitializeAsync(cancellationToken);
            ApplySnapshot(_voiceCaptureCoordinator.Current);
        }
        finally
        {
            _isInitializing = false;
        }
    }

    public Task SaveWindowPlacementAsync(double left, double top)
    {
        _settings = (_settings with
        {
            WindowLeft = left,
            WindowTop = top
        }).Normalize();

        return PersistSettingsAsync();
    }

    public void ReportStartupFailure(string message)
    {
        ApplySnapshot(new VoiceCaptureSnapshot(
            VoiceCaptureState.Faulted,
            TimeSpan.Zero,
            ErrorMessage: message));
    }

    public void BeginHotkeyCapture()
    {
        HotkeyError = string.Empty;

        if (IsRecording)
        {
            HotkeyError = "请先结束当前录音，再修改全局快捷键。";
            return;
        }

        HotkeyText = "请按下新的组合";
    }

    public void PreviewHotkey(HotkeyModifiers modifiers, IReadOnlyCollection<int> virtualKeys)
    {
        if (virtualKeys.Count == 0)
        {
            HotkeyText = "请按下新的组合";
            return;
        }

        if (HotkeyGesture.TryCreate(modifiers, virtualKeys, out var gesture))
        {
            HotkeyText = gesture.DisplayText;
            HotkeyError = string.Empty;
            return;
        }

        HotkeyText = "需要 Ctrl、Alt 或 Win 修饰键";
    }

    public void CancelHotkeyCapture()
    {
        HotkeyError = string.Empty;
        HotkeyText = HotkeyGesture.ParseOrDefault(_settings.Hotkey).DisplayText;
    }

    public void ReportHotkeyError(string message)
    {
        HotkeyError = message;
    }

    public async Task<bool> ApplyHotkeyAsync(HotkeyGesture gesture)
    {
        ArgumentNullException.ThrowIfNull(gesture);

        if (IsRecording)
        {
            HotkeyError = "请先结束当前录音，再修改全局快捷键。";
            return false;
        }

        var previousSettings = _settings;
        var previousGesture = HotkeyGesture.ParseOrDefault(_settings.Hotkey);

        try
        {
            _voiceCaptureCoordinator.UpdateHotkey(gesture);
            var updatedSettings = (_settings with
            {
                SchemaVersion = AppSettings.CurrentSchemaVersion,
                Hotkey = gesture.ToSettingString()
            }).Normalize();

            await _settingsStore.SaveAsync(updatedSettings);
            _settings = updatedSettings;
            HotkeyText = gesture.DisplayText;
            HotkeyError = string.Empty;
            return true;
        }
        catch (Exception exception)
        {
            _logger.LogError(exception, "Unable to update the global hotkey.");

            try
            {
                _voiceCaptureCoordinator.UpdateHotkey(previousGesture);
            }
            catch (Exception rollbackException)
            {
                _logger.LogError(rollbackException, "Unable to restore the previous global hotkey.");
            }

            _settings = previousSettings;
            HotkeyText = previousGesture.DisplayText;
            HotkeyError = $"快捷键修改失败：{exception.Message}";
            return false;
        }
    }

    public Task<bool> RestoreDefaultHotkeyAsync()
    {
        return ApplyHotkeyAsync(HotkeyGesture.Default);
    }

    [RelayCommand]
    private async Task ToggleRecordingAsync()
    {
        try
        {
            if (IsRecording)
            {
                await _voiceCaptureCoordinator.StopAsync();
                return;
            }

            IsExpanded = true;
            await _voiceCaptureCoordinator.StartAsync();
        }
        catch (Exception exception)
        {
            _logger.LogError(exception, "Unable to toggle voice capture.");
            HasError = true;
            StatusTitle = "录音失败";
            StatusDetail = exception.Message;
            StatusCode = "ERROR";
        }
    }

    [RelayCommand]
    private void ToggleExpanded()
    {
        if (IsRecording)
        {
            IsExpanded = true;
            return;
        }

        IsExpanded = !IsExpanded;
        _settings = (_settings with { IsExpanded = IsExpanded }).Normalize();
        _ = PersistSettingsAsync();
    }

    [RelayCommand]
    private void OpenSettings()
    {
        SettingsRequested?.Invoke(this, EventArgs.Empty);
    }

    [RelayCommand]
    private void ToggleTopmost()
    {
        IsTopmost = !IsTopmost;
    }

    [RelayCommand]
    private void Exit()
    {
        CloseRequested?.Invoke(this, EventArgs.Empty);
    }

    [RelayCommand]
    private void OpenRecordingsFolder()
    {
        Directory.CreateDirectory(AppPaths.RecordingsDirectory);
        Process.Start(new ProcessStartInfo
        {
            FileName = AppPaths.RecordingsDirectory,
            UseShellExecute = true
        });
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        _voiceCaptureCoordinator.StateChanged -= OnVoiceCaptureStateChanged;
        _voiceCaptureCoordinator.LevelChanged -= OnAudioLevelChanged;
    }

    partial void OnIsExpandedChanged(bool value)
    {
        if (value is false && IsRecording)
        {
            IsExpanded = true;
            return;
        }

        OnPropertyChanged(nameof(WindowWidth));
        OnPropertyChanged(nameof(WindowHeight));
    }

    partial void OnAudioLevelChanged(double value)
    {
        OnPropertyChanged(nameof(AudioLevelPercent));
    }

    partial void OnIsTopmostChanged(bool value)
    {
        if (_isInitializing)
        {
            return;
        }

        _settings = (_settings with { IsTopmost = value }).Normalize();
        _ = PersistSettingsAsync();
    }

    partial void OnSelectedMicrophoneChanged(AudioDeviceDescriptor? value)
    {
        if (_isInitializing)
        {
            return;
        }

        _settings = (_settings with
        {
            PreferredMicrophoneDeviceId = value?.Id ?? string.Empty
        }).Normalize();

        if (!IsRecording)
        {
            StatusDetail = value?.DisplayName ?? "默认麦克风";
        }

        _ = PersistSettingsAsync();
    }

    private void OnVoiceCaptureStateChanged(object? sender, VoiceCaptureStateChangedEventArgs e)
    {
        RunOnUiThread(() => ApplySnapshot(e.Snapshot));
    }

    private void OnAudioLevelChanged(object? sender, AudioLevelChangedEventArgs e)
    {
        RunOnUiThread(() => AudioLevel = e.Level);
    }

    private void ApplySnapshot(VoiceCaptureSnapshot snapshot)
    {
        IsRecording = snapshot.State == VoiceCaptureState.Recording;
        IsCaptured = snapshot.State == VoiceCaptureState.Captured;
        HasError = snapshot.State == VoiceCaptureState.Faulted;
        if (IsRecording)
        {
            IsExpanded = true;
        }

        AudioLevel = IsRecording ? AudioLevel : 0;
        ElapsedText = FormatDuration(snapshot.Elapsed);
        MicrophoneActionLabel = IsRecording ? "结束录音" : "开始录音";

        switch (snapshot.State)
        {
            case VoiceCaptureState.Idle:
                StatusTitle = "准备就绪";
                StatusDetail = SelectedMicrophone?.DisplayName ?? "默认麦克风";
                StatusCode = "IDLE";
                break;
            case VoiceCaptureState.Recording:
                StatusTitle = "正在聆听";
                StatusDetail = SelectedMicrophone?.DisplayName ?? "默认麦克风";
                StatusCode = "REC";
                break;
            case VoiceCaptureState.Captured:
                StatusTitle = "录音已保存";
                StatusDetail = $"{FormatDuration(snapshot.Elapsed)} · 已保存到本机";
                StatusCode = "SAVED";
                LastRecordingPath = snapshot.RecordingPath ?? string.Empty;
                break;
            case VoiceCaptureState.Faulted:
                StatusTitle = "需要处理";
                StatusDetail = snapshot.ErrorMessage ?? "录音暂不可用";
                StatusCode = "ERROR";
                break;
        }
    }

    private async Task PersistSettingsAsync()
    {
        try
        {
            await _settingsStore.SaveAsync(_settings);
        }
        catch (Exception exception)
        {
            _logger.LogWarning(exception, "Unable to save application settings.");
        }
    }

    private static string FormatDuration(TimeSpan duration)
    {
        var totalMinutes = Math.Max(0, (int)duration.TotalMinutes);
        return $"{totalMinutes:00}:{duration.Seconds:00}";
    }

    private static string FormatHotkey(string hotkey)
    {
        return hotkey.Replace("+", " + ", StringComparison.Ordinal);
    }

    private static void RunOnUiThread(Action action)
    {
        var dispatcher = System.Windows.Application.Current?.Dispatcher;
        if (dispatcher is null || dispatcher.CheckAccess())
        {
            action();
            return;
        }

        dispatcher.BeginInvoke(action);
    }
}

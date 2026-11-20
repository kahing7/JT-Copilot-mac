using JT.Copilot.Application.Abstractions;
using JT.Copilot.Application.Models;
using JT.Copilot.Application.Services;
using JT.Copilot.Domain.Enums;

namespace JT.Copilot.UnitTests;

public sealed class VoiceCaptureCoordinatorTests
{
    [Fact]
    public async Task StartAndStop_CapturesRecordingAndPublishesSavedState()
    {
        var audio = new FakeAudioCaptureService();
        var hotkey = new FakeGlobalHotkeyService();
        using var coordinator = new VoiceCaptureCoordinator(audio, hotkey, new FakeSettingsStore());

        await coordinator.InitializeAsync();
        await coordinator.StartAsync();
        await coordinator.StopAsync();

        Assert.Equal(VoiceCaptureState.Captured, coordinator.Current.State);
        Assert.Equal(TimeSpan.FromSeconds(2), coordinator.Current.Elapsed);
        Assert.Equal("recording.wav", coordinator.Current.RecordingPath);
        Assert.Equal(1, audio.StartCount);
        Assert.Equal(1, audio.StopCount);
    }

    [Fact]
    public async Task Start_WhenAudioProviderFails_PublishesFaultedState()
    {
        var audio = new FakeAudioCaptureService
        {
            StartException = new InvalidOperationException("microphone unavailable")
        };
        using var coordinator = new VoiceCaptureCoordinator(
            audio,
            new FakeGlobalHotkeyService(),
            new FakeSettingsStore());

        await coordinator.InitializeAsync();
        await coordinator.StartAsync();

        Assert.Equal(VoiceCaptureState.Faulted, coordinator.Current.State);
        Assert.Contains("microphone unavailable", coordinator.Current.ErrorMessage);
    }

    [Fact]
    public async Task Cancel_ReturnsToIdleAndCancelsAudio()
    {
        var audio = new FakeAudioCaptureService();
        using var coordinator = new VoiceCaptureCoordinator(
            audio,
            new FakeGlobalHotkeyService(),
            new FakeSettingsStore());

        await coordinator.InitializeAsync();
        await coordinator.StartAsync();
        await coordinator.CancelAsync();

        Assert.Equal(VoiceCaptureState.Idle, coordinator.Current.State);
        Assert.Equal(1, audio.CancelCount);
    }

    private sealed class FakeSettingsStore : IAppSettingsStore
    {
        public Task<AppSettings> LoadAsync(CancellationToken cancellationToken = default)
        {
            return Task.FromResult(new AppSettings());
        }

        public Task SaveAsync(AppSettings settings, CancellationToken cancellationToken = default)
        {
            return Task.CompletedTask;
        }
    }

    private sealed class FakeGlobalHotkeyService : IGlobalHotkeyService
    {
        public event EventHandler? Pressed;

        public event EventHandler? Released;

        public event EventHandler? CancelRequested;

        public bool IsRunning { get; private set; }

        public void Start()
        {
            IsRunning = true;
        }

        public void Stop()
        {
            IsRunning = false;
        }

        public void Dispose()
        {
            Stop();
        }

        public void RaisePressed() => Pressed?.Invoke(this, EventArgs.Empty);

        public void RaiseReleased() => Released?.Invoke(this, EventArgs.Empty);

        public void RaiseCancelRequested() => CancelRequested?.Invoke(this, EventArgs.Empty);
    }

    private sealed class FakeAudioCaptureService : IAudioCaptureService
    {
        public event EventHandler<AudioLevelChangedEventArgs>? LevelChanged
        {
            add { }
            remove { }
        }

        public Exception? StartException { get; init; }

        public bool IsCapturing { get; private set; }

        public int StartCount { get; private set; }

        public int StopCount { get; private set; }

        public int CancelCount { get; private set; }

        public IReadOnlyList<AudioDeviceDescriptor> GetInputDevices()
        {
            return [new AudioDeviceDescriptor("0", "Test microphone", true)];
        }

        public Task StartAsync(string? deviceId, CancellationToken cancellationToken = default)
        {
            StartCount++;
            if (StartException is not null)
            {
                throw StartException;
            }

            IsCapturing = true;
            return Task.CompletedTask;
        }

        public Task<AudioCaptureResult> StopAsync(CancellationToken cancellationToken = default)
        {
            StopCount++;
            IsCapturing = false;
            return Task.FromResult(new AudioCaptureResult("recording.wav", TimeSpan.FromSeconds(2)));
        }

        public void Cancel()
        {
            CancelCount++;
            IsCapturing = false;
        }

        public void Dispose()
        {
            IsCapturing = false;
        }
    }
}

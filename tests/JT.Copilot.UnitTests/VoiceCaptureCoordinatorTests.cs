using JT.Copilot.Application.Abstractions;
using JT.Copilot.Application.Hotkeys;
using JT.Copilot.Application.Models;
using JT.Copilot.Application.Services;
using JT.Copilot.Domain.Enums;

namespace JT.Copilot.UnitTests;

public sealed class VoiceCaptureCoordinatorTests
{
    [Fact]
    public async Task StartAndFinish_CompletesSessionWithoutLosingRecording()
    {
        var audio = new FakeAudioCaptureService();
        var hotkey = new FakeGlobalHotkeyService();
        using var coordinator = CreateCoordinator(audio, hotkey);

        await coordinator.InitializeAsync();
        await coordinator.StartAsync();
        await coordinator.FinishAsync();

        Assert.Equal(VoiceCaptureState.Completed, coordinator.Current.State);
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
        using var coordinator = CreateCoordinator(audio, new FakeGlobalHotkeyService());

        await coordinator.InitializeAsync();
        await coordinator.StartAsync();

        Assert.Equal(VoiceCaptureState.Faulted, coordinator.Current.State);
        Assert.Contains("microphone unavailable", coordinator.Current.ErrorMessage);
    }

    [Fact]
    public async Task Cancel_ReturnsToIdleAndCancelsAudio()
    {
        var audio = new FakeAudioCaptureService();
        using var coordinator = CreateCoordinator(audio, new FakeGlobalHotkeyService());

        await coordinator.InitializeAsync();
        await coordinator.StartAsync();
        await coordinator.CancelAsync();

        Assert.Equal(VoiceCaptureState.Idle, coordinator.Current.State);
        Assert.Equal(1, audio.CancelCount);
    }

    private static VoiceCaptureCoordinator CreateCoordinator(
        FakeAudioCaptureService audio,
        FakeGlobalHotkeyService hotkey)
    {
        return new VoiceCaptureCoordinator(
            audio,
            hotkey,
            new FakeSettingsStore(),
            new FakeSpeechRecognitionProvider(),
            new FakeStreamingSpeechRecognitionProvider(),
            new FakeWritingModelProvider(),
            new FakeTextInsertionService());
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

        public bool CaptureEscape { get; set; }

        public HotkeyGesture Gesture { get; private set; } = HotkeyGesture.Default;

        public void Start(HotkeyGesture gesture)
        {
            Gesture = gesture;
            IsRunning = true;
        }

        public void Reconfigure(HotkeyGesture gesture)
        {
            Gesture = gesture;
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

        public event EventHandler<PcmAudioDataEventArgs>? PcmDataAvailable
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

    private sealed class FakeSpeechRecognitionProvider : ISpeechRecognitionProvider
    {
        public Task<string> TranscribeAsync(
            ReadOnlyMemory<byte> wavAudio,
            string transcriptContext,
            CancellationToken cancellationToken = default)
        {
            return Task.FromResult(string.Empty);
        }
    }

    private sealed class FakeStreamingSpeechRecognitionProvider : IStreamingSpeechRecognitionProvider
    {
        public event EventHandler<LiveTranscriptEventArgs>? TranscriptChanged
        {
            add { }
            remove { }
        }

        public bool IsAvailable => false;

        public Task<bool> InitializeAsync(CancellationToken cancellationToken = default)
        {
            return Task.FromResult(false);
        }

        public void StartSession()
        {
        }

        public void PushAudio(ReadOnlyMemory<byte> pcmAudio)
        {
        }

        public string EndSession()
        {
            return string.Empty;
        }

        public void Dispose()
        {
        }
    }

    private sealed class FakeWritingModelProvider : IWritingModelProvider
    {
        public Task<WritingGuidance> AnalyzeAsync(
            string transcript,
            WritingGuidance? previousGuidance,
            CancellationToken cancellationToken = default)
        {
            return Task.FromResult(WritingGuidance.Empty);
        }

        public Task<string> OptimizeAsync(
            string transcript,
            CancellationToken cancellationToken = default)
        {
            return Task.FromResult(transcript);
        }

        public Task<string> OptimizeSegmentsAsync(
            IReadOnlyList<string> transcriptSegments,
            CancellationToken cancellationToken = default)
        {
            return Task.FromResult(string.Join(string.Empty, transcriptSegments));
        }
    }

    private sealed class FakeTextInsertionService : ITextInsertionService
    {
        public Task<ITextInsertionTarget?> CaptureTargetAsync(
            CancellationToken cancellationToken = default)
        {
            return Task.FromResult<ITextInsertionTarget?>(new FakeTextInsertionTarget());
        }

        public Task<TextInsertionResult> InsertAsync(
            string text,
            ITextInsertionTarget target,
            CancellationToken cancellationToken = default)
        {
            return Task.FromResult(TextInsertionResult.Succeeded);
        }

        public Task<TextInsertionResult> UpdateLiveDraftAsync(
            string previousText,
            string currentText,
            ITextInsertionTarget target,
            CancellationToken cancellationToken = default)
        {
            return Task.FromResult(TextInsertionResult.Succeeded);
        }

        public Task<TextReplacementResult> ReplaceSessionTextAsync(
            string expectedText,
            string replacementText,
            ITextInsertionTarget target,
            CancellationToken cancellationToken = default)
        {
            return Task.FromResult(TextReplacementResult.Succeeded);
        }
    }

    private sealed class FakeTextInsertionTarget : ITextInsertionTarget
    {
        public bool IsActive => true;

        public string DisplayName => "Fake editor";

        public void Dispose()
        {
        }
    }
}

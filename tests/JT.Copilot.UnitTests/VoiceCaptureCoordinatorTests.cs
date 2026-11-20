using JT.Copilot.Application.Abstractions;
using JT.Copilot.Application.Guidance;
using JT.Copilot.Application.Hotkeys;
using JT.Copilot.Application.Models;
using JT.Copilot.Application.Services;
using JT.Copilot.Application.Text;
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

    [Fact]
    public async Task Start_WithManualTemplate_PublishesFirstPromptBeforeSpeech()
    {
        using var coordinator = CreateCoordinator(
            new FakeAudioCaptureService(),
            new FakeGlobalHotkeyService());

        await coordinator.InitializeAsync();
        coordinator.UpdateDocumentTemplate(DocumentTemplate.ProjectManagement);
        await coordinator.StartAsync();

        Assert.Equal(
            "先交代一下项目背景",
            coordinator.CurrentWritingSession.Guidance.NextSentence);
        Assert.Equal(
            DocumentTemplate.ProjectManagement,
            coordinator.CurrentWritingSession.Guidance.Template);
        await coordinator.CancelAsync();
    }

    [Fact]
    public async Task LivePartial_CorrectsTermsAndPublishesLocalPromptBeforeNetworkAnalysis()
    {
        var streaming = new FakeStreamingSpeechRecognitionProvider(available: true);
        var writingModel = new FakeWritingModelProvider();
        var insertion = new FakeTextInsertionService();
        using var coordinator = CreateCoordinator(
            new FakeAudioCaptureService(),
            new FakeGlobalHotkeyService(),
            streaming,
            writingModel,
            insertion);
        var localUpdate = new TaskCompletionSource<WritingSessionUpdate>(
            TaskCreationOptions.RunContinuationsAsynchronously);
        coordinator.WritingSessionChanged += (_, args) =>
        {
            if (args.Update.StableTranscript.Contains("CRM系统", StringComparison.Ordinal)
                && args.Update.Guidance.NextSentence == "先交代一下项目背景")
            {
                localUpdate.TrySetResult(args.Update);
            }
        };

        await coordinator.InitializeAsync();
        await coordinator.StartAsync();
        streaming.RaiseTranscript(
            "我们的新奥尔良系统支持积分队里区，我要写一篇项目管理文档",
            isFinal: false);

        var update = await localUpdate.Task.WaitAsync(TimeSpan.FromSeconds(2));

        Assert.Contains("CRM系统", update.StableTranscript);
        Assert.Contains("积分兑礼", update.StableTranscript);
        Assert.Equal("先交代一下项目背景", update.Guidance.NextSentence);
        Assert.Equal(0, writingModel.AnalyzeCount);
        Assert.Contains("CRM系统", insertion.LastCurrentText);
        Assert.Contains("积分兑礼", insertion.LastCurrentText);
    }

    [Fact]
    public async Task NetworkSupplement_DoesNotOverwriteLocalNextSentence()
    {
        var streaming = new FakeStreamingSpeechRecognitionProvider(available: true);
        var writingModel = new FakeWritingModelProvider
        {
            GuidanceResponse = new WritingGuidance(
                ["网络框架"],
                "网络覆盖的下一句",
                ["补充一个具体案例"],
                ["补充风险应对"])
        };
        using var coordinator = CreateCoordinator(
            new FakeAudioCaptureService(),
            new FakeGlobalHotkeyService(),
            streaming,
            writingModel);
        var localUpdate = new TaskCompletionSource<WritingSessionUpdate>(
            TaskCreationOptions.RunContinuationsAsynchronously);
        var supplementedUpdate = new TaskCompletionSource<WritingSessionUpdate>(
            TaskCreationOptions.RunContinuationsAsynchronously);
        coordinator.WritingSessionChanged += (_, args) =>
        {
            if (args.Update.StableTranscript.Contains("项目管理文档", StringComparison.Ordinal)
                && args.Update.Guidance.NextSentence == "先交代一下项目背景")
            {
                localUpdate.TrySetResult(args.Update);
            }

            if (args.Update.Guidance.MissingPoints.Contains("补充风险应对"))
            {
                supplementedUpdate.TrySetResult(args.Update);
            }
        };

        await coordinator.InitializeAsync();
        await coordinator.StartAsync();
        streaming.RaiseTranscript("我要写一篇项目管理文档", isFinal: false);

        var local = await localUpdate.Task.WaitAsync(TimeSpan.FromSeconds(2));
        var supplemented = await supplementedUpdate.Task.WaitAsync(TimeSpan.FromSeconds(3));

        Assert.Equal("先交代一下项目背景", local.Guidance.NextSentence);
        Assert.Equal(local.Guidance.NextSentence, supplemented.Guidance.NextSentence);
        Assert.Contains("补充一个具体案例", supplemented.Guidance.Directions);
        Assert.Contains("补充风险应对", supplemented.Guidance.MissingPoints);
    }

    private static VoiceCaptureCoordinator CreateCoordinator(
        FakeAudioCaptureService audio,
        FakeGlobalHotkeyService hotkey,
        FakeStreamingSpeechRecognitionProvider? streaming = null,
        FakeWritingModelProvider? writingModel = null,
        FakeTextInsertionService? textInsertion = null)
    {
        return new VoiceCaptureCoordinator(
            audio,
            hotkey,
            new FakeSettingsStore(),
            new FakeSpeechRecognitionProvider(),
            streaming ?? new FakeStreamingSpeechRecognitionProvider(),
            writingModel ?? new FakeWritingModelProvider(),
            new LocalDocumentFrameworkEngine(),
            new DomainTermCorrector(),
            textInsertion ?? new FakeTextInsertionService());
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

    private sealed class FakeStreamingSpeechRecognitionProvider(bool available = false)
        : IStreamingSpeechRecognitionProvider
    {
        public event EventHandler<LiveTranscriptEventArgs>? TranscriptChanged;

        public bool IsAvailable => available;

        public Task<bool> InitializeAsync(CancellationToken cancellationToken = default)
        {
            return Task.FromResult(available);
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

        public void RaiseTranscript(string text, bool isFinal)
        {
            TranscriptChanged?.Invoke(this, new LiveTranscriptEventArgs(text, isFinal));
        }
    }

    private sealed class FakeWritingModelProvider : IWritingModelProvider
    {
        public int AnalyzeCount { get; private set; }

        public WritingGuidance GuidanceResponse { get; init; } = WritingGuidance.Empty;

        public Task<WritingGuidance> AnalyzeAsync(
            string transcript,
            WritingGuidance? previousGuidance,
            CancellationToken cancellationToken = default)
        {
            AnalyzeCount++;
            return Task.FromResult(GuidanceResponse);
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
        public string LastCurrentText { get; private set; } = string.Empty;

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
            LastCurrentText = currentText;
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

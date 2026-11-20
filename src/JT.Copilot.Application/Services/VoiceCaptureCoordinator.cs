using System.Diagnostics;
using System.Text;
using JT.Copilot.Application.Abstractions;
using JT.Copilot.Application.Hotkeys;
using JT.Copilot.Application.Models;
using JT.Copilot.Application.Text;
using JT.Copilot.Domain.Enums;

namespace JT.Copilot.Application.Services;

public sealed class VoiceCaptureCoordinator : IVoiceCaptureCoordinator
{
    private const int SampleRate = 16_000;
    private const int BitsPerSample = 16;
    private const int Channels = 1;
    private const double SpeechThreshold = 0.045;
    private const int SegmentOverlapBytes = SampleRate * (BitsPerSample / 8) * 45 / 100;
    private static readonly TimeSpan SilenceBeforeSegment = TimeSpan.FromMilliseconds(550);
    private static readonly TimeSpan MaxSegmentLength = TimeSpan.FromMilliseconds(3_800);
    private static readonly TimeSpan MinimumSpeechLength = TimeSpan.FromMilliseconds(350);

    private readonly IAudioCaptureService _audioCaptureService;
    private readonly IGlobalHotkeyService _globalHotkeyService;
    private readonly IAppSettingsStore _settingsStore;
    private readonly ISpeechRecognitionProvider _speechRecognitionProvider;
    private readonly IStreamingSpeechRecognitionProvider _streamingSpeechRecognitionProvider;
    private readonly IWritingModelProvider _writingModelProvider;
    private readonly IDocumentFrameworkEngine _documentFrameworkEngine;
    private readonly DomainTermCorrector _domainTermCorrector;
    private readonly ITextInsertionService _textInsertionService;
    private readonly SemaphoreSlim _stateGate = new(1, 1);
    private readonly object _timerLock = new();
    private readonly object _segmentLock = new();
    private readonly object _chainLock = new();
    private readonly object _transcriptLock = new();
    private readonly object _liveQueueLock = new();

    private readonly MemoryStream _segmentPcm = new();
    private readonly StringBuilder _stableTranscript = new();
    private readonly List<string> _segmentTexts = [];
    private readonly Queue<LiveTranscriptEventArgs> _liveTranscriptQueue = new();

    private Timer? _elapsedTimer;
    private Task _segmentChain = Task.CompletedTask;
    private CancellationTokenSource? _sessionCancellation;
    private CancellationTokenSource? _analysisCancellation;
    private Task<bool>? _streamingInitializationTask;
    private ITextInsertionTarget? _insertionTarget;
    private WritingGuidance _guidance = WritingGuidance.Empty;
    private DateTimeOffset _segmentStartedAt;
    private DateTimeOffset _lastVoiceDetectedAt;
    private long _recordingStartedAt;
    private int _sessionGeneration;
    private string _draftTranscript = string.Empty;
    private string _optimizedTranscript = string.Empty;
    private string _replacementMessage = string.Empty;
    private string _statusMessage = string.Empty;
    private string _liveCommittedText = string.Empty;
    private string _liveSessionText = string.Empty;
    private string _customVocabulary = string.Empty;
    private string _supplementalGuidanceKey = string.Empty;
    private IReadOnlyList<string> _supplementalDirections = [];
    private IReadOnlyList<string> _supplementalMissingPoints = [];
    private DocumentTemplate _documentTemplate = DocumentTemplate.Auto;
    private bool _hasSpeech;
    private bool _liveRecognitionAvailable;
    private bool _liveWorkerRunning;
    private bool _initialized;
    private bool _finishing;
    private bool _disposed;

    public VoiceCaptureCoordinator(
        IAudioCaptureService audioCaptureService,
        IGlobalHotkeyService globalHotkeyService,
        IAppSettingsStore settingsStore,
        ISpeechRecognitionProvider speechRecognitionProvider,
        IStreamingSpeechRecognitionProvider streamingSpeechRecognitionProvider,
        IWritingModelProvider writingModelProvider,
        IDocumentFrameworkEngine documentFrameworkEngine,
        DomainTermCorrector domainTermCorrector,
        ITextInsertionService textInsertionService)
    {
        _audioCaptureService = audioCaptureService;
        _globalHotkeyService = globalHotkeyService;
        _settingsStore = settingsStore;
        _speechRecognitionProvider = speechRecognitionProvider;
        _streamingSpeechRecognitionProvider = streamingSpeechRecognitionProvider;
        _writingModelProvider = writingModelProvider;
        _documentFrameworkEngine = documentFrameworkEngine;
        _domainTermCorrector = domainTermCorrector;
        _textInsertionService = textInsertionService;

        _globalHotkeyService.Pressed += OnHotkeyPressed;
        _globalHotkeyService.CancelRequested += OnEscapePressed;
        _audioCaptureService.LevelChanged += OnAudioLevelChanged;
        _audioCaptureService.PcmDataAvailable += OnPcmDataAvailable;
        _streamingSpeechRecognitionProvider.TranscriptChanged += OnLiveTranscriptChanged;
    }

    public event EventHandler<VoiceCaptureStateChangedEventArgs>? StateChanged;

    public event EventHandler<AudioLevelChangedEventArgs>? LevelChanged;

    public event EventHandler<WritingSessionUpdateEventArgs>? WritingSessionChanged;

    public VoiceCaptureSnapshot Current { get; private set; } = VoiceCaptureSnapshot.Idle;

    public WritingSessionUpdate CurrentWritingSession { get; private set; } =
        new(
            string.Empty,
            string.Empty,
            WritingGuidance.Empty,
            string.Empty);

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
            _customVocabulary = settings.CustomVocabulary;
            _documentTemplate = settings.GuidanceTemplate;
            _globalHotkeyService.Start(HotkeyGesture.ParseOrDefault(settings.Hotkey));
            _streamingInitializationTask ??= _streamingSpeechRecognitionProvider.InitializeAsync();
            _initialized = true;
        }
        catch (Exception exception)
        {
            PublishState(new VoiceCaptureSnapshot(
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
            if (Current.State is VoiceCaptureState.Recording or VoiceCaptureState.Processing)
            {
                return;
            }

            ResetSession();
            PublishSessionUpdate("正在准备本地实时识别...");
            _liveRecognitionAvailable = _streamingInitializationTask is not null
                && await _streamingInitializationTask.ConfigureAwait(false);

            if (_liveRecognitionAvailable)
            {
                _streamingSpeechRecognitionProvider.StartSession();
            }
            else
            {
                PublishSessionUpdate("本地实时引擎不可用，已回退到智谱分片识别。");
            }

            _insertionTarget = await _textInsertionService
                .CaptureTargetAsync(cancellationToken)
                .ConfigureAwait(false);

            if (_insertionTarget is null)
            {
                PublishSessionUpdate("无法锁定当前编辑器，请先把光标放到飞书、Word 或文本编辑器中。");
                PublishState(new VoiceCaptureSnapshot(
                    VoiceCaptureState.Faulted,
                    TimeSpan.Zero,
                    ErrorMessage: "无法锁定当前编辑器。"));
                return;
            }

            var settings = await _settingsStore.LoadAsync(cancellationToken).ConfigureAwait(false);
            await _audioCaptureService
                .StartAsync(settings.PreferredMicrophoneDeviceId, cancellationToken)
                .ConfigureAwait(false);

            _recordingStartedAt = Stopwatch.GetTimestamp();
            _segmentStartedAt = DateTimeOffset.UtcNow;
            _lastVoiceDetectedAt = _segmentStartedAt;
            _globalHotkeyService.CaptureEscape = true;
            StartElapsedTimer();

            PublishSessionUpdate($"正在聆听 · {_insertionTarget.DisplayName}");
            PublishState(new VoiceCaptureSnapshot(
                VoiceCaptureState.Recording,
                TimeSpan.Zero));
            RefreshLocalGuidance(string.Empty, _sessionGeneration);
        }
        catch (Exception exception)
        {
            CleanupFailedSession();
            PublishState(new VoiceCaptureSnapshot(
                VoiceCaptureState.Faulted,
                TimeSpan.Zero,
                ErrorMessage: exception.Message));
        }
        finally
        {
            _stateGate.Release();
        }
    }

    public Task StopAsync(CancellationToken cancellationToken = default)
    {
        return FinishAsync(cancellationToken);
    }

    public async Task FinishAsync(CancellationToken cancellationToken = default)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        await _stateGate.WaitAsync(cancellationToken).ConfigureAwait(false);

        try
        {
            if (Current.State != VoiceCaptureState.Recording || _finishing)
            {
                return;
            }

            _finishing = true;
            _globalHotkeyService.CaptureEscape = false;
            StopElapsedTimer();
            CancelAnalysis();
            PublishSessionUpdate("正在提交最后一段语音...");
            PublishState(new VoiceCaptureSnapshot(
                VoiceCaptureState.Processing,
                Stopwatch.GetElapsedTime(_recordingStartedAt)));

            try
            {
                await _audioCaptureService.StopAsync(cancellationToken).ConfigureAwait(false);
            }
            finally
            {
                CapturePendingSegment(force: true);
            }

            var generation = _sessionGeneration;
            var finalLiveText = _streamingSpeechRecognitionProvider.EndSession();
            await DrainLiveTranscriptQueueAsync().ConfigureAwait(false);
            if (!string.IsNullOrWhiteSpace(finalLiveText))
            {
                await ApplyLiveTextAsync(finalLiveText, isFinal: true, generation).ConfigureAwait(false);
            }

            Task segmentChain;
            lock (_chainLock)
            {
                segmentChain = _segmentChain;
            }

            await segmentChain.ConfigureAwait(false);
            await CompleteSessionAsync(cancellationToken).ConfigureAwait(false);
        }
        catch (Exception exception)
        {
            PublishSessionUpdate($"会话收尾失败：{exception.Message}");
            PublishState(new VoiceCaptureSnapshot(
                VoiceCaptureState.Faulted,
                TimeSpan.Zero,
                ErrorMessage: exception.Message));
        }
        finally
        {
            _finishing = false;
            _stateGate.Release();
        }
    }

    public async Task CancelAsync(CancellationToken cancellationToken = default)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        await _stateGate.WaitAsync(cancellationToken).ConfigureAwait(false);

        try
        {
            _globalHotkeyService.CaptureEscape = false;
            StopElapsedTimer();
            CancelAnalysis();
            _sessionCancellation?.Cancel();
            _audioCaptureService.Cancel();
            _ = _streamingSpeechRecognitionProvider.EndSession();
            ResetBuffers();
            _insertionTarget?.Dispose();
            _insertionTarget = null;
            PublishSessionUpdate("录音已取消。");
            PublishState(VoiceCaptureSnapshot.Idle);
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

        if (Current.State is VoiceCaptureState.Recording or VoiceCaptureState.Processing)
        {
            throw new InvalidOperationException("请先结束当前写作会话，再修改全局快捷键。");
        }

        _globalHotkeyService.Reconfigure(gesture);
    }

    public void UpdateDocumentTemplate(DocumentTemplate template)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        if (!Enum.IsDefined(template) || template == DocumentTemplate.General)
        {
            template = DocumentTemplate.Auto;
        }

        _documentTemplate = template;
        if (Current.State is VoiceCaptureState.Recording or VoiceCaptureState.Processing)
        {
            RefreshLocalGuidance(GetDocumentTranscript(), _sessionGeneration);
        }
    }

    public void UpdateCustomVocabulary(string customVocabulary)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        _customVocabulary = customVocabulary?.Trim() ?? string.Empty;
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        StopElapsedTimer();
        CancelAnalysis();
        _sessionCancellation?.Cancel();
        _sessionCancellation?.Dispose();
        _globalHotkeyService.Pressed -= OnHotkeyPressed;
        _globalHotkeyService.CancelRequested -= OnEscapePressed;
        _audioCaptureService.LevelChanged -= OnAudioLevelChanged;
        _audioCaptureService.PcmDataAvailable -= OnPcmDataAvailable;
        _streamingSpeechRecognitionProvider.TranscriptChanged -= OnLiveTranscriptChanged;
        _insertionTarget?.Dispose();
        _segmentPcm.Dispose();
        _stateGate.Dispose();
    }

    private void OnHotkeyPressed(object? sender, EventArgs e)
    {
        if (Current.State is VoiceCaptureState.Recording or VoiceCaptureState.Processing)
        {
            return;
        }

        _ = StartAsync();
    }

    private void OnEscapePressed(object? sender, EventArgs e)
    {
        if (Current.State == VoiceCaptureState.Recording)
        {
            _ = FinishAsync();
        }
    }

    private void OnAudioLevelChanged(object? sender, AudioLevelChangedEventArgs e)
    {
        LevelChanged?.Invoke(this, e);
    }

    private void OnPcmDataAvailable(object? sender, PcmAudioDataEventArgs e)
    {
        if (Current.State != VoiceCaptureState.Recording)
        {
            return;
        }

        lock (_segmentLock)
        {
            if (_liveRecognitionAvailable)
            {
                _streamingSpeechRecognitionProvider.PushAudio(e.PcmData);
            }

            _segmentPcm.Write(e.PcmData.Span);
            var now = DateTimeOffset.UtcNow;

            if (e.Level >= SpeechThreshold)
            {
                _hasSpeech = true;
                _lastVoiceDetectedAt = now;
            }

            var segmentLength = now - _segmentStartedAt;
            var silenceLength = now - _lastVoiceDetectedAt;
            if (_hasSpeech
                && (silenceLength >= SilenceBeforeSegment || segmentLength >= MaxSegmentLength))
            {
                CaptureSegmentLocked();
            }
        }
    }

    private void CapturePendingSegment(bool force)
    {
        lock (_segmentLock)
        {
            if (force || _hasSpeech)
            {
                CaptureSegmentLocked();
            }
            else
            {
                ResetSegmentBuffer();
            }
        }
    }

    private void CaptureSegmentLocked()
    {
        var pcm = _segmentPcm.ToArray();
        var segmentDuration = DateTimeOffset.UtcNow - _segmentStartedAt;
        var hadSpeech = _hasSpeech;
        var overlap = hadSpeech && pcm.Length > SegmentOverlapBytes
            ? pcm[^SegmentOverlapBytes..]
            : [];
        ResetSegmentBuffer(overlap);

        if (!hadSpeech
            || pcm.Length < SampleRate * (BitsPerSample / 8) * MinimumSpeechLength.TotalSeconds)
        {
            return;
        }

        if (segmentDuration < MinimumSpeechLength)
        {
            return;
        }

        var generation = _sessionGeneration;
        var wav = CreateWaveFile(pcm);
        lock (_chainLock)
        {
            var previous = _segmentChain;
            _segmentChain = ProcessSegmentAfterAsync(previous, wav, generation);
        }
    }

    private async Task ProcessSegmentAfterAsync(
        Task previous,
        byte[] wavAudio,
        int generation)
    {
        await previous.ConfigureAwait(false);

        if (_disposed
            || generation != _sessionGeneration
            || Current.State is not (VoiceCaptureState.Recording or VoiceCaptureState.Processing))
        {
            return;
        }

        try
        {
            var token = _sessionCancellation?.Token ?? CancellationToken.None;
            var segmentText = _domainTermCorrector.Correct(
                await _speechRecognitionProvider
                    .TranscribeAsync(wavAudio, BuildRecognitionPrompt(), token)
                    .ConfigureAwait(false),
                _customVocabulary).Trim();

            if (string.IsNullOrWhiteSpace(segmentText))
            {
                return;
            }

            lock (_transcriptLock)
            {
                _segmentTexts.Add(segmentText);
            }

            if (_liveRecognitionAvailable)
            {
                RefreshLocalGuidance(GetDocumentTranscript(), generation);
                return;
            }

            var appendedText = AppendTranscript(segmentText);
            if (string.IsNullOrWhiteSpace(appendedText))
            {
                return;
            }

            _draftTranscript = segmentText;
            PublishSessionUpdate("已识别，正在写入...");

            var insertionResult = _insertionTarget is null
                ? new TextInsertionResult(false, "目标编辑器已关闭。")
                : await _textInsertionService
                    .InsertAsync(appendedText, _insertionTarget, token)
                    .ConfigureAwait(false);

            if (!insertionResult.Success)
            {
                PublishSessionUpdate(insertionResult.Message);
            }
            else
            {
                PublishSessionUpdate("文字已写入，正在更新表达框架...");
            }

            RefreshLocalGuidance(GetStableTranscript(), generation);
        }
        catch (OperationCanceledException)
        {
        }
        catch (Exception exception)
        {
            PublishSessionUpdate($"语音识别失败：{exception.Message}");
        }
    }

    private void RefreshLocalGuidance(string transcript, int generation)
    {
        if (generation != _sessionGeneration)
        {
            return;
        }

        var result = _documentFrameworkEngine.Build(transcript, _documentTemplate);
        var guidanceKey = string.Join(
            "\u001F",
            result.Template,
            result.Guidance.NextSentence,
            string.Join("\u001E", result.Guidance.Framework));
        if (!string.Equals(guidanceKey, _supplementalGuidanceKey, StringComparison.Ordinal))
        {
            _supplementalGuidanceKey = guidanceKey;
            _supplementalDirections = [];
            _supplementalMissingPoints = [];
        }

        _guidance = result.Guidance with
        {
            Directions = MergeItems(result.Guidance.Directions, _supplementalDirections, 6),
            MissingPoints = MergeItems(result.Guidance.MissingPoints, _supplementalMissingPoints, 4)
        };

        PublishSessionUpdate(Current.State == VoiceCaptureState.Recording
            ? "正在聆听 · 下一步已同步"
            : "正在整理全文 · 框架已同步");
        QueueSupplementalGuidance(transcript, generation, result.Guidance, guidanceKey);
    }

    private void QueueSupplementalGuidance(
        string transcript,
        int generation,
        WritingGuidance localGuidance,
        string guidanceKey)
    {
        if (string.IsNullOrWhiteSpace(transcript))
        {
            return;
        }

        var cancellation = new CancellationTokenSource();
        var previous = Interlocked.Exchange(ref _analysisCancellation, cancellation);
        previous?.Cancel();
        previous?.Dispose();

        _ = UpdateSupplementalGuidanceAsync(
            transcript,
            generation,
            localGuidance,
            guidanceKey,
            cancellation);
    }

    private async Task UpdateSupplementalGuidanceAsync(
        string transcript,
        int generation,
        WritingGuidance localGuidance,
        string guidanceKey,
        CancellationTokenSource cancellation)
    {
        try
        {
            await Task.Delay(320, cancellation.Token).ConfigureAwait(false);
            var supplemental = await _writingModelProvider
                .AnalyzeAsync(transcript, localGuidance, cancellation.Token)
                .ConfigureAwait(false);

            if (generation != _sessionGeneration
                || !string.Equals(guidanceKey, _supplementalGuidanceKey, StringComparison.Ordinal))
            {
                return;
            }

            _supplementalDirections = supplemental.Directions;
            _supplementalMissingPoints = supplemental.MissingPoints;
            _guidance = _guidance with
            {
                Directions = MergeItems(_guidance.Directions, _supplementalDirections, 6),
                MissingPoints = MergeItems(_guidance.MissingPoints, _supplementalMissingPoints, 4)
            };
            PublishSessionUpdate(Current.State == VoiceCaptureState.Recording
                ? "正在聆听 · 已补充写作方向"
                : "正在整理全文 · 已补充检查项");
        }
        catch (OperationCanceledException)
        {
        }
        catch (Exception exception)
        {
            PublishSessionUpdate($"表达建议暂不可用：{exception.Message}");
        }
        finally
        {
            Interlocked.CompareExchange(ref _analysisCancellation, null, cancellation);
            cancellation.Dispose();
        }
    }

    private static IReadOnlyList<string> MergeItems(
        IReadOnlyList<string> primary,
        IReadOnlyList<string> supplemental,
        int limit)
    {
        return primary
            .Concat(supplemental)
            .Where(item => !string.IsNullOrWhiteSpace(item))
            .Select(item => item.Trim())
            .Distinct(StringComparer.Ordinal)
            .Take(limit)
            .ToArray();
    }

    private string BuildRecognitionPrompt()
    {
        var hotwords = _domainTermCorrector.GetHotwords(_customVocabulary);
        return hotwords.Count == 0
            ? string.Empty
            : $"请准确识别以下业务术语并保留英文缩写：{string.Join("、", hotwords)}";
    }

    private async Task CompleteSessionAsync(CancellationToken cancellationToken)
    {
        CancelAnalysis();
        var transcript = GetDocumentTranscript();

        if (string.IsNullOrWhiteSpace(transcript))
        {
            _replacementMessage = "本次会话没有识别到有效文字。";
            PublishSessionUpdate(_replacementMessage);
            PublishState(new VoiceCaptureSnapshot(
                VoiceCaptureState.Completed,
                Stopwatch.GetElapsedTime(_recordingStartedAt)));
            DisposeSessionResources();
            return;
        }

        PublishSessionUpdate("正在检查错别字、语法和全文流畅度...");

        try
        {
            string[] transcriptSegments;
            lock (_transcriptLock)
            {
                transcriptSegments = _segmentTexts.ToArray();
            }

            var optimizedText = transcriptSegments.Length > 1
                ? await _writingModelProvider
                    .OptimizeSegmentsAsync(transcriptSegments, cancellationToken)
                    .ConfigureAwait(false)
                : await _writingModelProvider
                    .OptimizeAsync(transcript, cancellationToken)
                .ConfigureAwait(false);

            _optimizedTranscript = string.IsNullOrWhiteSpace(optimizedText)
                ? transcript
                : _domainTermCorrector.Correct(optimizedText.Trim(), _customVocabulary);

            if (!string.Equals(_optimizedTranscript, transcript, StringComparison.Ordinal)
                && _insertionTarget is not null)
            {
                var replacement = await _textInsertionService
                    .ReplaceSessionTextAsync(
                        transcript,
                        _optimizedTranscript,
                        _insertionTarget,
                        cancellationToken)
                    .ConfigureAwait(false);

                _replacementMessage = replacement.Success
                    ? "全文优化完成并已原位替换。"
                    : replacement.Message;
            }
            else
            {
                _replacementMessage = "全文检查完成，无需修改。";
            }
        }
        catch (Exception exception)
        {
            _optimizedTranscript = transcript;
            _replacementMessage = $"全文优化未完成：{exception.Message}";
        }

        PublishSessionUpdate(_replacementMessage);
        PublishState(new VoiceCaptureSnapshot(
            VoiceCaptureState.Completed,
            Stopwatch.GetElapsedTime(_recordingStartedAt)));
        DisposeSessionResources();
    }

    private string AppendTranscript(string segmentText)
    {
        lock (_transcriptLock)
        {
            var existing = _stableTranscript.ToString();
            var normalizedSegment = segmentText.Trim();
            var overlap = FindOverlap(existing, normalizedSegment);
            var newText = normalizedSegment[overlap..];

            if (string.IsNullOrWhiteSpace(newText)
                || existing.EndsWith(newText, StringComparison.Ordinal))
            {
                return string.Empty;
            }

            var separator = NeedsSpace(existing, newText) ? " " : string.Empty;
            _stableTranscript.Append(separator);
            _stableTranscript.Append(newText);
            return separator + newText;
        }
    }

    private string GetStableTranscript()
    {
        lock (_transcriptLock)
        {
            return _stableTranscript.ToString().Trim();
        }
    }

    private string GetDocumentTranscript()
    {
        return _liveRecognitionAvailable && !string.IsNullOrWhiteSpace(_liveSessionText)
            ? _liveSessionText.Trim()
            : GetStableTranscript();
    }

    private void PublishSessionUpdate(string statusMessage)
    {
        _statusMessage = statusMessage;
        var update = new WritingSessionUpdate(
            GetDocumentTranscript(),
            _draftTranscript,
            _guidance,
            _statusMessage,
            _optimizedTranscript,
            _replacementMessage);
        CurrentWritingSession = update;
        WritingSessionChanged?.Invoke(this, new WritingSessionUpdateEventArgs(update));
    }

    private void PublishState(VoiceCaptureSnapshot snapshot)
    {
        Current = snapshot;
        StateChanged?.Invoke(this, new VoiceCaptureStateChangedEventArgs(snapshot));
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

        PublishState(Current with
        {
            Elapsed = Stopwatch.GetElapsedTime(_recordingStartedAt)
        });
    }

    private void ResetSession()
    {
        _sessionGeneration++;
        _sessionCancellation?.Dispose();
        _sessionCancellation = new CancellationTokenSource();
        ResetBuffers();
        _guidance = WritingGuidance.Empty;
        _supplementalGuidanceKey = string.Empty;
        _supplementalDirections = [];
        _supplementalMissingPoints = [];
        _draftTranscript = string.Empty;
        _optimizedTranscript = string.Empty;
        _replacementMessage = string.Empty;
        _statusMessage = string.Empty;
        _liveCommittedText = string.Empty;
        _liveSessionText = string.Empty;
        _liveRecognitionAvailable = false;

        lock (_liveQueueLock)
        {
            _liveTranscriptQueue.Clear();
            _liveWorkerRunning = false;
        }

        lock (_chainLock)
        {
            _segmentChain = Task.CompletedTask;
        }
    }

    private void ResetBuffers()
    {
        lock (_transcriptLock)
        {
            _stableTranscript.Clear();
            _segmentTexts.Clear();
        }

        lock (_segmentLock)
        {
            ResetSegmentBuffer();
        }
    }

    private void ResetSegmentBuffer(byte[]? seed = null)
    {
        _segmentPcm.SetLength(0);
        if (seed is { Length: > 0 })
        {
            _segmentPcm.Write(seed);
        }

        _segmentStartedAt = DateTimeOffset.UtcNow;
        _lastVoiceDetectedAt = _segmentStartedAt;
        _hasSpeech = false;
    }

    private void CancelAnalysis()
    {
        var cancellation = Interlocked.Exchange(ref _analysisCancellation, null);
        cancellation?.Cancel();
        cancellation?.Dispose();
    }

    private void CleanupFailedSession()
    {
        _globalHotkeyService.CaptureEscape = false;
        StopElapsedTimer();
        _audioCaptureService.Cancel();
        _ = _streamingSpeechRecognitionProvider.EndSession();
        _insertionTarget?.Dispose();
        _insertionTarget = null;
        CancelAnalysis();
    }

    private void DisposeSessionResources()
    {
        _globalHotkeyService.CaptureEscape = false;
        _ = _streamingSpeechRecognitionProvider.EndSession();
        _insertionTarget?.Dispose();
        _insertionTarget = null;
        _sessionCancellation?.Dispose();
        _sessionCancellation = null;
    }

    private static int FindOverlap(string existing, string incoming)
    {
        if (string.IsNullOrEmpty(existing) || string.IsNullOrEmpty(incoming))
        {
            return 0;
        }

        var maximum = Math.Min(48, Math.Min(existing.Length, incoming.Length));
        for (var length = maximum; length >= 4; length--)
        {
            if (existing.AsSpan(existing.Length - length).SequenceEqual(incoming.AsSpan(0, length)))
            {
                return length;
            }

            var existingSuffix = NormalizeForOverlap(existing[^length..]);
            var incomingPrefix = NormalizeForOverlap(incoming[..length]);
            if (existingSuffix.Length >= 4
                && incomingPrefix.Length >= 4
                && existingSuffix.EndsWith(incomingPrefix, StringComparison.Ordinal))
            {
                return length;
            }
        }

        return 0;
    }

    private static bool NeedsSpace(string existing, string incoming)
    {
        if (string.IsNullOrEmpty(existing) || string.IsNullOrEmpty(incoming))
        {
            return false;
        }

        var left = existing[^1];
        var right = incoming[0];
        return char.IsWhiteSpace(left) is false
            && char.IsWhiteSpace(right) is false
            && char.IsPunctuation(left) is false
            && char.IsPunctuation(right) is false
            && IsAsciiLetterOrDigit(left)
            && IsAsciiLetterOrDigit(right);
    }

    private static bool IsAsciiLetterOrDigit(char value)
    {
        return value is >= 'A' and <= 'Z'
            or >= 'a' and <= 'z'
            or >= '0' and <= '9';
    }

    private static string NormalizeForOverlap(string value)
    {
        var buffer = new StringBuilder(value.Length);
        foreach (var character in value)
        {
            if (char.IsLetterOrDigit(character))
            {
                buffer.Append(char.ToLowerInvariant(character));
            }
        }

        return buffer.ToString();
    }

    private void OnLiveTranscriptChanged(object? sender, LiveTranscriptEventArgs e)
    {
        if (!_liveRecognitionAvailable || Current.State != VoiceCaptureState.Recording)
        {
            return;
        }

        lock (_liveQueueLock)
        {
            _liveTranscriptQueue.Enqueue(e);
            if (_liveWorkerRunning)
            {
                return;
            }

            _liveWorkerRunning = true;
        }

        _ = ProcessLiveTranscriptQueueAsync(_sessionGeneration);
    }

    private async Task ProcessLiveTranscriptQueueAsync(int generation)
    {
        try
        {
            while (generation == _sessionGeneration)
            {
                LiveTranscriptEventArgs? update;
                lock (_liveQueueLock)
                {
                    if (_liveTranscriptQueue.Count == 0)
                    {
                        _liveWorkerRunning = false;
                        return;
                    }

                    update = _liveTranscriptQueue.Dequeue();
                }

                await ApplyLiveTextAsync(update.Text, update.IsFinal, generation).ConfigureAwait(false);
                await Task.Delay(55).ConfigureAwait(false);
            }
        }
        finally
        {
            lock (_liveQueueLock)
            {
                _liveWorkerRunning = false;
            }
        }
    }

    private async Task ApplyLiveTextAsync(string text, bool isFinal, int generation)
    {
        if (!_liveRecognitionAvailable
            || generation != _sessionGeneration
            || _insertionTarget is null
            || string.IsNullOrWhiteSpace(text))
        {
            return;
        }

        var correctedText = _domainTermCorrector.Correct(text.Trim(), _customVocabulary);
        if (string.IsNullOrWhiteSpace(correctedText))
        {
            return;
        }

        var baseText = AppendText(_liveCommittedText, correctedText);
        var previousDocumentText = _liveSessionText;
        var updateResult = await _textInsertionService
            .UpdateLiveDraftAsync(previousDocumentText, baseText, _insertionTarget)
            .ConfigureAwait(false);

        if (!updateResult.Success)
        {
            PublishSessionUpdate(updateResult.Message);
            return;
        }

        _draftTranscript = correctedText;
        _liveSessionText = baseText;
        if (isFinal)
        {
            _liveCommittedText = baseText;
        }

        PublishSessionUpdate(isFinal
            ? "已确认一句，继续实时输入..."
            : "正在实时输入...");
        RefreshLocalGuidance(GetDocumentTranscript(), generation);
    }

    private async Task DrainLiveTranscriptQueueAsync()
    {
        while (true)
        {
            lock (_liveQueueLock)
            {
                if (!_liveWorkerRunning && _liveTranscriptQueue.Count == 0)
                {
                    return;
                }
            }

            await Task.Delay(25).ConfigureAwait(false);
        }
    }

    private static string AppendText(string existing, string incoming)
    {
        var normalizedIncoming = incoming.Trim();
        if (string.IsNullOrWhiteSpace(existing))
        {
            return normalizedIncoming;
        }

        var overlap = FindOverlap(existing, normalizedIncoming);
        var newText = normalizedIncoming[overlap..];
        if (string.IsNullOrWhiteSpace(newText))
        {
            return existing;
        }

        var separator = NeedsSpace(existing, newText) ? " " : string.Empty;
        return existing + separator + newText;
    }

    private static byte[] CreateWaveFile(byte[] pcm)
    {
        using var stream = new MemoryStream(44 + pcm.Length);
        using var writer = new BinaryWriter(stream);

        var byteRate = SampleRate * Channels * BitsPerSample / 8;
        var blockAlign = Channels * BitsPerSample / 8;

        writer.Write("RIFF"u8);
        writer.Write(36 + pcm.Length);
        writer.Write("WAVE"u8);
        writer.Write("fmt "u8);
        writer.Write(16);
        writer.Write((short)1);
        writer.Write((short)Channels);
        writer.Write(SampleRate);
        writer.Write(byteRate);
        writer.Write((short)blockAlign);
        writer.Write((short)BitsPerSample);
        writer.Write("data"u8);
        writer.Write(pcm.Length);
        writer.Write(pcm);
        writer.Flush();
        return stream.ToArray();
    }
}

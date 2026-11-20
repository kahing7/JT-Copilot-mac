using System.Diagnostics;
using System.Text;
using JT.Copilot.Application.Abstractions;
using JT.Copilot.Application.Hotkeys;
using JT.Copilot.Application.Models;
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
    private readonly IWritingModelProvider _writingModelProvider;
    private readonly ITextInsertionService _textInsertionService;
    private readonly SemaphoreSlim _stateGate = new(1, 1);
    private readonly object _timerLock = new();
    private readonly object _segmentLock = new();
    private readonly object _chainLock = new();
    private readonly object _transcriptLock = new();

    private readonly MemoryStream _segmentPcm = new();
    private readonly StringBuilder _stableTranscript = new();
    private readonly List<string> _segmentTexts = [];

    private Timer? _elapsedTimer;
    private Task _segmentChain = Task.CompletedTask;
    private CancellationTokenSource? _sessionCancellation;
    private CancellationTokenSource? _analysisCancellation;
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
    private bool _hasSpeech;
    private bool _initialized;
    private bool _finishing;
    private bool _disposed;

    public VoiceCaptureCoordinator(
        IAudioCaptureService audioCaptureService,
        IGlobalHotkeyService globalHotkeyService,
        IAppSettingsStore settingsStore,
        ISpeechRecognitionProvider speechRecognitionProvider,
        IWritingModelProvider writingModelProvider,
        ITextInsertionService textInsertionService)
    {
        _audioCaptureService = audioCaptureService;
        _globalHotkeyService = globalHotkeyService;
        _settingsStore = settingsStore;
        _speechRecognitionProvider = speechRecognitionProvider;
        _writingModelProvider = writingModelProvider;
        _textInsertionService = textInsertionService;

        _globalHotkeyService.Pressed += OnHotkeyPressed;
        _globalHotkeyService.CancelRequested += OnEscapePressed;
        _audioCaptureService.LevelChanged += OnAudioLevelChanged;
        _audioCaptureService.PcmDataAvailable += OnPcmDataAvailable;
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
            _globalHotkeyService.Start(HotkeyGesture.ParseOrDefault(settings.Hotkey));
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
            var segmentText = await _speechRecognitionProvider
                .TranscribeAsync(wavAudio, string.Empty, token)
                .ConfigureAwait(false);

            if (string.IsNullOrWhiteSpace(segmentText))
            {
                return;
            }

            lock (_transcriptLock)
            {
                _segmentTexts.Add(segmentText.Trim());
            }

            var appendedText = AppendTranscript(segmentText);
            if (string.IsNullOrWhiteSpace(appendedText))
            {
                return;
            }

            _draftTranscript = segmentText.Trim();
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

            QueueGuidanceUpdate(GetStableTranscript(), generation);
        }
        catch (OperationCanceledException)
        {
        }
        catch (Exception exception)
        {
            PublishSessionUpdate($"语音识别失败：{exception.Message}");
        }
    }

    private void QueueGuidanceUpdate(string transcript, int generation)
    {
        var cancellation = new CancellationTokenSource();
        var previous = Interlocked.Exchange(ref _analysisCancellation, cancellation);
        previous?.Cancel();
        previous?.Dispose();

        _ = UpdateGuidanceAsync(transcript, generation, cancellation);
    }

    private async Task UpdateGuidanceAsync(
        string transcript,
        int generation,
        CancellationTokenSource cancellation)
    {
        try
        {
            await Task.Delay(260, cancellation.Token).ConfigureAwait(false);
            var guidance = await _writingModelProvider
                .AnalyzeAsync(transcript, _guidance, cancellation.Token)
                .ConfigureAwait(false);

            if (generation != _sessionGeneration)
            {
                return;
            }

            _guidance = guidance;
            PublishSessionUpdate(Current.State == VoiceCaptureState.Recording
                ? "正在聆听 · 框架已更新"
                : "正在整理全文...");
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

    private async Task CompleteSessionAsync(CancellationToken cancellationToken)
    {
        CancelAnalysis();
        var transcript = GetStableTranscript();

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

            _optimizedTranscript = transcriptSegments.Length > 1
                ? await _writingModelProvider
                    .OptimizeSegmentsAsync(transcriptSegments, cancellationToken)
                    .ConfigureAwait(false)
                : await _writingModelProvider
                    .OptimizeAsync(transcript, cancellationToken)
                .ConfigureAwait(false);

            if (string.IsNullOrWhiteSpace(_optimizedTranscript))
            {
                _optimizedTranscript = transcript;
            }

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

    private void PublishSessionUpdate(string statusMessage)
    {
        _statusMessage = statusMessage;
        var update = new WritingSessionUpdate(
            GetStableTranscript(),
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
        _draftTranscript = string.Empty;
        _optimizedTranscript = string.Empty;
        _replacementMessage = string.Empty;
        _statusMessage = string.Empty;

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
        _insertionTarget?.Dispose();
        _insertionTarget = null;
        CancelAnalysis();
    }

    private void DisposeSessionResources()
    {
        _globalHotkeyService.CaptureEscape = false;
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

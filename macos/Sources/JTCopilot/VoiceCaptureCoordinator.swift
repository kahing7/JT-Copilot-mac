import Foundation
import JTCopilotCore

/// 会话协调器：录音分段、实时写入、本地引导、智谱校正与最终替换。
/// 所有状态都在主 actor 上，避免音频回调与 UI 更新竞争。
@MainActor
final class VoiceCaptureCoordinator {
    private static let speechThreshold = 0.045
    private static let segmentOverlapBytes = Int(AudioCaptureService.sampleRate) * 2 * 45 / 100
    private static let silenceBeforeSegment: TimeInterval = 0.55
    private static let maxSegmentLength: TimeInterval = 3.8
    private static let minimumSpeechLength: TimeInterval = 0.35
    private static let minimumSegmentBytes = Int(AudioCaptureService.sampleRate) * 2 * 35 / 100

    private let audioCaptureService: AudioCaptureService
    private let hotkeyService: HotkeyService
    private let settingsStore: SettingsStore
    private let speechRecognitionProvider: ZhipuSpeechRecognitionProvider
    private let writingModelProvider: ZhipuWritingModelProvider
    private let documentFrameworkEngine: DocumentFrameworkEngine
    private let domainTermCorrector: DomainTermCorrector
    private let textInsertionService: TextInsertionService
    private let speechRecognizer: AppleSpeechRecognizer

    var onStateChanged: ((VoiceCaptureSnapshot) -> Void)?
    var onLevelChanged: ((Double) -> Void)?
    var onWritingSessionChanged: ((WritingSessionUpdate) -> Void)?

    private(set) var current = VoiceCaptureSnapshot.idle
    private(set) var currentWritingSession = WritingSessionUpdate()
    private(set) var hotkeyError: String?

    private var pcmBuffer = Data()
    private var stableTranscript = ""
    private var segmentTexts: [String] = []
    private var liveQueue: [LiveTranscriptUpdate] = []
    private var liveWorkerRunning = false

    private var elapsedTimer: Timer?
    private var segmentChain: Task<Void, Never> = Task {}
    private var supplementalTask: Task<Void, Never>?
    private var speechInitializationTask: Task<Bool, Never>?

    private var recordingStartedAt: Date?
    private var segmentStartedAt = Date()
    private var lastVoiceDetectedAt = Date()
    private var hasSpeech = false
    private var sessionGeneration = 0
    private var draftTranscript = ""
    private var optimizedTranscript = ""
    private var replacementMessage = ""
    private var statusMessage = ""
    private var liveCommittedText = ""
    private var liveSessionText = ""
    private var customVocabulary = ""
    private var supplementalGuidanceKey = ""
    private var supplementalDirections: [String] = []
    private var supplementalMissingPoints: [String] = []
    private var documentTemplate: DocumentTemplate = .auto
    private var guidance = WritingGuidance.empty
    private var insertionTarget: TextInsertionService.Target?
    private var liveRecognitionAvailable = false
    private var initialized = false
    private var starting = false
    private var finishing = false
    private var disposed = false
    private(set) var speechInitializationInFlight = false

    private var settings: AppSettings {
        settingsStore.load()
    }

    init(
        audioCaptureService: AudioCaptureService,
        hotkeyService: HotkeyService,
        settingsStore: SettingsStore,
        speechRecognitionProvider: ZhipuSpeechRecognitionProvider,
        writingModelProvider: ZhipuWritingModelProvider,
        documentFrameworkEngine: DocumentFrameworkEngine,
        domainTermCorrector: DomainTermCorrector,
        textInsertionService: TextInsertionService,
        speechRecognizer: AppleSpeechRecognizer
    ) {
        self.audioCaptureService = audioCaptureService
        self.hotkeyService = hotkeyService
        self.settingsStore = settingsStore
        self.speechRecognitionProvider = speechRecognitionProvider
        self.writingModelProvider = writingModelProvider
        self.documentFrameworkEngine = documentFrameworkEngine
        self.domainTermCorrector = domainTermCorrector
        self.textInsertionService = textInsertionService
        self.speechRecognizer = speechRecognizer

        hotkeyService.onPressed = { [weak self] in
            Task { @MainActor in
                self?.handleHotkeyPressed()
            }
        }
        hotkeyService.onCancelRequested = { [weak self] in
            Task { @MainActor in
                self?.handleCancelRequested()
            }
        }
        audioCaptureService.onLevel = { [weak self] level in
            Task { @MainActor in
                self?.onLevelChanged?(level)
            }
        }
        audioCaptureService.onPcm = { [weak self] data, level in
            Task { @MainActor in
                self?.handlePcm(data, level: level)
            }
        }
        speechRecognizer.onTranscript = { [weak self] update in
            Task { @MainActor in
                self?.handleLiveTranscript(update)
            }
        }
        speechRecognizer.onFailure = { [weak self] message in
            Task { @MainActor in
                guard let self else { return }

                if self.current.state == .recording {
                    let fallback = self.liveSessionText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !fallback.isEmpty {
                        self.stableTranscript = fallback
                    }
                }

                self.liveRecognitionAvailable = false
                self.publishSessionUpdate(message)
            }
        }
    }

    // MARK: - Lifecycle

    func initialize() async {
        guard !initialized else { return }

        let loaded = settings
        customVocabulary = loaded.customVocabulary
        documentTemplate = loaded.guidanceTemplate

        do {
            try hotkeyService.start(gesture: loaded.hotkeyGesture)
            hotkeyError = nil
        } catch {
            hotkeyError = error.localizedDescription
            publishState(VoiceCaptureSnapshot(
                state: .faulted,
                errorMessage: "全局快捷键启动失败：\(error.localizedDescription)"
            ))
        }

        speechInitializationInFlight = true
        speechInitializationTask = Task { [weak self, speechRecognizer] in
            let available = await speechRecognizer.initialize()
            self?.speechInitializationInFlight = false
            return available
        }

        initialized = true
    }

    var liveRecognitionReady: Bool {
        speechRecognizer.isAvailable
    }

    func start() async {
        guard !disposed, !starting else { return }
        guard current.state != .recording, current.state != .processing else { return }

        starting = true
        defer { starting = false }

        guard Permissions.accessibilityTrusted else {
            publishSessionUpdate("需要辅助功能权限才能向其他应用写入文字。请在系统设置 → 隐私与安全性 → 辅助功能中允许 JT Copilot。")
            publishState(VoiceCaptureSnapshot(
                state: .faulted,
                errorMessage: "需要辅助功能权限。"
            ))
            return
        }

        resetSession()
        publishSessionUpdate("正在准备本地实时识别...")

        if let speechInitializationTask {
            liveRecognitionAvailable = await speechInitializationTask.value
        } else {
            liveRecognitionAvailable = speechRecognizer.isAvailable
        }

        if liveRecognitionAvailable {
            speechRecognizer.setContextualStrings(domainTermCorrector.hotwords(customVocabulary))
            liveRecognitionAvailable = speechRecognizer.startSession()
        }

        if !liveRecognitionAvailable {
            publishSessionUpdate("本地实时引擎不可用，已回退到智谱分片识别。")
        }

        guard let target = textInsertionService.captureTarget() else {
            _ = speechRecognizer.endSession()
            liveRecognitionAvailable = false
            publishSessionUpdate("无法锁定当前编辑器，请先把光标放到飞书、Word 或文本编辑器中。")
            publishState(VoiceCaptureSnapshot(
                state: .faulted,
                errorMessage: "无法锁定当前编辑器。"
            ))
            return
        }

        insertionTarget = target
        let loaded = settings

        do {
            try audioCaptureService.start(deviceID: loaded.preferredMicrophoneDeviceId)
        } catch {
            cleanupFailedSession()
            publishState(VoiceCaptureSnapshot(
                state: .faulted,
                errorMessage: error.localizedDescription
            ))
            return
        }

        recordingStartedAt = Date()
        segmentStartedAt = Date()
        lastVoiceDetectedAt = segmentStartedAt
        hotkeyService.captureEscape = true
        startElapsedTimer()

        publishSessionUpdate("正在聆听 · \(target.displayName)")
        publishState(VoiceCaptureSnapshot(state: .recording, elapsed: 0))
        refreshLocalGuidance("", generation: sessionGeneration)
    }

    func finish() async {
        guard !disposed, current.state == .recording, !finishing else { return }

        finishing = true
        hotkeyService.captureEscape = false
        stopElapsedTimer()
        cancelSupplementalGuidance()
        publishSessionUpdate("正在提交最后一段语音...")
        publishState(VoiceCaptureSnapshot(
            state: .processing,
            elapsed: elapsed()
        ))

        let audioResult = audioCaptureService.stop()
        capturePendingSegment(force: true)
        let finalLiveText = speechRecognizer.endSession()
        await drainLiveQueue()

        if !finalLiveText.isEmpty {
            await applyLiveText(
                LiveTranscriptUpdate(text: finalLiveText, isFinal: true),
                generation: sessionGeneration
            )
        }

        await segmentChain.value
        await completeSession(recordingPath: audioResult.recordingPath)
        finishing = false
    }

    func cancel() async {
        guard !disposed else { return }

        hotkeyService.captureEscape = false
        stopElapsedTimer()
        cancelSupplementalGuidance()
        audioCaptureService.cancel()
        _ = speechRecognizer.endSession()
        sessionGeneration += 1
        liveQueue.removeAll()
        liveWorkerRunning = false
        resetBuffers()
        insertionTarget = nil
        publishSessionUpdate("录音已取消。")
        publishState(.idle)
    }

    func updateHotkey(_ gesture: HotkeyGesture) throws {
        guard current.state != .recording, current.state != .processing else {
            throw NSError(domain: "JTCopilot.Session", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "请先结束当前写作会话，再修改全局快捷键。"
            ])
        }

        try hotkeyService.reconfigure(gesture: gesture)
    }

    func updateDocumentTemplate(_ template: DocumentTemplate) {
        let resolved = template == .general ? .auto : template
        documentTemplate = resolved

        if current.state == .recording || current.state == .processing {
            refreshLocalGuidance(documentTranscript(), generation: sessionGeneration)
        }
    }

    func updateCustomVocabulary(_ vocabulary: String) {
        customVocabulary = vocabulary.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @discardableResult
    func retryHotkey() -> Bool {
        guard !disposed else { return false }

        do {
            try hotkeyService.start(gesture: settings.hotkeyGesture)
            hotkeyError = nil
            if current.state == .faulted {
                publishState(.idle)
            }
            return true
        } catch {
            hotkeyError = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func retrySpeechInitialization() async -> Bool {
        guard !disposed else { return false }
        speechInitializationInFlight = true
        let available = await speechRecognizer.initialize()
        speechInitializationInFlight = false
        speechInitializationTask = Task { available }
        return available
    }

    func dispose() {
        guard !disposed else { return }

        disposed = true
        stopElapsedTimer()
        cancelSupplementalGuidance()
        audioCaptureService.cancel()
        _ = speechRecognizer.endSession()
        hotkeyService.stop()
        insertionTarget = nil
    }

    // MARK: - Hotkey

    private func handleHotkeyPressed() {
        guard current.state != .recording, current.state != .processing else { return }
        Task { await start() }
    }

    private func handleCancelRequested() {
        guard current.state == .recording else { return }
        Task { await finish() }
    }

    // MARK: - Audio segmentation

    private func handlePcm(_ data: Data, level: Double) {
        guard current.state == .recording else { return }

        if liveRecognitionAvailable {
            speechRecognizer.append(pcm16: data)
        }

        pcmBuffer.append(data)

        let now = Date()
        if level >= VoiceCaptureCoordinator.speechThreshold {
            hasSpeech = true
            lastVoiceDetectedAt = now
        }

        let segmentLength = now.timeIntervalSince(segmentStartedAt)
        let silenceLength = now.timeIntervalSince(lastVoiceDetectedAt)

        if hasSpeech,
           (silenceLength >= VoiceCaptureCoordinator.silenceBeforeSegment
            || segmentLength >= VoiceCaptureCoordinator.maxSegmentLength) {
            captureSegment()
        }
    }

    private func capturePendingSegment(force: Bool) {
        if force || hasSpeech {
            captureSegment()
        } else {
            resetSegmentBuffer(seed: nil)
        }
    }

    private func captureSegment() {
        let pcm = pcmBuffer
        let segmentDuration = Date().timeIntervalSince(segmentStartedAt)
        let hadSpeech = hasSpeech
        let overlap = hadSpeech && pcm.count > VoiceCaptureCoordinator.segmentOverlapBytes
            ? pcm.suffix(VoiceCaptureCoordinator.segmentOverlapBytes)
            : Data()

        resetSegmentBuffer(seed: Data(overlap))

        guard hadSpeech,
              pcm.count >= VoiceCaptureCoordinator.minimumSegmentBytes,
              segmentDuration >= VoiceCaptureCoordinator.minimumSpeechLength else {
            return
        }

        let generation = sessionGeneration
        let wav = makeWaveFile(pcm: pcm)
        let previous = segmentChain

        segmentChain = Task { [weak self] in
            await previous.value
            guard let self else { return }
            await self.processSegment(wav, generation: generation)
        }
    }

    private func processSegment(_ wav: Data, generation: Int) async {
        guard !disposed,
              generation == sessionGeneration,
              current.state == .recording || current.state == .processing else {
            return
        }

        do {
            let rawText = try await speechRecognitionProvider.transcribe(
                wavData: wav,
                transcriptContext: buildRecognitionPrompt()
            )
            let corrected = domainTermCorrector
                .correct(rawText, customVocabulary: customVocabulary)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !corrected.isEmpty else { return }
            segmentTexts.append(corrected)

            if liveRecognitionAvailable {
                refreshLocalGuidance(documentTranscript(), generation: generation)
                return
            }

            let merged = TranscriptMerger.append(existing: stableTranscript, incoming: corrected)
            guard !merged.appended.isEmpty else { return }

            stableTranscript = merged.text
            draftTranscript = corrected
            publishSessionUpdate("已识别，正在写入...")

            guard let target = insertionTarget else {
                publishSessionUpdate("目标编辑器已关闭。")
                return
            }

            let result = await textInsertionService.insert(merged.appended, target: target)
            publishSessionUpdate(result.success
                ? "文字已写入，正在更新表达框架..."
                : result.message)

            refreshLocalGuidance(stableTranscript, generation: generation)
        } catch {
            publishSessionUpdate("语音识别失败：\(error.localizedDescription)")
        }
    }

    // MARK: - Guidance

    private func refreshLocalGuidance(_ transcript: String, generation: Int) {
        guard generation == sessionGeneration else { return }

        let result = documentFrameworkEngine.build(
            transcript: transcript,
            template: documentTemplate
        )

        let guidanceKey = [
            String(result.guidance.template.rawValue),
            result.guidance.nextSentence,
            result.guidance.framework.joined(separator: "\u{1E}")
        ].joined(separator: "\u{1F}")

        if guidanceKey != supplementalGuidanceKey {
            supplementalGuidanceKey = guidanceKey
            supplementalDirections = []
            supplementalMissingPoints = []
        }

        guidance = WritingGuidance(
            framework: result.guidance.framework,
            nextSentence: result.guidance.nextSentence,
            directions: merge(
                result.guidance.directions,
                supplementalDirections,
                limit: 6
            ),
            missingPoints: merge(
                result.guidance.missingPoints,
                supplementalMissingPoints,
                limit: 4
            ),
            template: result.guidance.template
        )

        publishSessionUpdate(current.state == .recording
            ? "正在聆听 · 下一步已同步"
            : "正在整理全文 · 框架已同步")

        queueSupplementalGuidance(
            transcript: transcript,
            generation: generation,
            localGuidance: result.guidance,
            guidanceKey: guidanceKey
        )
    }

    private func queueSupplementalGuidance(
        transcript: String,
        generation: Int,
        localGuidance: WritingGuidance,
        guidanceKey: String
    ) {
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        supplementalTask?.cancel()
        supplementalTask = Task { [weak self] in
            guard let self else { return }

            do {
                try await Task.sleep(nanoseconds: 320_000_000)
                let supplemental = try await self.writingModelProvider.analyze(
                    transcript: transcript,
                    previousGuidance: localGuidance
                )

                guard !Task.isCancelled,
                      generation == self.sessionGeneration,
                      guidanceKey == self.supplementalGuidanceKey else {
                    return
                }

                self.supplementalDirections = supplemental.directions
                self.supplementalMissingPoints = supplemental.missingPoints
                self.guidance.directions = self.merge(
                    self.guidance.directions,
                    supplemental.directions,
                    limit: 6
                )
                self.guidance.missingPoints = self.merge(
                    self.guidance.missingPoints,
                    supplemental.missingPoints,
                    limit: 4
                )

                self.publishSessionUpdate(self.current.state == .recording
                    ? "正在聆听 · 已补充写作方向"
                    : "正在整理全文 · 已补充检查项")
            } catch is CancellationError {
            } catch {
                self.publishSessionUpdate("表达建议暂不可用：\(error.localizedDescription)")
            }
        }
    }

    private func cancelSupplementalGuidance() {
        supplementalTask?.cancel()
        supplementalTask = nil
    }

    private func merge(_ primary: [String], _ supplemental: [String], limit: Int) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for item in primary + supplemental {
            let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else { continue }
            seen.insert(trimmed)
            result.append(trimmed)
            if result.count >= limit { break }
        }

        return result
    }

    // MARK: - Live recognition

    private func handleLiveTranscript(_ update: LiveTranscriptUpdate) {
        guard liveRecognitionAvailable, current.state == .recording else { return }

        liveQueue.append(update)
        if liveWorkerRunning { return }

        liveWorkerRunning = true
        let generation = sessionGeneration
        Task { [weak self] in
            await self?.processLiveQueue(generation: generation)
        }
    }

    private func processLiveQueue(generation: Int) async {
        while generation == sessionGeneration {
            guard !liveQueue.isEmpty else {
                liveWorkerRunning = false
                return
            }

            let update = liveQueue.removeFirst()
            await applyLiveText(update, generation: generation)
            try? await Task.sleep(nanoseconds: 55_000_000)

            if Task.isCancelled {
                break
            }
        }

        liveWorkerRunning = false
    }

    private func applyLiveText(_ update: LiveTranscriptUpdate, generation: Int) async {
        guard liveRecognitionAvailable,
              generation == sessionGeneration,
              current.state == .recording || current.state == .processing,
              let target = insertionTarget else {
            return
        }

        let corrected = domainTermCorrector
            .correct(update.text.trimmingCharacters(in: .whitespacesAndNewlines), customVocabulary: customVocabulary)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !corrected.isEmpty else { return }

        let baseText = TranscriptMerger.append(existing: liveCommittedText, incoming: corrected).text
        let previousDocumentText = liveSessionText

        let result = await textInsertionService.updateLiveDraft(
            previous: previousDocumentText,
            current: baseText,
            target: target
        )

        guard result.success else {
            publishSessionUpdate(result.message)
            return
        }

        draftTranscript = corrected
        liveSessionText = baseText
        if update.isFinal {
            liveCommittedText = baseText
        }

        publishSessionUpdate(update.isFinal
            ? "已确认一句，继续实时输入..."
            : "正在实时输入...")
        refreshLocalGuidance(documentTranscript(), generation: generation)
    }

    private func drainLiveQueue() async {
        var attempts = 0
        while (liveWorkerRunning || !liveQueue.isEmpty) && attempts < 200 {
            try? await Task.sleep(nanoseconds: 25_000_000)
            attempts += 1
        }
    }

    // MARK: - Completion

    private func completeSession(recordingPath: String?) async {
        cancelSupplementalGuidance()
        let transcript = documentTranscript()

        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            replacementMessage = "本次会话没有识别到有效文字。"
            publishSessionUpdate(replacementMessage)
            publishState(VoiceCaptureSnapshot(
                state: .completed,
                elapsed: elapsed(),
                recordingPath: recordingPath
            ))
            disposeSessionResources()
            return
        }

        publishSessionUpdate("正在检查错别字、语法和全文流畅度...")

        do {
            let segments = segmentTexts
            let optimized: String
            if segments.count > 1 {
                optimized = try await writingModelProvider.optimizeSegments(segments)
            } else {
                optimized = try await writingModelProvider.optimize(transcript: transcript)
            }

            let corrected = optimized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? transcript
                : domainTermCorrector
                    .correct(optimized, customVocabulary: customVocabulary)
                    .trimmingCharacters(in: .whitespacesAndNewlines)

            optimizedTranscript = corrected

            if corrected != transcript {
                if let target = insertionTarget {
                    let result = await textInsertionService.replaceSessionText(
                        expected: transcript,
                        replacement: corrected,
                        target: target
                    )
                    replacementMessage = result.success
                        ? "全文优化完成并已原位替换。"
                        : result.message
                } else {
                    replacementMessage = "全文已优化，但目标编辑器已关闭，请从引导面板复制结果。"
                }
            } else {
                replacementMessage = "全文检查完成，无需修改。"
            }
        } catch {
            optimizedTranscript = transcript
            replacementMessage = "全文优化未完成：\(error.localizedDescription)"
        }

        publishSessionUpdate(replacementMessage)
        publishState(VoiceCaptureSnapshot(
            state: .completed,
            elapsed: elapsed(),
            recordingPath: recordingPath
        ))
        disposeSessionResources()
    }

    // MARK: - Helpers

    private func documentTranscript() -> String {
        if liveRecognitionAvailable, !liveSessionText.isEmpty {
            return liveSessionText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return stableTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func buildRecognitionPrompt() -> String {
        let hotwords = domainTermCorrector.hotwords(customVocabulary)
        return hotwords.isEmpty
            ? ""
            : "请准确识别以下业务术语并保留英文缩写：\(hotwords.joined(separator: "、"))"
    }

    private func publishSessionUpdate(_ message: String) {
        statusMessage = message
        let update = WritingSessionUpdate(
            stableTranscript: documentTranscript(),
            draftTranscript: draftTranscript,
            guidance: guidance,
            statusText: statusMessage,
            optimizedTranscript: optimizedTranscript,
            replacementMessage: replacementMessage
        )
        currentWritingSession = update
        onWritingSessionChanged?(update)
    }

    private func publishState(_ snapshot: VoiceCaptureSnapshot) {
        current = snapshot
        onStateChanged?(snapshot)
    }

    private func startElapsedTimer() {
        stopElapsedTimer()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tickElapsed()
            }
        }
    }

    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }

    private func tickElapsed() {
        guard current.state == .recording else { return }
        publishState(VoiceCaptureSnapshot(state: .recording, elapsed: elapsed()))
    }

    private func elapsed() -> TimeInterval {
        guard let recordingStartedAt else { return 0 }
        return Date().timeIntervalSince(recordingStartedAt)
    }

    private func resetSession() {
        sessionGeneration += 1
        resetBuffers()
        guidance = .empty
        supplementalGuidanceKey = ""
        supplementalDirections = []
        supplementalMissingPoints = []
        draftTranscript = ""
        optimizedTranscript = ""
        replacementMessage = ""
        statusMessage = ""
        liveCommittedText = ""
        liveSessionText = ""
        liveRecognitionAvailable = false
        liveQueue.removeAll()
        liveWorkerRunning = false
        segmentChain = Task {}
    }

    private func resetBuffers() {
        stableTranscript = ""
        segmentTexts.removeAll()
        resetSegmentBuffer(seed: nil)
    }

    private func resetSegmentBuffer(seed: Data?) {
        pcmBuffer = seed ?? Data()
        segmentStartedAt = Date()
        lastVoiceDetectedAt = segmentStartedAt
        hasSpeech = false
    }

    private func cleanupFailedSession() {
        hotkeyService.captureEscape = false
        stopElapsedTimer()
        audioCaptureService.cancel()
        _ = speechRecognizer.endSession()
        insertionTarget = nil
        cancelSupplementalGuidance()
    }

    private func disposeSessionResources() {
        hotkeyService.captureEscape = false
        _ = speechRecognizer.endSession()
        insertionTarget = nil
    }

    private func makeWaveFile(pcm: Data) -> Data {
        let byteRate = UInt32(AudioCaptureService.sampleRate) * 2
        var wav = Data()

        func appendASCII(_ value: String) {
            wav.append(contentsOf: Array(value.utf8))
        }

        func appendUInt32(_ value: UInt32) {
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) { wav.append(contentsOf: $0) }
        }

        func appendUInt16(_ value: UInt16) {
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) { wav.append(contentsOf: $0) }
        }

        appendASCII("RIFF")
        appendUInt32(UInt32(36 + pcm.count))
        appendASCII("WAVE")
        appendASCII("fmt ")
        appendUInt32(16)
        appendUInt16(1)
        appendUInt16(1)
        appendUInt32(16_000)
        appendUInt32(byteRate)
        appendUInt16(2)
        appendUInt16(16)
        appendASCII("data")
        appendUInt32(UInt32(pcm.count))
        wav.append(pcm)
        return wav
    }
}

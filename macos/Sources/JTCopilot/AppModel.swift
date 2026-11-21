import AppKit
import Combine
import Foundation
import JTCopilotCore

@MainActor
final class AppModel: ObservableObject {
    // 主状态
    @Published private(set) var isRecording = false
    @Published private(set) var isProcessing = false
    @Published private(set) var isCaptured = false
    @Published private(set) var isSessionActive = false
    @Published private(set) var hasError = false
    @Published var isGuidanceVisible = false {
        didSet { onGuidanceVisibilityChanged?(isGuidanceVisible) }
    }
    @Published var isTopmost = true {
        didSet {
            onTopmostChanged?(isTopmost)
            guard !isInitializing else { return }
            settings.isTopmost = isTopmost
            scheduleSave()
        }
    }
    @Published private(set) var isExpanded = true
    @Published var orbOpacityPercent: Double = 78 {
        didSet {
            guard !isInitializing else { return }
            settings.orbOpacityPercent = orbOpacityPercent
            scheduleSave()
        }
    }
    @Published var guidanceOpacityPercent: Double = 68 {
        didSet {
            guard !isInitializing else { return }
            settings.guidanceOpacityPercent = guidanceOpacityPercent
            scheduleSave()
        }
    }

    // 状态展示
    @Published private(set) var statusTitle = "准备就绪"
    @Published private(set) var statusDetail = "麦克风待命"
    @Published private(set) var statusCode = "IDLE"
    @Published private(set) var elapsedText = "00:00"
    @Published private(set) var microphoneActionLabel = "开始写作"
    @Published private(set) var audioLevel: Double = 0

    // 麦克风
    @Published private(set) var audioDevices: [AudioDeviceDescriptor] = []
    @Published var selectedMicrophone: AudioDeviceDescriptor? {
        didSet {
            guard !isInitializing, !isRefreshingDevices, let selectedMicrophone else { return }
            settings.preferredMicrophoneDeviceId = selectedMicrophone.id
            scheduleSave()
            if !isRecording {
                statusDetail = selectedMicrophone.displayName
            }
        }
    }

    // 快捷键
    @Published private(set) var hotkeyText: String
    @Published private(set) var hotkeyError = ""
    @Published private(set) var isCapturingHotkey = false
    private var capturedKeyCodes = Set<UInt16>()
    private var capturedModifiers: HotkeyModifiers = []

    // 术语与模板
    @Published var customVocabulary: String {
        didSet {
            coordinator.updateCustomVocabulary(customVocabulary)
            guard !isInitializing else { return }
            settings.customVocabulary = customVocabulary
            scheduleSave()
        }
    }
    @Published var selectedDocumentTemplate: DocumentTemplateOption? {
        didSet {
            guard let selectedDocumentTemplate else { return }
            coordinator.updateDocumentTemplate(selectedDocumentTemplate.value)
            detectedTemplateLabel = selectedDocumentTemplate.displayName
            guard !isInitializing else { return }
            settings.guidanceTemplate = selectedDocumentTemplate.value
            scheduleSave()
        }
    }
    @Published private(set) var detectedTemplateLabel = "自动识别"

    // 引导面板内容
    @Published private(set) var liveTranscript = ""
    @Published private(set) var sessionStatus = ""
    @Published private(set) var nextSentence = ""
    @Published private(set) var nextSentenceHistory: [String] = []
    @Published private(set) var optimizedTranscript = ""
    @Published private(set) var replacementMessage = ""
    @Published private(set) var frameworkItems: [String] = []
    @Published private(set) var directionItems: [String] = []
    @Published private(set) var missingPointItems: [String] = []

    // 设置与权限
    @Published private(set) var apiKeyStatus = "尚未配置"
    @Published private(set) var microphoneStatus = "未授权"
    @Published private(set) var speechStatus = "未授权"
    @Published private(set) var accessibilityStatus = "未授权"
    @Published private(set) var lastRecordingPath = ""

    let documentTemplateOptions = DocumentTemplateCatalog.all
    let coordinator: VoiceCaptureCoordinator

    var onSettingsRequested: (() -> Void)?
    var onExitRequested: (() -> Void)?
    var onGuidanceVisibilityChanged: ((Bool) -> Void)?
    var onTopmostChanged: ((Bool) -> Void)?

    private let settingsStore: SettingsStore
    private let audioCaptureService: AudioCaptureService
    private let keyStore: ZhipuApiKeyStore
    private var settings: AppSettings
    private var isInitializing = true
    private var isRefreshingDevices = false
    private var pendingSave: DispatchWorkItem?

    init(
        coordinator: VoiceCaptureCoordinator,
        settingsStore: SettingsStore,
        audioCaptureService: AudioCaptureService,
        keyStore: ZhipuApiKeyStore
    ) {
        self.coordinator = coordinator
        self.settingsStore = settingsStore
        self.audioCaptureService = audioCaptureService
        self.keyStore = keyStore

        let loaded = settingsStore.load().normalized()
        self.settings = loaded
        self.hotkeyText = loaded.hotkeyGesture.macDisplayText
        self.customVocabulary = loaded.customVocabulary
        self.isTopmost = loaded.isTopmost
        self.isExpanded = loaded.isExpanded
        self.orbOpacityPercent = loaded.orbOpacityPercent
        self.guidanceOpacityPercent = loaded.guidanceOpacityPercent
        self.selectedDocumentTemplate = DocumentTemplateCatalog.all.first {
            $0.value == loaded.guidanceTemplate
        } ?? DocumentTemplateCatalog.all[0]
        self.detectedTemplateLabel = self.selectedDocumentTemplate?.displayName ?? "自动识别"

        coordinator.onStateChanged = { [weak self] snapshot in
            Task { @MainActor in self?.applySnapshot(snapshot) }
        }
        coordinator.onLevelChanged = { [weak self] level in
            Task { @MainActor in
                guard let self, self.isRecording else { return }
                self.audioLevel = min(max(level, 0), 1)
            }
        }
        coordinator.onWritingSessionChanged = { [weak self] update in
            Task { @MainActor in self?.applyWritingUpdate(update) }
        }
    }

    var currentSettings: AppSettings {
        settings
    }

    var orbOpacityScale: Double {
        orbOpacityPercent / 100
    }

    var guidanceOpacityScale: Double {
        guidanceOpacityPercent / 100
    }

    var audioLevelPercent: Double {
        audioLevel * 100
    }

    var recordingsDirectoryPath: String {
        AppPaths.recordingsDirectory.path
    }

    func initialize() async {
        isInitializing = true
        defer { isInitializing = false }

        settings = settingsStore.load().normalized()
        hotkeyText = settings.hotkeyGesture.macDisplayText
        customVocabulary = settings.customVocabulary
        isTopmost = settings.isTopmost
        isExpanded = settings.isExpanded
        orbOpacityPercent = settings.orbOpacityPercent
        guidanceOpacityPercent = settings.guidanceOpacityPercent
        selectedDocumentTemplate = documentTemplateOptions.first {
            $0.value == settings.guidanceTemplate
        } ?? documentTemplateOptions[0]
        detectedTemplateLabel = selectedDocumentTemplate?.displayName ?? "自动识别"

        refreshAudioDevices(preferredID: settings.preferredMicrophoneDeviceId)
        apiKeyStatus = keyStore.hasApiKey ? "已安全配置" : "尚未配置"

        await coordinator.initialize()
        refreshPermissions()
        if let hotkeyError = coordinator.hotkeyError {
            self.hotkeyError = "全局快捷键不可用：\(hotkeyError)"
        }
        applySnapshot(coordinator.current)
        applyWritingUpdate(coordinator.currentWritingSession)
    }

    // MARK: - Recording

    func toggleRecording() {
        Task {
            if isRecording {
                await coordinator.finish()
            } else {
                isExpanded = true
                await coordinator.start()
            }
        }
    }

    func toggleExpanded() {
        if isRecording {
            isExpanded = true
            return
        }

        isExpanded.toggle()
        settings.isExpanded = isExpanded
        scheduleSave()
    }

    // MARK: - Window / app commands

    func openSettings() {
        onSettingsRequested?()
    }

    func toggleTopmost() {
        isTopmost.toggle()
    }

    func exitApp() {
        onExitRequested?()
    }

    func openRecordingsFolder() {
        AppPaths.ensureRecordingsDirectory()
        NSWorkspace.shared.open(AppPaths.recordingsDirectory)
    }

    func copyOptimizedText() {
        let text = optimizedTranscript.isEmpty ? liveTranscript : optimizedTranscript
        guard !text.isEmpty else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func toggleGuidance() {
        isGuidanceVisible.toggle()
    }

    func dismissGuidance() {
        isGuidanceVisible = false
    }

    func endGuidanceSession() {
        if isProcessing {
            isGuidanceVisible = true
            return
        }

        guard isRecording else {
            isGuidanceVisible = false
            return
        }

        isGuidanceVisible = true
        Task {
            await coordinator.finish()
        }
    }

    func saveOrbOrigin(x: CGFloat, y: CGFloat) {
        settings.windowLeft = Double(x)
        settings.windowTop = Double(y)
        scheduleSave()
    }

    func persistNow() {
        pendingSave?.cancel()
        pendingSave = nil
        settingsStore.save(settings)
    }

    // MARK: - Settings

    func refreshPermissions() {
        microphoneStatus = Permissions.microphoneAuthorized ? "已授权" : "未授权"
        speechStatus = Permissions.speechAuthorized ? "已授权" : "未授权"
        accessibilityStatus = Permissions.accessibilityTrusted ? "已授权" : "未授权"

        if Permissions.speechAuthorized,
           !coordinator.liveRecognitionReady,
           !coordinator.speechInitializationInFlight {
            Task {
                _ = await coordinator.retrySpeechInitialization()
            }
        }
    }

    func requestMicrophoneAccess() {
        Task {
            _ = await Permissions.requestMicrophone()
            refreshPermissions()
            refreshAudioDevices(preferredID: settings.preferredMicrophoneDeviceId)
        }
    }

    func requestSpeechAccess() {
        Task {
            let granted = await Permissions.requestSpeech()
            refreshPermissions()
            if granted {
                _ = await coordinator.retrySpeechInitialization()
            }
        }
    }

    func requestAccessibilityAccess() {
        _ = Permissions.promptAccessibility()
        Permissions.openAccessibilitySettings()
    }

    func retryHotkey() {
        let success = coordinator.retryHotkey()
        if success {
            hotkeyError = ""
        }
        refreshPermissions()
    }

    func onAccessibilityPermissionChanged(trusted: Bool) {
        refreshPermissions()
        if trusted {
            let success = coordinator.retryHotkey()
            if success {
                hotkeyError = ""
            }
        }
    }

    func refreshAudioDevices(preferredID: String? = nil) {
        isRefreshingDevices = true
        audioDevices = audioCaptureService.inputDevices()
        let preferred = preferredID ?? selectedMicrophone?.id ?? settings.preferredMicrophoneDeviceId
        selectedMicrophone = audioDevices.first { $0.id == preferred }
            ?? audioDevices.first { $0.isDefault }
            ?? audioDevices.first
        isRefreshingDevices = false
    }

    // MARK: - Hotkey capture

    func beginHotkeyCapture() {
        hotkeyError = ""

        if isRecording {
            hotkeyError = "请先结束当前录音，再修改全局快捷键。"
            return
        }

        capturedKeyCodes.removeAll()
        capturedModifiers = []
        isCapturingHotkey = true
        hotkeyText = "请按下新的组合"
    }

    func previewHotkey(modifiers: HotkeyModifiers, keyCode: UInt16) {
        guard isCapturingHotkey else { return }

        if !HotkeyKeyCatalog.isModifierKeyCode(keyCode) {
            capturedModifiers = modifiers
            capturedKeyCodes.insert(keyCode)
        }

        guard !capturedKeyCodes.isEmpty else {
            hotkeyText = "请按下新的组合"
            return
        }

        if let gesture = HotkeyGesture.create(
            modifiers: modifiers,
            macKeyCodes: Array(capturedKeyCodes)
        ) {
            hotkeyText = gesture.macDisplayText
            hotkeyError = ""
        } else {
            hotkeyText = "需要 Ctrl、Alt 或 Cmd 修饰键"
        }
    }

    func finishHotkeyCapture(modifiers: HotkeyModifiers, keyCode: UInt16) {
        guard isCapturingHotkey else { return }

        if !HotkeyKeyCatalog.isModifierKeyCode(keyCode) {
            capturedKeyCodes.insert(keyCode)
        }

        let keys = Array(capturedKeyCodes)
        let effectiveModifiers = modifiers.isEmpty ? capturedModifiers : modifiers
        isCapturingHotkey = false
        capturedKeyCodes.removeAll()
        capturedModifiers = []

        guard !keys.isEmpty,
              let gesture = HotkeyGesture.create(
                  modifiers: effectiveModifiers,
                  macKeyCodes: keys
              ) else {
            hotkeyText = settings.hotkeyGesture.macDisplayText
            hotkeyError = "组合无效，需要 Ctrl、Alt 或 Cmd 修饰键。"
            return
        }

        Task { await applyHotkey(gesture) }
    }

    func cancelHotkeyCapture() {
        isCapturingHotkey = false
        capturedKeyCodes.removeAll()
        capturedModifiers = []
        hotkeyError = ""
        hotkeyText = settings.hotkeyGesture.macDisplayText
    }

    func restoreDefaultHotkey() {
        cancelHotkeyCapture()
        Task { await applyHotkey(.defaultGesture) }
    }

    private func applyHotkey(_ gesture: HotkeyGesture) async {
        let previous = settings.hotkeyGesture

        do {
            try coordinator.updateHotkey(gesture)
            settings.hotkey = gesture.settingString
            scheduleSave()
            hotkeyText = gesture.macDisplayText
            hotkeyError = ""
        } catch {
            try? coordinator.updateHotkey(previous)
            settings.hotkey = previous.settingString
            hotkeyText = previous.macDisplayText
            hotkeyError = "快捷键修改失败：\(error.localizedDescription)"
        }
    }

    // MARK: - Coordinator events

    private func applySnapshot(_ snapshot: VoiceCaptureSnapshot) {
        isRecording = snapshot.state == .recording
        isProcessing = snapshot.state == .processing
        isCaptured = snapshot.state == .completed || snapshot.state == .captured
        isSessionActive = snapshot.state == .recording || snapshot.state == .processing
        hasError = snapshot.state == .faulted

        if snapshot.state == .idle, isGuidanceVisible {
            isGuidanceVisible = false
        }

        if isRecording {
            isExpanded = true
            if !isGuidanceVisible {
                isGuidanceVisible = true
            }
        }

        if !isRecording {
            audioLevel = 0
        }

        elapsedText = formatDuration(snapshot.elapsed)
        microphoneActionLabel = isRecording ? "结束并优化" : "开始写作"

        switch snapshot.state {
        case .idle:
            statusTitle = "准备就绪"
            statusDetail = selectedMicrophone?.displayName ?? "默认麦克风"
            statusCode = "IDLE"
        case .recording:
            statusTitle = "正在实时写作"
            statusDetail = sessionStatus.isEmpty ? "正在聆听" : sessionStatus
            statusCode = "LIVE"
        case .processing:
            statusTitle = "正在整理全文"
            statusDetail = sessionStatus.isEmpty ? "正在检查文字和表达" : sessionStatus
            statusCode = "POLISH"
        case .completed, .captured:
            statusTitle = "会话已完成"
            statusDetail = replacementMessage.isEmpty
                ? "\(formatDuration(snapshot.elapsed)) · 全文已优化"
                : replacementMessage
            statusCode = "DONE"
            lastRecordingPath = snapshot.recordingPath ?? ""
        case .faulted:
            statusTitle = "需要处理"
            statusDetail = snapshot.errorMessage ?? "录音暂不可用"
            statusCode = "ERROR"
        }
    }

    private func applyWritingUpdate(_ update: WritingSessionUpdate) {
        liveTranscript = update.stableTranscript
        sessionStatus = update.statusText
        nextSentence = update.guidance.nextSentence
        nextSentenceHistory = update.guidance.nextSentenceHistory
        detectedTemplateLabel = update.guidance.template == .auto && selectedDocumentTemplate != nil
            ? selectedDocumentTemplate?.displayName ?? "自动识别"
            : DocumentTemplateCatalog.displayName(for: update.guidance.template)
        optimizedTranscript = update.optimizedTranscript
        replacementMessage = update.replacementMessage

        frameworkItems = update.guidance.framework
        directionItems = update.guidance.directions
        missingPointItems = update.guidance.missingPoints

        if isRecording {
            statusDetail = update.statusText
        } else if isProcessing {
            statusDetail = update.statusText
        } else if isCaptured, !update.replacementMessage.isEmpty {
            statusDetail = update.replacementMessage
        }
    }

    // MARK: - Helpers

    private func scheduleSave() {
        guard !isInitializing else { return }

        pendingSave?.cancel()
        let settingsSnapshot = settings
        let item = DispatchWorkItem { [settingsStore] in
            settingsStore.save(settingsSnapshot)
        }
        pendingSave = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: item)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

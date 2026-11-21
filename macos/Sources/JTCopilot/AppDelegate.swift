import AppKit
import Darwin
import Foundation
import JTCopilotCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?
    private var coordinator: VoiceCaptureCoordinator?
    private var orbController: OrbWindowController?
    private var guidanceController: GuidanceWindowController?
    private var settingsController: SettingsWindowController?
    private var statusItemController: StatusItemController?
    private var permissionTimer: Timer?
    private var lastAccessibilityState: Bool?
    private var lockFileDescriptor: Int32 = -1

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("JT Copilot: applicationDidFinishLaunching")
        AppPaths.ensureRootDirectory()

        guard acquireSingleInstanceLock() else {
            NSLog("JT Copilot: another instance already holds the lock")
            let alert = NSAlert()
            alert.messageText = "JT Copilot 已经在运行"
            alert.informativeText = "请查看屏幕右下角的悬浮球或菜单栏里的 JT Copilot 图标。"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "好")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
            NSApp.terminate(nil)
            return
        }

        NSApp.setActivationPolicy(.accessory)
        buildMainMenu()

        let settingsStore = SettingsStore()
        let audioCaptureService = AudioCaptureService()
        let apiKeyStore = ZhipuApiKeyStore()
        let domainTermCorrector = DomainTermCorrector()

        let coordinator = VoiceCaptureCoordinator(
            audioCaptureService: audioCaptureService,
            hotkeyService: HotkeyService(),
            settingsStore: settingsStore,
            speechRecognitionProvider: ZhipuSpeechRecognitionProvider(apiKeyStore: apiKeyStore),
            writingModelProvider: ZhipuWritingModelProvider(apiKeyStore: apiKeyStore),
            documentFrameworkEngine: DocumentFrameworkEngine(),
            domainTermCorrector: domainTermCorrector,
            textInsertionService: TextInsertionService(),
            speechRecognizer: AppleSpeechRecognizer()
        )

        let model = AppModel(
            coordinator: coordinator,
            settingsStore: settingsStore,
            audioCaptureService: audioCaptureService,
            keyStore: apiKeyStore
        )

        let orbController = OrbWindowController(model: model)
        let guidanceController = GuidanceWindowController(model: model)
        let settingsController = SettingsWindowController(model: model)
        let statusItemController = StatusItemController(model: model)

        self.coordinator = coordinator
        self.model = model
        self.orbController = orbController
        self.guidanceController = guidanceController
        self.settingsController = settingsController
        self.statusItemController = statusItemController

        model.onSettingsRequested = { [weak self] in
            self?.settingsController?.showSettings()
        }
        model.onExitRequested = {
            NSApp.terminate(nil)
        }

        orbController.showOrb()
        NSLog("JT Copilot: orb shown, frame=%@", NSStringFromRect(orbController.window?.frame ?? .zero))
        lastAccessibilityState = Permissions.accessibilityTrusted
        startPermissionMonitor()

        Task {
            await model.initialize()
            _ = await Permissions.requestMicrophone()
            model.refreshPermissions()
            model.refreshAudioDevices(
                preferredID: model.currentSettings.preferredMicrophoneDeviceId
            )
            presentOnboardingIfNeeded()

            if !Permissions.accessibilityTrusted {
                _ = Permissions.promptAccessibility()
                model.refreshPermissions()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionTimer?.invalidate()
        permissionTimer = nil
        model?.persistNow()
        coordinator?.dispose()

        if lockFileDescriptor >= 0 {
            flock(lockFileDescriptor, LOCK_UN)
            close(lockFileDescriptor)
            lockFileDescriptor = -1
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - Startup helpers

    private func presentOnboardingIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "jtcopilot.onboarding.shown") else { return }
        defaults.set(true, forKey: "jtcopilot.onboarding.shown")

        guard let model else { return }
        let missingApiKey = model.apiKeyStatus != "已安全配置"
        guard missingApiKey || !Permissions.accessibilityTrusted else { return }

        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "欢迎使用 JT Copilot"
        alert.informativeText = """
        macOS 版使用系统语音识别做实时逐字预览，结束时再由智谱 GLM-ASR 与 GLM-4.6 校正全文。

        首次使用请完成：
        • 授予麦克风、语音识别和辅助功能权限
        • 通过“配置智谱Key.command”或 ZHIPU_API_KEY 环境变量配置智谱密钥

        辅助功能用于全局快捷键 ⌃⇧J T 与向其他应用写入文字。授权后若快捷键无效，请重启应用。
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "打开设置")
        alert.addButton(withTitle: "稍后")

        if alert.runModal() == .alertFirstButtonReturn {
            settingsController?.showSettings()
        }
    }

    private func startPermissionMonitor() {
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let trusted = Permissions.accessibilityTrusted
                if trusted != self.lastAccessibilityState {
                    self.lastAccessibilityState = trusted
                    self.model?.onAccessibilityPermissionChanged(trusted: trusted)
                }
            }
        }
    }

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        let quitItem = NSMenuItem(
            title: "退出 JT Copilot",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenu.addItem(quitItem)
        appMenuItem.submenu = appMenu

        NSApp.mainMenu = mainMenu
    }

    private func acquireSingleInstanceLock() -> Bool {
        let path = AppPaths.lockFileURL.path
        let descriptor = open(path, O_CREAT | O_RDWR, 0o644)
        guard descriptor >= 0 else {
            return true
        }

        if flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            close(descriptor)
            return false
        }

        lockFileDescriptor = descriptor
        return true
    }
}

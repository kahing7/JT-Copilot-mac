import AppKit

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let model: AppModel
    private let statusItem: NSStatusItem
    private let recordingItem: NSMenuItem
    private let guidanceItem: NSMenuItem
    private let topmostItem: NSMenuItem

    init(model: AppModel) {
        self.model = model
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        self.recordingItem = NSMenuItem(title: "开始写作", action: #selector(toggleRecording), keyEquivalent: "")
        self.guidanceItem = NSMenuItem(title: "显示引导面板", action: #selector(toggleGuidance), keyEquivalent: "")
        self.topmostItem = NSMenuItem(title: "窗口置顶", action: #selector(toggleTopmost), keyEquivalent: "")

        super.init()

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "waveform.circle",
                accessibilityDescription: "JT Copilot"
            )
            button.image?.isTemplate = true
            button.toolTip = "JT Copilot"
        }

        let menu = NSMenu()
        menu.delegate = self

        recordingItem.target = self
        guidanceItem.target = self
        topmostItem.target = self

        menu.addItem(recordingItem)
        menu.addItem(guidanceItem)
        menu.addItem(topmostItem)
        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "打开设置…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出 JT Copilot", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        recordingItem.title = model.isRecording ? "结束写作" : "开始写作"
        guidanceItem.title = model.isGuidanceVisible ? "隐藏引导面板" : "显示引导面板"
        topmostItem.state = model.isTopmost ? .on : .off
    }

    @objc private func toggleRecording() {
        model.toggleRecording()
    }

    @objc private func toggleGuidance() {
        model.toggleGuidance()
    }

    @objc private func toggleTopmost() {
        model.toggleTopmost()
    }

    @objc private func openSettings() {
        model.openSettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

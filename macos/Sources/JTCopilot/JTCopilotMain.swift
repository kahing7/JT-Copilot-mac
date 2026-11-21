import AppKit

@main
struct JTCopilotMain {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let appDelegate = AppDelegate()
        application.delegate = appDelegate
        application.setActivationPolicy(.accessory)

        withExtendedLifetime(appDelegate) {
            application.run()
        }
    }
}

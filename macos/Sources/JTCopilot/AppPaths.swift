import Foundation

enum AppPaths {
    static let rootDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("JT Copilot", isDirectory: true)
    }()

    static var settingsFileURL: URL {
        rootDirectory.appendingPathComponent("settings.json")
    }

    static var recordingsDirectory: URL {
        rootDirectory.appendingPathComponent("recordings", isDirectory: true)
    }

    static var lockFileURL: URL {
        rootDirectory.appendingPathComponent(".lock")
    }

    static func ensureRootDirectory() {
        try? FileManager.default.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )
    }

    static func ensureRecordingsDirectory() {
        try? FileManager.default.createDirectory(
            at: recordingsDirectory,
            withIntermediateDirectories: true
        )
    }
}

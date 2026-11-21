import Foundation
import JTCopilotCore

final class SettingsStore {
    private let fileURL: URL

    init(fileURL: URL = AppPaths.settingsFileURL) {
        self.fileURL = fileURL
    }

    func load() -> AppSettings {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return AppSettings()
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let settings = try JSONDecoder().decode(AppSettings.self, from: data)
            return settings.normalized()
        } catch {
            NSLog("JT Copilot: settings could not be read (%@), using defaults.", String(describing: error))
            return AppSettings()
        }
    }

    func save(_ settings: AppSettings) {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
            let data = try encoder.encode(settings.normalized())
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("JT Copilot: settings could not be saved (%@).", String(describing: error))
        }
    }
}

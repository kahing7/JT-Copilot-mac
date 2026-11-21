import Foundation

public enum GuidanceHistory {
    public static let defaultLimit = 30

    public static func appending(
        _ sentence: String,
        to history: [String],
        limit: Int = defaultLimit
    ) -> [String] {
        let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, history.last != trimmed else {
            return history
        }

        return Array((history + [trimmed]).suffix(max(limit, 1)))
    }

    public static func visibleHistory(
        _ history: [String],
        current: String
    ) -> [String] {
        let trimmedCurrent = current.trimmingCharacters(in: .whitespacesAndNewlines)
        guard history.last == trimmedCurrent else {
            return history
        }
        return Array(history.dropLast())
    }
}

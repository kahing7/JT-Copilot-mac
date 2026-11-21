import Foundation

/// Separates the current speech hypothesis from text already committed for the session.
public struct SessionTranscriptAccumulator: Equatable, Sendable {
    public private(set) var completedText = ""
    public private(set) var currentText = ""
    private var lastCommittedUtterance = ""

    public init() {}

    public var fullText: String {
        TranscriptMerger.append(
            existing: completedText,
            incoming: currentText
        ).text
    }

    public mutating func updateHypothesis(_ value: String) {
        let normalized = TranscriptMerger.normalizeSpeechText(value)
        guard !normalized.isEmpty else {
            currentText = ""
            return
        }

        if !completedText.isEmpty, normalized.hasPrefix(completedText) {
            let remainder = String(normalized.dropFirst(completedText.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            currentText = isAlreadyCommitted(remainder) ? "" : remainder
            return
        }

        if isAlreadyCommitted(normalized) {
            currentText = ""
            return
        }

        currentText = normalized
    }

    public mutating func commitCurrent() {
        let value = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }

        completedText = TranscriptMerger.append(
            existing: completedText,
            incoming: value
        ).text
        lastCommittedUtterance = value
        currentText = ""
    }

    public mutating func reset() {
        self = SessionTranscriptAccumulator()
    }

    private func isAlreadyCommitted(_ value: String) -> Bool {
        guard value.count >= 4 else { return false }
        if completedText.contains(value) {
            return true
        }
        return !lastCommittedUtterance.isEmpty
            && lastCommittedUtterance.hasPrefix(value)
    }
}

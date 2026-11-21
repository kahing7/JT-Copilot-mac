import Foundation

public enum TranscriptMerger {
    public static func findOverlap(existing: String, incoming: String) -> Int {
        let existingCharacters = Array(existing)
        let incomingCharacters = Array(incoming)

        guard !existingCharacters.isEmpty, !incomingCharacters.isEmpty else {
            return 0
        }

        let maximum = min(48, min(existingCharacters.count, incomingCharacters.count))
        guard maximum >= 4 else {
            return 0
        }

        for length in stride(from: maximum, through: 4, by: -1) {
            let existingSuffix = Array(existingCharacters.suffix(length))
            let incomingPrefix = Array(incomingCharacters.prefix(length))

            if existingSuffix == incomingPrefix {
                return length
            }

            let normalizedSuffix = normalizeForOverlap(String(existingSuffix))
            let normalizedPrefix = normalizeForOverlap(String(incomingPrefix))
            if normalizedSuffix.count >= 4,
               normalizedPrefix.count >= 4,
               normalizedSuffix.hasSuffix(normalizedPrefix) {
                return length
            }
        }

        return 0
    }

    public static func needsSpace(existing: String, incoming: String) -> Bool {
        guard let left = existing.last, let right = incoming.first else {
            return false
        }

        return !left.isWhitespace
            && !right.isWhitespace
            && !left.isPunctuation
            && !right.isPunctuation
            && isAsciiLetterOrDigit(left)
            && isAsciiLetterOrDigit(right)
    }

    /// 返回合并后的全文以及本次实际追加的片段（没有新增内容时 appended 为空）。
    public static func append(existing: String, incoming: String) -> (text: String, appended: String) {
        let normalizedIncoming = incoming.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedIncoming.isEmpty else {
            return (existing, "")
        }

        let overlap = findOverlap(existing: existing, incoming: normalizedIncoming)
        let newText = String(Array(normalizedIncoming).dropFirst(overlap))
        guard !newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return (existing, "")
        }

        if existing.hasSuffix(newText) {
            return (existing, "")
        }

        let separator = needsSpace(existing: existing, incoming: newText) ? " " : ""
        return (existing + separator + newText, separator + newText)
    }

    /// 语音结果中偶尔会夹带中文之间的空格；这里把它们去掉。
    public static func normalizeSpeechText(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        var result = trimmed
        if let regex = try? NSRegularExpression(pattern: "(?<=\\p{Han}) (?=\\p{Han})") {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "")
        }

        return result.replacingOccurrences(of: "  ", with: " ")
    }

    private static func normalizeForOverlap(_ value: String) -> String {
        String(value.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    private static func isAsciiLetterOrDigit(_ character: Character) -> Bool {
        guard character.isASCII else { return false }
        return character.isLetter || character.isNumber
    }
}

import Foundation

public struct LiveTextDiff: Equatable, Sendable {
    /// 公共前缀长度，单位为 UTF-16 code unit，与 Windows 实现一致。
    public let commonPrefixLength: Int
    /// 需要删除的 UTF-16 code unit 数量。
    public let charactersToDelete: Int
    /// 需要输入的 UTF-16 code unit 数量。
    public let charactersToInsert: Int
    /// 需要删除的实际后缀文本。
    public let textToDelete: String
    /// 需要输入的实际后缀文本。
    public let textToInsert: String

    public init(
        commonPrefixLength: Int,
        charactersToDelete: Int,
        charactersToInsert: Int,
        textToDelete: String,
        textToInsert: String
    ) {
        self.commonPrefixLength = commonPrefixLength
        self.charactersToDelete = charactersToDelete
        self.charactersToInsert = charactersToInsert
        self.textToDelete = textToDelete
        self.textToInsert = textToInsert
    }

    /// 删除时按“用户感知字符”计数，避免把一个 emoji 拆成两次退格。
    public var backspaceCount: Int {
        textToDelete.count
    }
}

public enum LiveTextDiffCalculator {
    public static func calculate(previous: String, current: String) -> LiveTextDiff {
        let previousUnits = Array(previous.utf16)
        let currentUnits = Array(current.utf16)
        let maximum = min(previousUnits.count, currentUnits.count)
        var prefixLength = 0

        while prefixLength < maximum && previousUnits[prefixLength] == currentUnits[prefixLength] {
            prefixLength += 1
        }

        if prefixLength > 0,
           prefixLength < previousUnits.count,
           (0xD800...0xDBFF).contains(previousUnits[prefixLength - 1]) {
            prefixLength -= 1
        }

        let previousIndex = String.Index(utf16Offset: prefixLength, in: previous)
        let currentIndex = String.Index(utf16Offset: prefixLength, in: current)

        return LiveTextDiff(
            commonPrefixLength: prefixLength,
            charactersToDelete: previousUnits.count - prefixLength,
            charactersToInsert: currentUnits.count - prefixLength,
            textToDelete: String(previous[previousIndex...]),
            textToInsert: String(current[currentIndex...])
        )
    }
}

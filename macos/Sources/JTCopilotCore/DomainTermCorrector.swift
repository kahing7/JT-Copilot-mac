import Foundation

/// 业务术语本地纠正。规则与 Windows 版 DomainTermCorrector 保持一致：
/// 自定义词条优先，内置词条补齐；ASCII 缩写按单词边界匹配。
public final class DomainTermCorrector {
    private struct TermRule {
        let standard: String
        var aliases: [String]
    }

    private struct AliasRule {
        let alias: String
        let standard: String
        let order: Int
    }

    private static let defaultRules: [TermRule] = [
        TermRule(standard: "CRM系统", aliases: ["新奥尔良系统", "新奥良系统", "新奥尔良"]),
        TermRule(standard: "CRM", aliases: ["西阿艾姆", "CRM"]),
        TermRule(standard: "积分兑礼", aliases: ["积分队里区", "积分队里", "积分兑里", "积分兑换"]),
        TermRule(standard: "OK", aliases: ["欧克", "欧凯", "okay", "OK"]),
        TermRule(standard: "PRD", aliases: ["PRD"]),
        TermRule(standard: "API", aliases: ["API"]),
        TermRule(standard: "OKR", aliases: ["OKR"]),
        TermRule(standard: "KPI", aliases: ["KPI"]),
        TermRule(standard: "WBS", aliases: ["WBS"]),
        TermRule(standard: "RACI", aliases: ["RACI"]),
        TermRule(standard: "AI", aliases: ["AI"])
    ]

    private static let defaultHotwords: [String] = [
        "CRM", "CRM系统", "积分兑礼", "OK", "PRD", "API", "OKR", "KPI", "WBS", "RACI", "AI",
        "项目管理", "业务目标", "项目背景", "项目范围", "里程碑", "验收标准"
    ]

    private let lock = NSLock()
    private var ruleCache: [String: [TermRule]] = [:]

    public init() {}

    public func correct(_ text: String, customVocabulary: String?) -> String {
        guard !text.isEmpty else { return text }

        let aliases = buildRules(customVocabulary)
            .enumerated()
            .flatMap { ruleIndex, rule in
                rule.aliases.map { AliasRule(alias: $0, standard: rule.standard, order: ruleIndex) }
            }

        var seenAliases = Set<String>()
        let distinctAliases = aliases
            .filter { seenAliases.insert($0.alias.lowercased()).inserted }
            .sorted {
                if $0.alias.count != $1.alias.count {
                    return $0.alias.count > $1.alias.count
                }
                return $0.order < $1.order
            }

        guard !distinctAliases.isEmpty else { return text }

        let pattern = distinctAliases.map { rule -> String in
            let escaped = NSRegularExpression.escapedPattern(for: rule.alias)
            if isAscii(rule.alias) {
                return "(?<![A-Za-z0-9])\(escaped)(?![A-Za-z0-9])"
            }
            return escaped
        }.joined(separator: "|")

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }

        let source = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: source.length))
        let corrected = NSMutableString(string: text)

        for match in matches.reversed() {
            let matchedText = source.substring(with: match.range)
            guard let rule = distinctAliases.first(where: {
                $0.alias.caseInsensitiveCompare(matchedText) == .orderedSame
            }) else {
                continue
            }

            corrected.replaceCharacters(in: match.range, with: rule.standard)
        }

        // Vosk / 语音识别常把“OK 吗”听成“可以吗”；只在已知业务术语后纠正。
        let contextPattern = "(积分兑礼|CRM系统)([，,\\s]{0,4})可以吗"
        if let contextRegex = try? NSRegularExpression(pattern: contextPattern) {
            let correctedString = corrected as String
            let range = NSRange(location: 0, length: (correctedString as NSString).length)
            return contextRegex.stringByReplacingMatches(
                in: correctedString,
                range: range,
                withTemplate: "$1$2OK吗"
            )
        }

        return corrected as String
    }

    public func hotwords(_ customVocabulary: String?) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for standard in buildRules(customVocabulary).map(\.standard) + DomainTermCorrector.defaultHotwords {
            if seen.insert(standard.lowercased()).inserted {
                result.append(standard)
            }
            if result.count >= 100 {
                break
            }
        }

        return result
    }

    public func defaultAliases(for standardTerm: String) -> [String] {
        DomainTermCorrector.defaultRules
            .first { $0.standard.caseInsensitiveCompare(standardTerm) == .orderedSame }?
            .aliases ?? []
    }

    private func buildRules(_ customVocabulary: String?) -> [TermRule] {
        let key = customVocabulary ?? ""

        lock.lock()
        if let cached = ruleCache[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        var rules = parseCustomRules(key).map {
            TermRule(standard: $0.standard, aliases: $0.aliases)
        }

        for defaultRule in DomainTermCorrector.defaultRules {
            if let index = rules.firstIndex(where: {
                $0.standard.caseInsensitiveCompare(defaultRule.standard) == .orderedSame
            }) {
                for alias in defaultRule.aliases where !rules[index].aliases.contains(where: {
                    $0.caseInsensitiveCompare(alias) == .orderedSame
                }) {
                    rules[index].aliases.append(alias)
                }
            } else {
                rules.append(TermRule(standard: defaultRule.standard, aliases: defaultRule.aliases))
            }
        }

        lock.lock()
        ruleCache[key] = rules
        lock.unlock()
        return rules
    }

    private func parseCustomRules(_ customVocabulary: String) -> [TermRule] {
        var rules: [TermRule] = []

        let lines = customVocabulary.components(separatedBy: .newlines)
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            guard let separatorIndex = line.firstIndex(of: "=") else { continue }
            let standard = String(line[..<separatorIndex]).trimmingCharacters(in: .whitespaces)
            guard !standard.isEmpty else { continue }

            let aliasText = String(line[line.index(after: separatorIndex)...])
            let aliases = aliasText
                .split(whereSeparator: { $0 == "," || $0 == "，" })
                .map { String($0).trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            var uniqueAliases: [String] = []
            for alias in aliases where !uniqueAliases.contains(where: {
                $0.caseInsensitiveCompare(alias) == .orderedSame
            }) {
                uniqueAliases.append(alias)
            }

            if let index = rules.firstIndex(where: {
                $0.standard.caseInsensitiveCompare(standard) == .orderedSame
            }) {
                for alias in uniqueAliases where !rules[index].aliases.contains(where: {
                    $0.caseInsensitiveCompare(alias) == .orderedSame
                }) {
                    rules[index].aliases.append(alias)
                }
            } else {
                rules.append(TermRule(standard: standard, aliases: uniqueAliases))
            }
        }

        return rules
    }

    private func isAscii(_ value: String) -> Bool {
        value.allSatisfy { $0.isASCII }
    }
}

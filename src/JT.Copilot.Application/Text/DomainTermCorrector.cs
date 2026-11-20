using System.Collections.Concurrent;
using System.Text.RegularExpressions;

namespace JT.Copilot.Application.Text;

public sealed class DomainTermCorrector
{
    private static readonly IReadOnlyList<TermRule> DefaultRules =
    [
        new("CRM系统", ["新奥尔良系统", "新奥良系统", "新奥尔良"]),
        new("CRM", ["西阿艾姆", "CRM"]),
        new("积分兑礼", ["积分队里区", "积分队里", "积分兑里", "积分兑换"]),
        new("OK", ["欧克", "欧凯", "okay", "OK"]),
        new("PRD", ["PRD"]),
        new("API", ["API"]),
        new("OKR", ["OKR"]),
        new("KPI", ["KPI"]),
        new("WBS", ["WBS"]),
        new("RACI", ["RACI"]),
        new("AI", ["AI"])
    ];

    private static readonly IReadOnlyList<string> DefaultHotwords =
    [
        "CRM",
        "CRM系统",
        "积分兑礼",
        "OK",
        "PRD",
        "API",
        "OKR",
        "KPI",
        "WBS",
        "RACI",
        "AI",
        "项目管理",
        "业务目标",
        "项目背景",
        "项目范围",
        "里程碑",
        "验收标准"
    ];

    private readonly ConcurrentDictionary<string, IReadOnlyList<TermRule>> _ruleCache =
        new(StringComparer.Ordinal);

    public string Correct(string text, string? customVocabulary)
    {
        if (string.IsNullOrEmpty(text))
        {
            return text;
        }

        var aliases = BuildRules(customVocabulary)
            .SelectMany(rule => rule.Aliases.Select(alias => new AliasRule(alias, rule.Standard)))
            .DistinctBy(rule => rule.Alias, StringComparer.OrdinalIgnoreCase)
            .OrderByDescending(rule => rule.Alias.Length)
            .ToArray();

        if (aliases.Length == 0)
        {
            return text;
        }

        var pattern = string.Join(
            "|",
            aliases.Select(aliasRule =>
            {
                var escaped = Regex.Escape(aliasRule.Alias);
                return IsAscii(aliasRule.Alias)
                    ? $"(?<![A-Za-z0-9]){escaped}(?![A-Za-z0-9])"
                    : escaped;
            }));

        var corrected = Regex.Replace(
            text,
            pattern,
            match => aliases.First(rule =>
                string.Equals(rule.Alias, match.Value, StringComparison.OrdinalIgnoreCase)).Standard,
            RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);

        // Vosk often hears "OK吗" as "可以吗"; only correct it next to a known business term.
        return Regex.Replace(
            corrected,
            @"(积分兑礼|CRM系统)([，,\s]{0,4})可以吗",
            "$1$2OK吗",
            RegexOptions.CultureInvariant);
    }

    public IReadOnlyList<string> GetHotwords(string? customVocabulary)
    {
        return BuildRules(customVocabulary)
            .Select(rule => rule.Standard)
            .Concat(DefaultHotwords)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .Take(100)
            .ToArray();
    }

    public IReadOnlyList<string> GetDefaultAliases(string standardTerm)
    {
        return DefaultRules
            .FirstOrDefault(rule => string.Equals(rule.Standard, standardTerm, StringComparison.OrdinalIgnoreCase))
            ?.Aliases
            ?? [];
    }

    private IReadOnlyList<TermRule> BuildRules(string? customVocabulary)
    {
        var key = customVocabulary ?? string.Empty;
        return _ruleCache.GetOrAdd(key, _ =>
        {
            var customRules = ParseCustomRules(key);
            var rules = customRules
                .Select(rule => new TermRule(rule.Standard, rule.Aliases.ToList()))
                .ToList();

            foreach (var defaultRule in DefaultRules)
            {
                var existing = rules.FirstOrDefault(rule =>
                    string.Equals(rule.Standard, defaultRule.Standard, StringComparison.OrdinalIgnoreCase));

                if (existing is null)
                {
                    rules.Add(new TermRule(defaultRule.Standard, defaultRule.Aliases.ToList()));
                    continue;
                }

                foreach (var alias in defaultRule.Aliases)
                {
                    if (!existing.Aliases.Contains(alias, StringComparer.OrdinalIgnoreCase))
                    {
                        existing.Aliases.Add(alias);
                    }
                }
            }

            return rules;
        });
    }

    private static IReadOnlyList<TermRule> ParseCustomRules(string customVocabulary)
    {
        var rules = new List<TermRule>();

        foreach (var line in customVocabulary.Split(
                     ['\r', '\n'],
                     StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            var separatorIndex = line.IndexOf('=');
            if (separatorIndex <= 0)
            {
                continue;
            }

            var standard = line[..separatorIndex].Trim();
            if (standard.Length == 0)
            {
                continue;
            }

            var aliases = line[(separatorIndex + 1)..]
                .Split([',', '，'], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
                .Where(alias => alias.Length > 0)
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .ToList();
            var existing = rules.FirstOrDefault(rule =>
                string.Equals(rule.Standard, standard, StringComparison.OrdinalIgnoreCase));

            if (existing is null)
            {
                rules.Add(new TermRule(standard, aliases));
                continue;
            }

            foreach (var alias in aliases)
            {
                if (!existing.Aliases.Contains(alias, StringComparer.OrdinalIgnoreCase))
                {
                    existing.Aliases.Add(alias);
                }
            }
        }

        return rules;
    }

    private static bool IsAscii(string value)
    {
        return value.All(character => character <= 0x7F);
    }

    private sealed record TermRule(string Standard, List<string> Aliases);

    private sealed record AliasRule(string Alias, string Standard);
}

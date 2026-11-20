using JT.Copilot.Application.Abstractions;
using JT.Copilot.Application.Models;

namespace JT.Copilot.Application.Guidance;

public sealed class LocalDocumentFrameworkEngine : IDocumentFrameworkEngine
{
    private static readonly FrameworkDefinition ProjectManagement = new(
        DocumentTemplate.ProjectManagement,
        "项目管理文档",
        [
            new("项目背景", "先交代一下项目背景", "补充项目起因、当前现状和需要解决的问题", ["项目背景", "背景", "起因", "当前现状", "当前情况", "问题"]),
            new("业务目标", "接下来对齐项目的业务目标", "说明目标、预期收益和衡量指标", ["业务目标", "项目目标", "目标", "收益", "价值", "指标"]),
            new("项目范围", "说明项目范围和边界", "明确包含事项、不包含事项和关键约束", ["项目范围", "范围", "边界", "不包含", "包含"]),
            new("规划与里程碑", "介绍项目规划和关键里程碑", "写清阶段、时间节点和关键里程碑", ["项目规划", "规划", "里程碑", "排期", "计划", "阶段"]),
            new("组织与职责", "说明干系人与职责", "列出关键角色、负责人和决策机制", ["项目组织", "职责", "干系人", "负责人", "决策人"]),
            new("风险与依赖", "补充风险和依赖", "说明风险影响、应对方式和外部依赖", ["风险", "依赖", "约束", "应对"]),
            new("交付物与验收标准", "给出交付物和验收标准", "写清交付成果、完成定义和验收方式", ["交付物", "交付成果", "验收", "完成定义"])
        ],
        ["项目管理", "项目背景", "业务目标", "项目范围", "里程碑", "干系人", "风险", "依赖", "交付物", "验收标准"]);

    private static readonly FrameworkDefinition Prd = new(
        DocumentTemplate.Prd,
        "产品需求文档",
        [
            new("背景与问题", "先说明需求背景和要解决的问题", "交代用户痛点、现状和触发原因", ["需求背景", "背景", "问题", "痛点", "现状"]),
            new("用户与场景", "说明目标用户和使用场景", "写清用户角色、任务和高频场景", ["用户", "场景", "角色", "人群"]),
            new("目标与指标", "明确产品目标和成功指标", "给出可衡量的业务或体验指标", ["产品目标", "目标", "指标", "成功标准"]),
            new("功能范围", "说明功能范围和优先级", "区分本期必须、可选和暂不实现的内容", ["功能范围", "功能", "优先级", "范围"]),
            new("流程与交互", "描述核心流程和关键交互", "按用户任务顺序讲清主流程和异常分支", ["流程", "交互", "路径", "异常"]),
            new("需求细节", "补充规则、数据和异常处理", "说明校验、权限、状态和边界条件", ["规则", "数据", "权限", "状态", "边界"]),
            new("验收标准", "给出验收标准和完成定义", "列出可测试的验收条件和结果", ["验收", "完成定义", "测试"])
        ],
        ["PRD", "产品需求", "用户故事", "需求文档", "功能需求"]);

    private static readonly FrameworkDefinition WeeklyReport = new(
        DocumentTemplate.WeeklyReport,
        "工作周报",
        [
            new("本周进展", "先总结本周完成的关键进展", "用结果和影响说明完成情况", ["本周进展", "本周完成", "进展", "完成"]),
            new("关键结果", "补充关键结果和业务价值", "给出数据、产出和实际影响", ["关键结果", "结果", "价值", "数据"]),
            new("问题与风险", "说明当前问题和风险", "写清阻塞点、影响和需要的支持", ["问题", "风险", "阻塞", "困难"]),
            new("下周计划", "列出下周计划和优先事项", "按优先级说明目标和预期产出", ["下周计划", "下周", "计划", "优先"]),
            new("协作与依赖", "补充需要协同的事项和依赖", "明确责任人、时间和需要的决策", ["协作", "依赖", "支持", "协同"])
        ],
        ["周报", "本周", "下周", "本周进展", "工作汇报"]);

    private static readonly FrameworkDefinition Solution = new(
        DocumentTemplate.Solution,
        "方案文档",
        [
            new("背景与现状", "先说明方案背景和当前现状", "交代问题、机会和已有条件", ["背景", "现状", "问题", "机会"]),
            new("目标与约束", "明确方案目标和关键约束", "写清成功标准、时间、成本和边界", ["目标", "约束", "成功标准", "边界"]),
            new("总体方案", "介绍总体方案和处理思路", "先给整体路径，再展开关键模块", ["总体方案", "整体方案", "思路", "方案"]),
            new("关键设计", "说明关键设计和技术取舍", "解释核心机制、接口和替代方案", ["关键设计", "设计", "架构", "接口", "取舍"]),
            new("实施计划", "给出实施计划和资源安排", "说明阶段、负责人和依赖关系", ["实施计划", "实施", "计划", "资源"]),
            new("风险与备选", "补充风险、依赖和备选方案", "给出触发条件、应对措施和回退路径", ["风险", "备选", "回退", "依赖"]),
            new("验收标准", "最后说明验收和上线标准", "写清验证方法、完成定义和上线条件", ["验收", "上线", "完成定义"])
        ],
        ["方案", "总体设计", "技术方案", "架构", "实施计划"]);

    private static readonly FrameworkDefinition General = new(
        DocumentTemplate.General,
        "通用写作",
        [
            new("主题与背景", "先交代主题和背景", "说明为什么写、面向谁和解决什么问题", ["主题", "背景", "问题"]),
            new("核心观点", "先给出核心观点或结论", "把最关键的信息放在前面", ["观点", "结论", "核心"]),
            new("结构展开", "按逻辑顺序展开主要内容", "使用并列、递进或问题解决结构", ["第一", "第二", "首先", "其次", "然后"]),
            new("依据与细节", "补充事实、数据和例子", "用证据支撑观点并说明边界", ["数据", "案例", "例如", "依据"]),
            new("总结与行动", "最后总结结论和下一步行动", "写清结论、行动项和责任人", ["总结", "下一步", "行动"])
        ],
        []);

    public DocumentFrameworkResult Build(string transcript, DocumentTemplate template)
    {
        var resolvedTemplate = template == DocumentTemplate.Auto
            ? DetectTemplate(transcript)
            : template;
        var definition = GetDefinition(resolvedTemplate);
        var currentIndex = FindCurrentStage(transcript, definition.Stages);
        var nextIndex = currentIndex < 0
            ? 0
            : Math.Min(currentIndex + 1, definition.Stages.Count - 1);
        var nextStage = definition.Stages[nextIndex];
        var framework = definition.Stages
            .Select((stage, index) => index switch
            {
                var value when value < currentIndex => $"{value + 1}. {stage.Title}（已涉及）",
                var value when value == currentIndex => $"{value + 1}. {stage.Title}（当前）",
                _ => $"{index + 1}. {stage.Title}"
            })
            .ToArray();
        var nextSentence = currentIndex == definition.Stages.Count - 1
            ? "最后收束全文，检查交付物和验收标准"
            : nextStage.Prompt;
        var directions = new List<string>
        {
            nextStage.Prompt,
            nextStage.Direction
        };

        if (currentIndex >= 0)
        {
            directions.Insert(0, $"当前结构：{definition.Stages[currentIndex].Title}");
        }

        return new DocumentFrameworkResult(
            definition.Template,
            definition.DisplayName,
            new WritingGuidance(
                framework,
                nextSentence,
                directions,
                [nextStage.Direction],
                definition.Template));
    }

    public DocumentTemplate DetectTemplate(string transcript)
    {
        if (string.IsNullOrWhiteSpace(transcript))
        {
            return DocumentTemplate.General;
        }

        var definitions = new[]
        {
            ProjectManagement,
            Prd,
            WeeklyReport,
            Solution
        };
        var scores = definitions
            .Select(definition => new
            {
                Definition = definition,
                Score = definition.DetectionTerms.Sum(term =>
                    CountOccurrences(transcript, term) * Math.Max(1, term.Length))
            })
            .OrderByDescending(item => item.Score)
            .ThenBy(item => item.Definition.Template)
            .ToArray();

        return scores[0].Score > 0
            ? scores[0].Definition.Template
            : DocumentTemplate.General;
    }

    private static int FindCurrentStage(string transcript, IReadOnlyList<FrameworkStage> stages)
    {
        if (string.IsNullOrWhiteSpace(transcript))
        {
            return -1;
        }

        var currentIndex = -1;
        var lastSignalEnd = -1;

        for (var index = 0; index < stages.Count; index++)
        {
            foreach (var keyword in stages[index].Keywords)
            {
                var position = transcript.LastIndexOf(keyword, StringComparison.OrdinalIgnoreCase);
                if (position < 0)
                {
                    continue;
                }

                var signalEnd = position + keyword.Length;
                if (signalEnd > lastSignalEnd)
                {
                    lastSignalEnd = signalEnd;
                    currentIndex = index;
                }
            }
        }

        return currentIndex;
    }

    private static int CountOccurrences(string text, string term)
    {
        var count = 0;
        var offset = 0;
        while ((offset = text.IndexOf(term, offset, StringComparison.OrdinalIgnoreCase)) >= 0)
        {
            count++;
            offset += term.Length;
        }

        return count;
    }

    private static FrameworkDefinition GetDefinition(DocumentTemplate template)
    {
        return template switch
        {
            DocumentTemplate.ProjectManagement => ProjectManagement,
            DocumentTemplate.Prd => Prd,
            DocumentTemplate.WeeklyReport => WeeklyReport,
            DocumentTemplate.Solution => Solution,
            _ => General
        };
    }

    private sealed record FrameworkDefinition(
        DocumentTemplate Template,
        string DisplayName,
        IReadOnlyList<FrameworkStage> Stages,
        IReadOnlyList<string> DetectionTerms);

    private sealed record FrameworkStage(
        string Title,
        string Prompt,
        string Direction,
        IReadOnlyList<string> Keywords);
}

public sealed record DocumentFrameworkResult(
    DocumentTemplate Template,
    string DisplayName,
    WritingGuidance Guidance);

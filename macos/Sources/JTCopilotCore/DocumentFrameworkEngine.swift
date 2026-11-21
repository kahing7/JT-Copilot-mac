import Foundation

public struct DocumentFrameworkResult: Equatable, Sendable {
    public let template: DocumentTemplate
    public let displayName: String
    public let guidance: WritingGuidance

    public init(template: DocumentTemplate, displayName: String, guidance: WritingGuidance) {
        self.template = template
        self.displayName = displayName
        self.guidance = guidance
    }
}

/// 本地文档模板引擎：不依赖网络，实时推进“下一句”。
public final class DocumentFrameworkEngine {
    private struct FrameworkStage {
        let title: String
        let prompt: String
        let direction: String
        let keywords: [String]
    }

    private struct FrameworkDefinition {
        let template: DocumentTemplate
        let displayName: String
        let stages: [FrameworkStage]
        let detectionTerms: [String]
    }

    private static let projectManagement = FrameworkDefinition(
        template: .projectManagement,
        displayName: "项目管理文档",
        stages: [
            FrameworkStage(title: "项目背景", prompt: "先交代一下项目背景", direction: "补充项目起因、当前现状和需要解决的问题", keywords: ["项目背景", "背景", "起因", "当前现状", "当前情况", "问题"]),
            FrameworkStage(title: "业务目标", prompt: "接下来对齐项目的业务目标", direction: "说明目标、预期收益和衡量指标", keywords: ["业务目标", "项目目标", "目标", "收益", "价值", "指标"]),
            FrameworkStage(title: "项目范围", prompt: "说明项目范围和边界", direction: "明确包含事项、不包含事项和关键约束", keywords: ["项目范围", "范围", "边界", "不包含", "包含"]),
            FrameworkStage(title: "规划与里程碑", prompt: "介绍项目规划和关键里程碑", direction: "写清阶段、时间节点和关键里程碑", keywords: ["项目规划", "规划", "里程碑", "排期", "计划", "阶段"]),
            FrameworkStage(title: "组织与职责", prompt: "说明干系人与职责", direction: "列出关键角色、负责人和决策机制", keywords: ["项目组织", "职责", "干系人", "负责人", "决策人"]),
            FrameworkStage(title: "风险与依赖", prompt: "补充风险和依赖", direction: "说明风险影响、应对方式和外部依赖", keywords: ["风险", "依赖", "约束", "应对"]),
            FrameworkStage(title: "交付物与验收标准", prompt: "给出交付物和验收标准", direction: "写清交付成果、完成定义和验收方式", keywords: ["交付物", "交付成果", "验收", "完成定义"])
        ],
        detectionTerms: ["项目管理", "项目背景", "业务目标", "项目范围", "里程碑", "干系人", "风险", "依赖", "交付物", "验收标准"]
    )

    private static let prd = FrameworkDefinition(
        template: .prd,
        displayName: "产品需求文档",
        stages: [
            FrameworkStage(title: "背景与问题", prompt: "先说明需求背景和要解决的问题", direction: "交代用户痛点、现状和触发原因", keywords: ["需求背景", "背景", "问题", "痛点", "现状"]),
            FrameworkStage(title: "用户与场景", prompt: "说明目标用户和使用场景", direction: "写清用户角色、任务和高频场景", keywords: ["用户", "场景", "角色", "人群"]),
            FrameworkStage(title: "目标与指标", prompt: "明确产品目标和成功指标", direction: "给出可衡量的业务或体验指标", keywords: ["产品目标", "目标", "指标", "成功标准"]),
            FrameworkStage(title: "功能范围", prompt: "说明功能范围和优先级", direction: "区分本期必须、可选和暂不实现的内容", keywords: ["功能范围", "功能", "优先级", "范围"]),
            FrameworkStage(title: "流程与交互", prompt: "描述核心流程和关键交互", direction: "按用户任务顺序讲清主流程和异常分支", keywords: ["流程", "交互", "路径", "异常"]),
            FrameworkStage(title: "需求细节", prompt: "补充规则、数据和异常处理", direction: "说明校验、权限、状态和边界条件", keywords: ["规则", "数据", "权限", "状态", "边界"]),
            FrameworkStage(title: "验收标准", prompt: "给出验收标准和完成定义", direction: "列出可测试的验收条件和结果", keywords: ["验收", "完成定义", "测试"])
        ],
        detectionTerms: ["PRD", "产品需求", "用户故事", "需求文档", "功能需求"]
    )

    private static let weeklyReport = FrameworkDefinition(
        template: .weeklyReport,
        displayName: "工作周报",
        stages: [
            FrameworkStage(title: "本周进展", prompt: "先总结本周完成的关键进展", direction: "用结果和影响说明完成情况", keywords: ["本周进展", "本周完成", "进展", "完成"]),
            FrameworkStage(title: "关键结果", prompt: "补充关键结果和业务价值", direction: "给出数据、产出和实际影响", keywords: ["关键结果", "结果", "价值", "数据"]),
            FrameworkStage(title: "问题与风险", prompt: "说明当前问题和风险", direction: "写清阻塞点、影响和需要的支持", keywords: ["问题", "风险", "阻塞", "困难"]),
            FrameworkStage(title: "下周计划", prompt: "列出下周计划和优先事项", direction: "按优先级说明目标和预期产出", keywords: ["下周计划", "下周", "计划", "优先"]),
            FrameworkStage(title: "协作与依赖", prompt: "补充需要协同的事项和依赖", direction: "明确责任人、时间和需要的决策", keywords: ["协作", "依赖", "支持", "协同"])
        ],
        detectionTerms: ["周报", "本周", "下周", "本周进展", "工作汇报"]
    )

    private static let solution = FrameworkDefinition(
        template: .solution,
        displayName: "方案文档",
        stages: [
            FrameworkStage(title: "背景与现状", prompt: "先说明方案背景和当前现状", direction: "交代问题、机会和已有条件", keywords: ["背景", "现状", "问题", "机会"]),
            FrameworkStage(title: "目标与约束", prompt: "明确方案目标和关键约束", direction: "写清成功标准、时间、成本和边界", keywords: ["目标", "约束", "成功标准", "边界"]),
            FrameworkStage(title: "总体方案", prompt: "介绍总体方案和处理思路", direction: "先给整体路径，再展开关键模块", keywords: ["总体方案", "整体方案", "思路", "方案"]),
            FrameworkStage(title: "关键设计", prompt: "说明关键设计和技术取舍", direction: "解释核心机制、接口和替代方案", keywords: ["关键设计", "设计", "架构", "接口", "取舍"]),
            FrameworkStage(title: "实施计划", prompt: "给出实施计划和资源安排", direction: "说明阶段、负责人和依赖关系", keywords: ["实施计划", "实施", "计划", "资源"]),
            FrameworkStage(title: "风险与备选", prompt: "补充风险、依赖和备选方案", direction: "给出触发条件、应对措施和回退路径", keywords: ["风险", "备选", "回退", "依赖"]),
            FrameworkStage(title: "验收标准", prompt: "最后说明验收和上线标准", direction: "写清验证方法、完成定义和上线条件", keywords: ["验收", "上线", "完成定义"])
        ],
        detectionTerms: ["方案", "总体设计", "技术方案", "架构", "实施计划"]
    )

    private static let general = FrameworkDefinition(
        template: .general,
        displayName: "通用写作",
        stages: [
            FrameworkStage(title: "主题与背景", prompt: "先交代主题和背景", direction: "说明为什么写、面向谁和解决什么问题", keywords: ["主题", "背景", "问题"]),
            FrameworkStage(title: "核心观点", prompt: "先给出核心观点或结论", direction: "把最关键的信息放在前面", keywords: ["观点", "结论", "核心"]),
            FrameworkStage(title: "结构展开", prompt: "按逻辑顺序展开主要内容", direction: "使用并列、递进或问题解决结构", keywords: ["第一", "第二", "首先", "其次", "然后"]),
            FrameworkStage(title: "依据与细节", prompt: "补充事实、数据和例子", direction: "用证据支撑观点并说明边界", keywords: ["数据", "案例", "例如", "依据"]),
            FrameworkStage(title: "总结与行动", prompt: "最后总结结论和下一步行动", direction: "写清结论、行动项和责任人", keywords: ["总结", "下一步", "行动"])
        ],
        detectionTerms: []
    )

    public init() {}

    public func build(transcript: String, template: DocumentTemplate) -> DocumentFrameworkResult {
        let resolvedTemplate = template == .auto ? detectTemplate(transcript) : template
        let definition = definition(for: resolvedTemplate)
        let currentIndex = findCurrentStage(transcript: transcript, stages: definition.stages)
        let nextIndex = currentIndex < 0
            ? 0
            : min(currentIndex + 1, definition.stages.count - 1)
        let nextStage = definition.stages[nextIndex]

        let framework = definition.stages.enumerated().map { index, stage -> String in
            if index < currentIndex {
                return "\(index + 1). \(stage.title)（已涉及）"
            }
            if index == currentIndex {
                return "\(index + 1). \(stage.title)（当前）"
            }
            return "\(index + 1). \(stage.title)"
        }

        let nextSentence = currentIndex == definition.stages.count - 1
            ? "最后收束全文，检查交付物和验收标准"
            : nextStage.prompt

        var directions = [nextStage.prompt, nextStage.direction]
        if currentIndex >= 0 {
            directions.insert("当前结构：\(definition.stages[currentIndex].title)", at: 0)
        }

        return DocumentFrameworkResult(
            template: definition.template,
            displayName: definition.displayName,
            guidance: WritingGuidance(
                framework: framework,
                nextSentence: nextSentence,
                directions: directions,
                missingPoints: [nextStage.direction],
                template: definition.template
            )
        )
    }

    public func detectTemplate(_ transcript: String) -> DocumentTemplate {
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .general
        }

        let definitions = [
            DocumentFrameworkEngine.projectManagement,
            DocumentFrameworkEngine.prd,
            DocumentFrameworkEngine.weeklyReport,
            DocumentFrameworkEngine.solution
        ]

        let scores = definitions.map { definition -> (definition: FrameworkDefinition, score: Int) in
            let score = definition.detectionTerms.reduce(0) { partial, term in
                partial + countOccurrences(of: term, in: transcript) * max(1, term.count)
            }
            return (definition, score)
        }

        let best = scores.sorted {
            if $0.score != $1.score {
                return $0.score > $1.score
            }
            return $0.definition.template.rawValue < $1.definition.template.rawValue
        }.first

        guard let best, best.score > 0 else {
            return .general
        }

        return best.definition.template
    }

    private func findCurrentStage(transcript: String, stages: [FrameworkStage]) -> Int {
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return -1
        }

        let source = transcript as NSString
        var currentIndex = -1
        var lastSignalEnd = -1

        for (index, stage) in stages.enumerated() {
            for keyword in stage.keywords {
                let range = source.range(of: keyword, options: [.caseInsensitive, .backwards])
                guard range.location != NSNotFound else { continue }

                let signalEnd = NSMaxRange(range)
                if signalEnd > lastSignalEnd {
                    lastSignalEnd = signalEnd
                    currentIndex = index
                }
            }
        }

        return currentIndex
    }

    private func countOccurrences(of term: String, in text: String) -> Int {
        guard !term.isEmpty else { return 0 }

        let source = text as NSString
        var count = 0
        var offset = 0

        while offset < source.length {
            let range = source.range(
                of: term,
                options: [.caseInsensitive],
                range: NSRange(location: offset, length: source.length - offset)
            )
            guard range.location != NSNotFound else { break }

            count += 1
            offset = NSMaxRange(range)
        }

        return count
    }

    private func definition(for template: DocumentTemplate) -> FrameworkDefinition {
        switch template {
        case .projectManagement:
            return DocumentFrameworkEngine.projectManagement
        case .prd:
            return DocumentFrameworkEngine.prd
        case .weeklyReport:
            return DocumentFrameworkEngine.weeklyReport
        case .solution:
            return DocumentFrameworkEngine.solution
        default:
            return DocumentFrameworkEngine.general
        }
    }
}

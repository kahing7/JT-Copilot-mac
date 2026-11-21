import XCTest
@testable import JTCopilotCore

final class DocumentFrameworkEngineTests: XCTestCase {
    private let engine = DocumentFrameworkEngine()

    func testDetectTemplateRecognizesProjectManagementContext() {
        let template = engine.detectTemplate("我现在准备写一篇项目管理的文档，需要说明项目背景、业务目标和验收标准")
        XCTAssertEqual(DocumentTemplate.projectManagement, template)
    }

    func testBuildAdvancesProjectManagementPrompt() {
        let cases: [(String, String)] = [
            ("我现在准备写一篇项目管理的文档", "先交代一下项目背景"),
            ("先交代一下项目背景，当前存在交付延期", "接下来对齐项目的业务目标"),
            ("业务目标是把交付准时率提升到百分之九十五", "说明项目范围和边界"),
            ("项目范围包括三个业务团队", "介绍项目规划和关键里程碑"),
            ("规划分为两个阶段，十一月完成里程碑一", "说明干系人与职责"),
            ("干系人包括产品和研发团队，由项目经理负责", "补充风险和依赖"),
            ("风险主要是供应商依赖，需要提前准备备选", "给出交付物和验收标准")
        ]

        for (transcript, expected) in cases {
            let result = engine.build(transcript: transcript, template: .auto)
            XCTAssertEqual(DocumentTemplate.projectManagement, result.template)
            XCTAssertEqual(expected, result.guidance.nextSentence, transcript)
        }
    }

    func testManualTemplateDoesNotRequireAutoDetection() {
        let result = engine.build(transcript: "先写需求背景", template: .prd)
        XCTAssertEqual(DocumentTemplate.prd, result.template)
        XCTAssertEqual("说明目标用户和使用场景", result.guidance.nextSentence)
    }
}

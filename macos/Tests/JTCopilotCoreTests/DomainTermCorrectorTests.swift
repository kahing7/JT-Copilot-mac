import XCTest
@testable import JTCopilotCore

final class DomainTermCorrectorTests: XCTestCase {
    private let corrector = DomainTermCorrector()
    private let defaultVocabulary = AppSettings.defaultCustomVocabulary

    func testRepairsKnownBusinessTerms() {
        XCTAssertEqual(
            "我们的CRM系统支持积分兑礼",
            corrector.correct("我们的新奥尔良系统支持积分队里区", customVocabulary: defaultVocabulary)
        )
        XCTAssertEqual(
            "OK，这个功能可以",
            corrector.correct("欧克，这个功能可以", customVocabulary: defaultVocabulary)
        )
        XCTAssertEqual(
            "CRM OK PRD API KPI",
            corrector.correct("crm ok prd api kpi", customVocabulary: defaultVocabulary)
        )
    }

    func testCustomAliasOverridesBuiltInAlias() {
        let vocabulary = "客户关系管理=crm,西阿艾姆"
        XCTAssertEqual(
            "客户关系管理 和 客户关系管理",
            corrector.correct("crm 和 西阿艾姆", customVocabulary: vocabulary)
        )
    }

    func testDoesNotTurnLegitimateChineseQuestionIntoOk() {
        XCTAssertEqual(
            "这样可以吗",
            corrector.correct("这样可以吗", customVocabulary: defaultVocabulary)
        )
        XCTAssertEqual(
            "支持积分兑礼，OK吗",
            corrector.correct("支持积分兑礼，可以吗", customVocabulary: defaultVocabulary)
        )
    }

    func testHotwordsIncludeCustomStandardsBeforeDefaults() {
        let hotwords = corrector.hotwords("积分兑礼=积分对礼\n客户关系管理=CRM")
        XCTAssertTrue(hotwords.contains("积分兑礼"))
        XCTAssertTrue(hotwords.contains("客户关系管理"))
        XCTAssertTrue(hotwords.contains("项目管理"))
    }
}

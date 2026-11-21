import XCTest
@testable import JTCopilotCore

final class TranscriptMergerTests: XCTestCase {
    func testOverlapRemovesRepeatedBoundaryText() {
        let existing = "我们先介绍项目背景"
        let merged = TranscriptMerger.append(existing: existing, incoming: "项目背景，然后说明业务目标")
        XCTAssertEqual("我们先介绍项目背景然后说明业务目标", merged.text)
        XCTAssertEqual("然后说明业务目标", merged.appended)
    }

    func testAsciiWordsGetSpaceSeparator() {
        let merged = TranscriptMerger.append(existing: "use CRM", incoming: "OK")
        XCTAssertEqual("use CRM OK", merged.text)
    }

    func testChineseDoesNotGetSpaceSeparator() {
        let merged = TranscriptMerger.append(existing: "项目背景", incoming: "业务目标")
        XCTAssertEqual("项目背景业务目标", merged.text)
    }

    func testNormalizeSpeechTextRemovesCjkSpaces() {
        XCTAssertEqual("项目背景", TranscriptMerger.normalizeSpeechText(" 项目 背景 "))
    }
}

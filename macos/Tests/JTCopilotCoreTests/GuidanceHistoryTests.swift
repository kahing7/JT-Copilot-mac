import XCTest
@testable import JTCopilotCore

final class GuidanceHistoryTests: XCTestCase {
    func testAppendingKeepsPreviousGuidance() {
        let history = GuidanceHistory.appending("先说目标用户", to: [])

        XCTAssertEqual(["先说目标用户"], history)
    }

    func testAppendingDoesNotDuplicateLastGuidance() {
        let history = GuidanceHistory.appending(
            "  先说目标用户  ",
            to: ["先说目标用户"]
        )

        XCTAssertEqual(["先说目标用户"], history)
    }

    func testAppendingKeepsMostRecentEntriesWithinLimit() {
        let history = GuidanceHistory.appending(
            "第四句",
            to: ["第一句", "第二句", "第三句"],
            limit: 2
        )

        XCTAssertEqual(["第三句", "第四句"], history)
    }

    func testVisibleHistoryHidesCurrentDuplicate() {
        let visible = GuidanceHistory.visibleHistory(
            ["上一句", "当前句"],
            current: "当前句"
        )

        XCTAssertEqual(["上一句"], visible)
    }

    func testVisibleHistoryKeepsItemsWhenCurrentIsStreaming() {
        let visible = GuidanceHistory.visibleHistory(
            ["上一句", "当前句"],
            current: "当前句正在生成"
        )

        XCTAssertEqual(["上一句", "当前句"], visible)
    }
}

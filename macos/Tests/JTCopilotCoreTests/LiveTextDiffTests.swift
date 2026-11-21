import XCTest
@testable import JTCopilotCore

final class LiveTextDiffTests: XCTestCase {
    func testProducesMinimalEdits() {
        let cases: [(String, String, Int, Int, Int)] = [
            ("我", "我想", 1, 0, 1),
            ("我想介绍", "我想介绍一下", 4, 0, 2),
            ("她有三个能力", "它有三个能力", 0, 6, 6),
            ("功能介绍完了", "功能介绍", 4, 2, 0)
        ]

        for (previous, current, prefix, deletion, insertion) in cases {
            let diff = LiveTextDiffCalculator.calculate(previous: previous, current: current)
            XCTAssertEqual(prefix, diff.commonPrefixLength, "prefix for \(previous) -> \(current)")
            XCTAssertEqual(deletion, diff.charactersToDelete, "delete for \(previous) -> \(current)")
            XCTAssertEqual(insertion, diff.charactersToInsert, "insert for \(previous) -> \(current)")
        }
    }

    func testBackspaceCountUsesGraphemeClusters() {
        let diff = LiveTextDiffCalculator.calculate(previous: "a👨‍👩‍👧", current: "a")
        XCTAssertEqual(1, diff.backspaceCount)
        XCTAssertEqual("👨‍👩‍👧", diff.textToDelete)
    }
}

import XCTest
@testable import JTCopilotCore

final class SessionTranscriptAccumulatorTests: XCTestCase {
    func testKeepsCommittedTextWhenAppleSpeechRestarts() {
        var accumulator = SessionTranscriptAccumulator()

        accumulator.updateHypothesis("我们今天开会")
        accumulator.commitCurrent()
        accumulator.updateHypothesis("我们今天开会")
        accumulator.updateHypothesis("讨论明年的预算")

        XCTAssertEqual("我们今天开会讨论明年的预算", accumulator.fullText)
    }

    func testStripsCumulativeAppleSpeechPrefix() {
        var accumulator = SessionTranscriptAccumulator()

        accumulator.updateHypothesis("会议主题是预算规划")
        accumulator.commitCurrent()
        accumulator.updateHypothesis("会议主题是预算规划讨论各部门需求")

        XCTAssertEqual("会议主题是预算规划讨论各部门需求", accumulator.fullText)
    }

    func testCommitDoesNotLoseEarlierSegments() {
        var accumulator = SessionTranscriptAccumulator()

        for sentence in ["第一句内容", "第二句内容", "第三句内容"] {
            accumulator.updateHypothesis(sentence)
            accumulator.commitCurrent()
        }

        XCTAssertEqual("第一句内容第二句内容第三句内容", accumulator.fullText)
    }
}

import XCTest
@testable import PushupTracker

final class PushUpCounterTests: XCTestCase {
    func testTwoCompleteRepetitionsCountOnceEach() {
        var counter = PushUpCounter()
        let increments = feed([155, 90, 156, 159, 98, 160], into: &counter)
        XCTAssertEqual(increments, [false, false, true, false, false, true])
    }

    func testStartingAtBottomAndPartialMotionDoNotCount() {
        var counter = PushUpCounter()
        XCTAssertEqual(feed([90, 156, 125, 130, 155], into: &counter), Array(repeating: false, count: 5))
    }

    func testLongTrackingLossInvalidatesAnUnfinishedRep() {
        var counter = PushUpCounter()
        _ = feed([156, 90], into: &counter)
        XCTAssertFalse(counter.update(angle: nil, at: 1.0))
        XCTAssertFalse(counter.update(angle: 157, at: 1.2))
        XCTAssertFalse(counter.update(angle: 158, at: 1.31))
    }

    func testShortTrackingLossClearsAnUnconfirmedPosition() {
        var counter = PushUpCounter()
        _ = counter.update(angle: 156, at: 0)
        _ = counter.update(angle: nil, at: 0.05)
        _ = counter.update(angle: 156, at: 0.12)
        XCTAssertEqual(counter.phase, .waitingForTop)
    }

    func testOneNoisyFrameDoesNotConfirmABottom() {
        var counter = PushUpCounter()
        _ = feed([156], into: &counter)
        _ = counter.update(angle: 90, at: 0.24)
        XCTAssertFalse(counter.update(angle: 157, at: 0.36))
        XCTAssertFalse(counter.update(angle: 157, at: 0.46))
    }

    private func feed(_ angles: [Double], into counter: inout PushUpCounter) -> [Bool] {
        angles.enumerated().map { index, angle in
            let start = Double(index) * 0.24
            _ = counter.update(angle: angle, at: start)
            return counter.update(angle: angle, at: start + 0.1)
        }
    }
}

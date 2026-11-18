import XCTest
@testable import PushupTracker

final class FrontPushUpCounterTests: XCTestCase {
    func testCountsTwoPushUpsFromHeadMovementAlone() {
        let heights: [CGFloat?] = [0.70, 0.70, 0.70, 0.63, 0.52, 0.51, 0.61, 0.69, 0.70,
                       0.70, 0.60, 0.51, 0.52, 0.67, 0.70, 0.70]
        XCTAssertEqual(count(heights), 2)
    }

    func testCountsWhenTheHeadIsSmallerInFrame() {
        XCTAssertEqual(count([0.56, 0.56, 0.56, 0.54, 0.52, 0.52, 0.55, 0.56, 0.56], width: 0.042), 1)
    }

    func testIgnoresSmallHeadMovementsAndSingleFrameNoise() {
        XCTAssertEqual(count([0.70, 0.70, 0.70, 0.67, 0.66, 0.67, 0.70, 0.50, 0.70, 0.70]), 0)
    }

    func testPreservesConfirmedDescentAcrossABriefLoss() {
        XCTAssertEqual(count([0.70, 0.70, 0.70, 0.56, 0.53, nil, nil, nil, 0.68, 0.70, 0.70]), 1)
    }

    func testCanFinishADescentAlreadyNearTheBottomWhenTrackingDrops() {
        XCTAssertEqual(count([0.70, 0.70, 0.70, 0.65, 0.636, nil, nil, nil, 0.70, 0.70]), 1)
    }

    func testTrackingLossByItselfDoesNotCount() {
        XCTAssertEqual(count([0.70, 0.70, 0.70, nil, nil, nil, 0.70, 0.70, 0.70]), 0)
    }

    func testProlongedLossDiscardsAnUnfinishedRep() {
        let lost = Array<CGFloat?>(repeating: nil, count: 15)
        XCTAssertEqual(count([0.70, 0.70, 0.70, 0.52, 0.52] + lost + [0.70, 0.70, 0.70]), 0)
    }

    func testMovingIntoTheStartingPositionDoesNotCount() {
        XCTAssertEqual(count([0.83, 0.76, 0.70, 0.70, 0.70, 0.70]), 0)
    }

    func testLateralMovementStartsANewCalibration() {
        var counter = FrontPushUpCounter()
        let points = [
            (0.35, 0.70), (0.35, 0.70), (0.35, 0.70), (0.35, 0.50), (0.35, 0.50),
            (0.61, 0.70), (0.61, 0.70), (0.61, 0.70)
        ]
        let results = points.enumerated().map { index, point in
            counter.update(.init(x: point.0, y: point.1, width: 0.12), at: Double(index) * 0.13)
        }
        XCTAssertFalse(results.contains(true))
    }

    private func count(_ heights: [CGFloat?], width: CGFloat = 0.12) -> Int {
        var counter = FrontPushUpCounter()
        return heights.enumerated().filter { index, height in
            let sample = height.map { FrontPushUpCounter.Head(x: 0.35, y: $0, width: width) }
            return counter.update(sample, at: Double(index) * 0.13)
        }.count
    }
}

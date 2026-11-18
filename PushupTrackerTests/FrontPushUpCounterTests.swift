import CoreGraphics
import XCTest
@testable import PushupTracker

final class FrontPushUpCounterTests: XCTestCase {
    func testCountsAFullRepWithOnlyOneArmInFrame() {
        XCTAssertEqual(count([top, top, bent, bent, top, top, top]), 1)
    }

    func testCountsWhenTheBentArmLooksStraightFromTheFront() {
        let foreshortened = frame(shoulder: 105, elbow: CGPoint(x: 80, y: 85))
        XCTAssertEqual(count([top, top, foreshortened, foreshortened, top, top]), 1)
    }

    func testIgnoresPartialBendsAndASingleNoisyFrame() {
        let partial = frame(shoulder: 125, elbow: CGPoint(x: 90, y: 95))
        XCTAssertEqual(count([top, top, partial, partial, top, bent, top, top]), 0)
    }

    func testCountsTwoArmsOnceEvenWhenTheyStraightenAtDifferentTimes() {
        XCTAssertEqual(count([top, top, bent, bent, top, top, top, top],
                             other: [top, top, bent, bent, bent, bent, top, top]), 1)
    }

    func testCanUseTheOtherArmForTheNextRep() {
        XCTAssertEqual(count([top, top, bent, bent, top, top, nil, nil, nil, nil, nil, nil],
                             other: [nil, nil, nil, nil, nil, nil, top, top, bent, bent, top, top]), 2)
    }

    func testDoesNotCombineTheBendFromOneArmWithTheReturnFromAnother() {
        XCTAssertEqual(count([top, top, bent, bent, nil, nil],
                             other: [nil, nil, nil, nil, top, top]), 0)
    }

    func testContinuesThroughABriefLossAtTheBottom() {
        XCTAssertEqual(count([top, top, bent, nil, bent, nil, top, top]), 1)
    }

    func testTrackingTheShoulderAndWristCanConfirmFlexionWithoutAnElbow() {
        let inFlexion = frame(shoulder: 105, elbow: CGPoint(x: 110, y: 95))
        let tracked = PoseGeometry.Frame(imageSize: inFlexion.imageSize,
                                        points: inFlexion.points.filter { $0.key != .leftElbow })
        XCTAssertEqual(count([top, top, tracked, tracked, nil, nil, top, top]), 1)
        XCTAssertEqual(count([tracked, tracked, nil, top, top]), 0)
    }

    func testLossAloneDoesNotCount() {
        XCTAssertEqual(count([top, top, nil, nil, top, top]), 0)
    }

    func testDoesNotCountWhenTheWristMovesAcrossTheFrame() {
        let moved = frame(shoulder: 110, elbow: CGPoint(x: 160, y: 95), wristX: 135)
        XCTAssertEqual(count([top, top, moved, moved, top, top]), 0)
    }

    func testRetainsAConfirmedBendDuringSeveralSecondsWithoutASkeleton() {
        let loss = Array<PoseGeometry.Frame?>(repeating: nil, count: 35)
        XCTAssertEqual(count([top, top, bent, bent] + loss + [top, top, top, top]), 1)
    }

    func testRetainsExtensionAndMeasuredFlexionAcrossSeparateGaps() {
        let loss = Array<PoseGeometry.Frame?>(repeating: nil, count: 18)
        let poses = [top, top] + loss + [bent] + loss + [bent] + loss + [top, top]
        XCTAssertEqual(count(poses), 1)
    }

    func testContinuesCountingAfterReturningFromATrackingGap() {
        let loss = Array<PoseGeometry.Frame?>(repeating: nil, count: 18)
        XCTAssertEqual(count([top, top, bent, bent] + loss + [top, top, bent, bent, top, top]), 2)
    }

    func testAStableNewHandPlacementCancelsTheOldRepAndStartsANewOne() {
        let newTop = frame(shoulder: 150, elbow: CGPoint(x: 135, y: 110), wristX: 135)
        let newBent = frame(shoulder: 105, elbow: CGPoint(x: 165, y: 95), wristX: 135)
        let loss = Array<PoseGeometry.Frame?>(repeating: nil, count: 14)
        let beforeMoving = [top, top, bent, bent] + loss
        XCTAssertEqual(count(beforeMoving + [newTop, newTop, top, top]), 0)
        XCTAssertEqual(count(beforeMoving + [newTop, newTop, newBent, newBent, newTop, newTop]), 1)
    }

    func testAShortWristGlitchCannotClearAConfirmedBend() {
        let glitch = frame(shoulder: 150, elbow: CGPoint(x: 135, y: 110), wristX: 135)
        XCTAssertEqual(count([top, top, bent, bent, glitch, top, top]), 1)
    }

    private var top: PoseGeometry.Frame {
        frame(shoulder: 150, elbow: CGPoint(x: 80, y: 110))
    }

    private var bent: PoseGeometry.Frame {
        frame(shoulder: 105, elbow: CGPoint(x: 110, y: 95))
    }

    private func frame(shoulder: CGFloat, elbow: CGPoint, wristX: CGFloat = 80) -> PoseGeometry.Frame {
        let size = CGSize(width: 240, height: 320)
        func normalized(_ point: CGPoint) -> CGPoint {
            CGPoint(x: point.x / size.width, y: point.y / size.height)
        }
        return PoseGeometry.Frame(imageSize: size, points: [
            .leftShoulder: normalized(CGPoint(x: wristX, y: shoulder)),
            .leftElbow: normalized(elbow),
            .leftWrist: normalized(CGPoint(x: wristX, y: 70))
        ])
    }

    private func count(_ frames: [PoseGeometry.Frame?], other: [PoseGeometry.Frame?] = []) -> Int {
        var counter = FrontPushUpCounter()
        return frames.enumerated().filter { index, frame in
            let otherArm = other.indices.contains(index) ? other[index]?.leftArm : nil
            return counter.update(left: frame?.leftArm, right: otherArm, at: Double(index) * 0.10)
        }.count
    }
}

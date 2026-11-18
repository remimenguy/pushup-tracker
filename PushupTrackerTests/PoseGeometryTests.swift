import CoreGraphics
import XCTest
@testable import PushupTracker

final class PoseGeometryTests: XCTestCase {
    func testMeasuresAnExtendedArmAndABentArm() throws {
        let wrist = CGPoint(x: 100, y: 40)
        let hip = CGPoint(x: 220, y: 100)
        let straight = try XCTUnwrap(PoseGeometry.elbowAngle(
            shoulder: CGPoint(x: 100, y: 120), elbow: CGPoint(x: 100, y: 80), wrist: wrist, hip: hip
        ))
        let bent = try XCTUnwrap(PoseGeometry.elbowAngle(
            shoulder: CGPoint(x: 68, y: 74), elbow: CGPoint(x: 100, y: 74), wrist: wrist,
            hip: CGPoint(x: 210, y: 65)
        ))
        XCTAssertEqual(straight, 180, accuracy: 0.01)
        XCTAssertEqual(bent, 90, accuracy: 0.01)
    }

    func testRejectsAnUprightPersonAndDegenerateArm() {
        XCTAssertNil(PoseGeometry.elbowAngle(
            shoulder: CGPoint(x: 100, y: 230), elbow: CGPoint(x: 100, y: 150),
            wrist: CGPoint(x: 100, y: 40), hip: CGPoint(x: 110, y: 120)
        ))
        XCTAssertNil(PoseGeometry.elbowAngle(
            shoulder: CGPoint(x: 100, y: 120), elbow: CGPoint(x: 100, y: 120),
            wrist: CGPoint(x: 100, y: 40), hip: CGPoint(x: 220, y: 100)
        ))
    }

    func testCountsAFrontalRepEvenWhenBentElbowsProjectAsStraight() {
        let top = frame(shoulderY: 185)
        let bottom = frame(shoulderY: 128)
        let shallow = frame(shoulderY: 163)

        var counter = FrontPushUpCounter()
        let poses = [bottom, top, shallow, top, bottom, top, top]
        let increments = poses.enumerated().map { index, pose in
            let time = Double(index) * 0.25
            _ = update(pose, at: time, into: &counter)
            return update(pose, at: time + 0.11, into: &counter)
        }
        XCTAssertEqual(increments, [false, false, false, false, false, true, false])
    }

    func testFrontalTrackingReportsVisibleLimbsAndRejectsAnUprightPose() {
        let valid = frame(shoulderY: 185)
        XCTAssertEqual(valid.visibleArms, 2)
        XCTAssertEqual(valid.visibleLegs, 2)
        XCTAssertNotNil(valid.frontMeasurement)

        let oneLeg = frame(shoulderY: 185, includeRightLeg: false)
        XCTAssertEqual(oneLeg.visibleLegs, 1)
        XCTAssertNotNil(oneLeg.frontMeasurement)

        let noLegs = frame(shoulderY: 185, legY: nil, includeRightLeg: false)
        XCTAssertEqual(noLegs.visibleLegs, 0)
        XCTAssertNil(noLegs.frontMeasurement)
        XCTAssertNil(frame(shoulderY: 185, legY: 10).frontMeasurement)
    }

    func testFrontalRepIsDiscardedAfterProlongedTrackingLoss() {
        let top = frame(shoulderY: 185)
        let bottom = frame(shoulderY: 128)
        let hidden = PoseGeometry.Frame(imageSize: top.imageSize, points: [:])
        var counter = FrontPushUpCounter()

        XCTAssertFalse(update(top, at: 0, into: &counter))
        XCTAssertFalse(update(top, at: 0.12, into: &counter))
        XCTAssertFalse(update(bottom, at: 0.25, into: &counter))
        XCTAssertFalse(update(bottom, at: 0.37, into: &counter))
        XCTAssertFalse(update(hidden, at: 1, into: &counter))
        XCTAssertFalse(update(hidden, at: 2, into: &counter))
        XCTAssertFalse(update(top, at: 2.1, into: &counter))
        XCTAssertFalse(update(top, at: 2.22, into: &counter))
    }

    func testCountsWhenTheBottomIsBrieflyOccludedAfterAVisibleDescent() {
        let top = frame(shoulderY: 185)
        let descent = frame(shoulderY: 158)
        let hidden = PoseGeometry.Frame(imageSize: top.imageSize, points: [:])
        var counter = FrontPushUpCounter()

        XCTAssertFalse(update(top, at: 0, into: &counter))
        XCTAssertFalse(update(top, at: 0.12, into: &counter))
        XCTAssertFalse(update(descent, at: 0.30, into: &counter))
        XCTAssertFalse(update(descent, at: 0.42, into: &counter))
        XCTAssertFalse(update(hidden, at: 0.50, into: &counter))
        XCTAssertFalse(update(hidden, at: 0.62, into: &counter))
        XCTAssertFalse(update(hidden, at: 0.95, into: &counter))
        XCTAssertFalse(update(top, at: 1.14, into: &counter))
        XCTAssertTrue(update(top, at: 1.26, into: &counter))
        XCTAssertFalse(update(top, at: 1.38, into: &counter))
    }

    func testCountsWhenOneShoulderIsVisibleAtTheBottom() {
        let top = frame(shoulderY: 185)
        let bottom = frame(shoulderY: 130)
        let partial = PoseGeometry.Frame(imageSize: bottom.imageSize,
                                         points: bottom.points.filter { $0.key == .leftShoulder })
        XCTAssertNil(partial.frontMeasurement)
        var counter = FrontPushUpCounter()

        XCTAssertFalse(update(top, at: 0, into: &counter))
        XCTAssertFalse(update(top, at: 0.12, into: &counter))
        XCTAssertFalse(update(partial, at: 0.30, into: &counter))
        XCTAssertFalse(update(partial, at: 0.42, into: &counter))
        XCTAssertFalse(update(top, at: 0.66, into: &counter))
        XCTAssertTrue(update(top, at: 0.78, into: &counter))
    }

    func testLossAtTheTopIsNotTreatedAsADescent() {
        let top = frame(shoulderY: 185)
        let hidden = PoseGeometry.Frame(imageSize: top.imageSize, points: [:])
        var counter = FrontPushUpCounter()

        XCTAssertFalse(update(top, at: 0, into: &counter))
        XCTAssertFalse(update(top, at: 0.12, into: &counter))
        XCTAssertFalse(update(hidden, at: 0.33, into: &counter))
        XCTAssertFalse(update(hidden, at: 0.67, into: &counter))
        XCTAssertFalse(update(top, at: 0.85, into: &counter))
        XCTAssertFalse(update(top, at: 0.97, into: &counter))
    }

    func testOverlayFitsAndFlipsVerticalCoordinates() {
        let rect = PoseGeometry.previewRect(image: CGSize(width: 480, height: 640),
                                            in: CGSize(width: 340, height: 300))
        XCTAssertEqual(rect, CGRect(x: 57.5, y: 0, width: 225, height: 300))
        XCTAssertEqual(PoseGeometry.previewPoint(CGPoint(x: 0.25, y: 0.75), in: rect),
                       CGPoint(x: 113.75, y: 75))
    }

    func testReturningWithHandsInANewPositionDoesNotFinishTheRep() {
        let top = frame(shoulderY: 185)
        let bottom = frame(shoulderY: 128)
        let moved = PoseGeometry.Frame(imageSize: top.imageSize, points: top.points.mapValues {
            CGPoint(x: $0.x + 0.13, y: $0.y)
        })
        var counter = FrontPushUpCounter()

        XCTAssertFalse(update(top, at: 0, into: &counter))
        XCTAssertFalse(update(top, at: 0.12, into: &counter))
        XCTAssertFalse(update(bottom, at: 0.30, into: &counter))
        XCTAssertFalse(update(bottom, at: 0.42, into: &counter))
        XCTAssertFalse(update(moved, at: 0.66, into: &counter))
        XCTAssertFalse(update(moved, at: 0.78, into: &counter))
    }

    @discardableResult
    private func update(_ frame: PoseGeometry.Frame, at time: TimeInterval, into counter: inout FrontPushUpCounter) -> Bool {
        counter.update(frame, measurement: frame.frontMeasurement, at: time)
    }

    private func frame(shoulderY: CGFloat, legY: CGFloat? = 145,
                       includeRightLeg: Bool = true) -> PoseGeometry.Frame {
        let size = CGSize(width: 320, height: 240)
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: x / size.width, y: y / size.height)
        }
        var points: [PoseGeometry.Joint: CGPoint] = [
            .leftShoulder: point(120, shoulderY), .rightShoulder: point(200, shoulderY),
            .leftElbow: point(120, (shoulderY + 100) / 2), .rightElbow: point(200, (shoulderY + 100) / 2),
            .leftWrist: point(120, 100), .rightWrist: point(200, 100)
        ]
        if let legY {
            points[.leftKnee] = point(145, legY)
            if includeRightLeg { points[.rightAnkle] = point(173, legY) }
        }
        return PoseGeometry.Frame(imageSize: size, points: points)
    }
}

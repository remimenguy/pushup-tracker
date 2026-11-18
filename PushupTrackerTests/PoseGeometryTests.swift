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

    func testCountsAFrontalRepEvenWhenBentElbowsProjectAsStraight() throws {
        let top = try XCTUnwrap(frame(shoulderY: 185).frontMeasurement)
        let bottom = try XCTUnwrap(frame(shoulderY: 128).frontMeasurement)
        let shallow = try XCTUnwrap(frame(shoulderY: 163).frontMeasurement)

        var counter = FrontPushUpCounter()
        let positions = [bottom, top, shallow, top, bottom, top, top]
        let increments = positions.enumerated().map { index, measurement in
            let time = Double(index) * 0.25
            _ = counter.update(measurement, at: time)
            return counter.update(measurement, at: time + 0.11)
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

    func testFrontalRepIsDiscardedWhenTheLegsLeaveTheFrame() throws {
        let top = try XCTUnwrap(frame(shoulderY: 185).frontMeasurement)
        let bottom = try XCTUnwrap(frame(shoulderY: 128).frontMeasurement)
        let missingLegs = frame(shoulderY: 170, legY: nil).frontMeasurement
        var counter = FrontPushUpCounter()

        XCTAssertFalse(counter.update(top, at: 0))
        XCTAssertFalse(counter.update(top, at: 0.12))
        XCTAssertFalse(counter.update(bottom, at: 0.25))
        XCTAssertFalse(counter.update(bottom, at: 0.37))
        XCTAssertFalse(counter.update(missingLegs, at: 0.9))
        XCTAssertFalse(counter.update(top, at: 1))
        XCTAssertFalse(counter.update(top, at: 1.12))
    }

    func testOverlayFitsAndFlipsVerticalCoordinates() {
        let rect = PoseGeometry.previewRect(image: CGSize(width: 480, height: 640),
                                            in: CGSize(width: 340, height: 300))
        XCTAssertEqual(rect, CGRect(x: 57.5, y: 0, width: 225, height: 300))
        XCTAssertEqual(PoseGeometry.previewPoint(CGPoint(x: 0.25, y: 0.75), in: rect),
                       CGPoint(x: 113.75, y: 75))
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

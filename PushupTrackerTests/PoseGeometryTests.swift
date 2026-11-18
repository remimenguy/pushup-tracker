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

    func testOverlayFitsAndFlipsVerticalCoordinates() {
        let rect = PoseGeometry.previewRect(image: CGSize(width: 480, height: 640),
                                            in: CGSize(width: 340, height: 300))
        XCTAssertEqual(rect, CGRect(x: 57.5, y: 0, width: 225, height: 300))
        XCTAssertEqual(PoseGeometry.previewPoint(CGPoint(x: 0.25, y: 0.75), in: rect),
                       CGPoint(x: 113.75, y: 75))
    }
}

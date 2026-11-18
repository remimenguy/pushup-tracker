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
}

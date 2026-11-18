import CoreGraphics
import Foundation

enum PoseGeometry {
    static func elbowAngle(shoulder: CGPoint, elbow: CGPoint, wrist: CGPoint, hip: CGPoint) -> Double? {
        let torsoWidth = abs(hip.x - shoulder.x)
        let torsoHeight = abs(hip.y - shoulder.y)
        guard torsoWidth > torsoHeight, shoulder.y > wrist.y else { return nil }

        let upperArm = CGVector(dx: shoulder.x - elbow.x, dy: shoulder.y - elbow.y)
        let forearm = CGVector(dx: wrist.x - elbow.x, dy: wrist.y - elbow.y)
        let length = hypot(upperArm.dx, upperArm.dy) * hypot(forearm.dx, forearm.dy)
        guard length > 1 else { return nil }
        let cosine = Double((upperArm.dx * forearm.dx + upperArm.dy * forearm.dy) / length)
        return acos(min(1, max(-1, cosine))) * 180 / .pi
    }
}

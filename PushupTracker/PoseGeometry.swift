import CoreGraphics
import Foundation

enum PoseGeometry {
    static func elbowAngle(shoulder: CGPoint, elbow: CGPoint, wrist: CGPoint, hip: CGPoint) -> Double? {
        let torsoWidth = abs(hip.x - shoulder.x)
        let torsoHeight = abs(hip.y - shoulder.y)
        guard torsoWidth > torsoHeight, shoulder.y > wrist.y else { return nil }

        return elbowAngle(shoulder: shoulder, elbow: elbow, wrist: wrist)
    }

    private static func elbowAngle(shoulder: CGPoint, elbow: CGPoint, wrist: CGPoint) -> Double? {
        let upperArm = CGVector(dx: shoulder.x - elbow.x, dy: shoulder.y - elbow.y)
        let forearm = CGVector(dx: wrist.x - elbow.x, dy: wrist.y - elbow.y)
        let length = hypot(upperArm.dx, upperArm.dy) * hypot(forearm.dx, forearm.dy)
        guard length > 1 else { return nil }
        let cosine = Double((upperArm.dx * forearm.dx + upperArm.dy * forearm.dy) / length)
        return acos(min(1, max(-1, cosine))) * 180 / .pi
    }

    enum Joint: Hashable, Sendable {
        case leftShoulder, leftElbow, leftWrist, leftHip, leftKnee, leftAnkle
        case rightShoulder, rightElbow, rightWrist, rightHip, rightKnee, rightAnkle

        var isLegJoint: Bool {
            switch self {
            case .leftHip, .leftKnee, .leftAnkle, .rightHip, .rightKnee, .rightAnkle: true
            default: false
            }
        }
    }

    struct Frame: Equatable, Sendable {
        let imageSize: CGSize
        let points: [Joint: CGPoint]

        private static let arms: [(Joint, Joint, Joint)] = [
            (.leftShoulder, .leftElbow, .leftWrist),
            (.rightShoulder, .rightElbow, .rightWrist)
        ]

        var visibleArms: Int {
            Self.arms.filter { points[$0.0] != nil && points[$0.1] != nil && points[$0.2] != nil }.count
        }

        var visibleLegs: Int {
            let left = points[.leftKnee] != nil || points[.leftAnkle] != nil
            let right = points[.rightKnee] != nil || points[.rightAnkle] != nil
            return (left ? 1 : 0) + (right ? 1 : 0)
        }

        func smoothed(from previous: Frame?) -> Frame {
            guard let previous, previous.imageSize == imageSize else { return self }
            var smoothed = points
            for (joint, point) in points {
                guard let last = previous.points[joint], hypot(point.x - last.x, point.y - last.y) < 0.10 else {
                    continue
                }
                smoothed[joint] = CGPoint(x: (point.x * 0.7 + last.x * 0.3),
                                         y: (point.y * 0.7 + last.y * 0.3))
            }
            return Frame(imageSize: imageSize, points: smoothed)
        }

    }

    static func previewRect(image: CGSize, in canvas: CGSize) -> CGRect {
        guard image.width > 0, image.height > 0 else { return .zero }
        let scale = min(canvas.width / image.width, canvas.height / image.height)
        let size = CGSize(width: image.width * scale, height: image.height * scale)
        return CGRect(x: (canvas.width - size.width) / 2, y: (canvas.height - size.height) / 2,
                      width: size.width, height: size.height)
    }

    static func previewPoint(_ point: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + point.x * rect.width, y: rect.minY + (1 - point.y) * rect.height)
    }
}

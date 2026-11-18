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

    struct FrontMeasurement {
        let relativeHeight: CGFloat
        let armsExtended: Bool
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

        var visibleLegs: Int { legs.count }

        var frontMeasurement: FrontMeasurement? {
            guard let left = arm(Self.arms[0]), let right = arm(Self.arms[1]) else { return nil }
            let shoulderWidth = abs(left.shoulder.x - right.shoulder.x)
            let wristWidth = abs(left.wrist.x - right.wrist.x)
            guard shoulderWidth >= imageSize.width * 0.045,
                  abs(left.shoulder.y - right.shoulder.y) <= shoulderWidth * 0.65,
                  wristWidth >= shoulderWidth * 0.18 else { return nil }

            let shoulderX = (left.shoulder.x + right.shoulder.x) / 2
            let wristY = (left.wrist.y + right.wrist.y) / 2
            // The knees or feet should be behind the hands in an elevated front view.
            guard legs.contains(where: {
                $0.contains { joint in
                    abs(joint.x - shoulderX) <= shoulderWidth * 1.4 && joint.y >= wristY - shoulderWidth * 0.30
                }
            }) else { return nil }

            let leftAngle = PoseGeometry.elbowAngle(shoulder: left.shoulder, elbow: left.elbow, wrist: left.wrist)
            let rightAngle = PoseGeometry.elbowAngle(shoulder: right.shoulder, elbow: right.elbow, wrist: right.wrist)
            guard let leftAngle, let rightAngle else { return nil }
            let shoulderY = (left.shoulder.y + right.shoulder.y) / 2
            return FrontMeasurement(relativeHeight: (shoulderY - wristY) / shoulderWidth,
                                    armsExtended: leftAngle >= 140 && rightAngle >= 140)
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

        private var legs: [[CGPoint]] {
            let left = [pixelPoint(.leftKnee), pixelPoint(.leftAnkle)].compactMap { $0 }
            let right = [pixelPoint(.rightKnee), pixelPoint(.rightAnkle)].compactMap { $0 }
            return [left, right].filter { !$0.isEmpty }
        }

        private func arm(_ joints: (Joint, Joint, Joint)) -> (shoulder: CGPoint, elbow: CGPoint, wrist: CGPoint)? {
            guard let shoulder = pixelPoint(joints.0), let elbow = pixelPoint(joints.1),
                  let wrist = pixelPoint(joints.2) else { return nil }
            return (shoulder, elbow, wrist)
        }

        private func pixelPoint(_ joint: Joint) -> CGPoint? {
            points[joint].map { CGPoint(x: $0.x * imageSize.width, y: $0.y * imageSize.height) }
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

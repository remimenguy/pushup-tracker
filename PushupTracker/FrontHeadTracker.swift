import Vision

/// Measures the same eye line with face landmarks first and body landmarks when needed.
final class FrontHeadTracker {
    private let request = VNDetectFaceLandmarksRequest()

    func sample(
        using handler: VNImageRequestHandler, imageSize: CGSize,
        bodyJoints: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]
    ) -> FrontPushUpCounter.Head? {
        let aspect = imageSize.width / imageSize.height
        let faces: [VNFaceObservation]
        do {
            try handler.perform([request])
            faces = request.results ?? []
        } catch {
            faces = []
        }
        guard faces.count <= 1 else { return nil }

        if let face = faces.first, let landmarks = face.landmarks,
           let left = center(of: landmarks.leftEye), let right = center(of: landmarks.rightEye) {
            let box = face.boundingBox
            return .init(x: (box.minX + (left.x + right.x) / 2 * box.width) * aspect,
                         y: box.minY + (left.y + right.y) / 2 * box.height,
                         width: box.width * aspect)
        }

        if let left = bodyJoints[.leftEye], let right = bodyJoints[.rightEye],
           left.confidence >= 0.25, right.confidence >= 0.25 {
            let eyeWidth = hypot((left.x - right.x) * aspect, left.y - right.y)
            return .init(x: (left.x + right.x) / 2 * aspect, y: (left.y + right.y) / 2,
                         width: eyeWidth * 2.4)
        }

        guard let box = faces.first?.boundingBox else { return nil }
        return .init(x: box.midX * aspect, y: box.midY + box.height * 0.12, width: box.width * aspect)
    }

    private func center(of eye: VNFaceLandmarkRegion2D?) -> CGPoint? {
        guard let points = eye?.normalizedPoints, !points.isEmpty else { return nil }
        let sum = points.reduce(CGPoint.zero) { sum, point in
            CGPoint(x: sum.x + point.x, y: sum.y + point.y)
        }
        return CGPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count))
    }
}

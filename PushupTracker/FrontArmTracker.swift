import CoreVideo
import Foundation
import Vision

/// Keeps measuring shoulder-to-wrist motion for a short period when pose landmarks disappear.
final class FrontArmTracker {
    private struct Observation {
        let arm: PoseGeometry.Arm
        let image: CVPixelBuffer
        let time: TimeInterval
    }

    private struct Tracks {
        let handler = VNSequenceRequestHandler()
        let shoulder: VNTrackObjectRequest
        let wrist: VNTrackObjectRequest

        init(arm: PoseGeometry.Arm, imageSize: CGSize) {
            shoulder = Self.request(at: arm.shoulder, side: max(24, arm.reach * 0.42), imageSize: imageSize)
            wrist = Self.request(at: arm.wrist, side: max(20, arm.reach * 0.25), imageSize: imageSize)
        }

        private static func request(at point: CGPoint, side: CGFloat, imageSize: CGSize) -> VNTrackObjectRequest {
            let rect = CGRect(x: (point.x - side / 2) / imageSize.width,
                              y: (point.y - side / 2) / imageSize.height,
                              width: side / imageSize.width, height: side / imageSize.height)
            let bounds = CGRect(x: 0, y: 0, width: 1, height: 1)
            let request = VNTrackObjectRequest(detectedObjectObservation: VNDetectedObjectObservation(boundingBox: rect.intersection(bounds)))
            request.trackingLevel = .accurate
            return request
        }

        func measure(on image: CVPixelBuffer, orientation: CGImagePropertyOrientation,
                     imageSize: CGSize) throws -> PoseGeometry.Arm? {
            try handler.perform([shoulder, wrist], on: image, orientation: orientation)
            guard let shoulderResult = shoulder.results?.first as? VNDetectedObjectObservation,
                  let wristResult = wrist.results?.first as? VNDetectedObjectObservation,
                  shoulderResult.confidence >= 0.45, wristResult.confidence >= 0.45 else { return nil }

            shoulder.inputObservation = shoulderResult
            wrist.inputObservation = wristResult
            func center(_ observation: VNDetectedObjectObservation) -> CGPoint {
                CGPoint(x: observation.boundingBox.midX * imageSize.width,
                        y: observation.boundingBox.midY * imageSize.height)
            }
            return PoseGeometry.Arm(shoulder: center(shoulderResult), elbow: nil, wrist: center(wristResult))
        }
    }

    private var lastObservation: Observation?
    private var tracks: Tracks?

    func update(
        observed arm: PoseGeometry.Arm?, image: CVPixelBuffer, orientation: CGImagePropertyOrientation,
        imageSize: CGSize, at time: TimeInterval
    ) -> PoseGeometry.Arm? {
        if let arm {
            tracks = nil
            lastObservation = Observation(arm: arm, image: image, time: time)
            return arm
        }

        guard let lastObservation, time - lastObservation.time <= 1.2 else {
            self.lastObservation = nil
            tracks = nil
            return nil
        }

        do {
            if tracks == nil {
                let seeded = Tracks(arm: lastObservation.arm, imageSize: imageSize)
                guard try seeded.measure(on: lastObservation.image, orientation: orientation, imageSize: imageSize) != nil else {
                    self.lastObservation = nil
                    return nil
                }
                tracks = seeded
            }

            if let measurement = try tracks?.measure(on: image, orientation: orientation, imageSize: imageSize) {
                return measurement
            }
        } catch {
            // The arm counter can resume from the last confirmed pose when landmarks return.
        }
        self.lastObservation = nil
        tracks = nil
        return nil
    }
}

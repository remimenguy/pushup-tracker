@preconcurrency import AVFoundation
import CoreMedia
import Foundation
import Vision

final class CameraEngine: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    enum Mode: String, CaseIterable, Sendable {
        case front, side

        var title: String { self == .front ? "De face" : "De profil" }
    }

    enum Status: Equatable, Sendable {
        case framing, searching, ready, denied, unavailable
        case front(arms: Int, legs: Int, inPosition: Bool, followingDescent: Bool)
    }

    struct Update: Equatable, Sendable {
        let status: Status
        let repetitions: Int
        let pose: PoseGeometry.Frame?
    }

    let session = AVCaptureSession()
    let updates: AsyncStream<Update>

    private let continuation: AsyncStream<Update>.Continuation
    private let queue = DispatchQueue(label: "fr.menguy.pushuptracker.camera", qos: .userInitiated)
    // Capture and analysis state is confined to queue.
    private var isConfigured = false
    private var isCounting = false
    private var mode = Mode.front
    private var frontCounter = FrontPushUpCounter()
    private var lastPose: PoseGeometry.Frame?
    private var repetitions = 0
    private var lastUpdate: Update?
    private var lastAnalysisAt = -Double.infinity
    private var lastSideAt = -Double.infinity
    private var trackedSide: Arm?
    private var counter = PushUpCounter()
    private let poseRequest = VNDetectHumanBodyPoseRequest()

    override init() {
        (updates, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
        super.init()
    }

    deinit {
        continuation.finish()
    }

    func start() async {
        let allowed: Bool
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: allowed = true
        case .notDetermined: allowed = await AVCaptureDevice.requestAccess(for: .video)
        default: allowed = false
        }
        guard !Task.isCancelled else { return }
        queue.async { [self] in
            guard allowed else { publish(.denied); return }
            guard configureIfNeeded() else { publish(.unavailable); return }
            if !session.isRunning { session.startRunning() }
            publish(session.isRunning ? .framing : .unavailable)
        }
    }

    func stop() {
        queue.async { [self] in
            resetTracking()
            if session.isRunning { session.stopRunning() }
        }
    }

    func finishCounting() async -> Int {
        await withCheckedContinuation { result in
            queue.async { [self] in
                isCounting = false
                resetTracking()
                if session.isRunning { session.stopRunning() }
                result.resume(returning: repetitions)
            }
        }
    }

    func setMode(_ mode: Mode) {
        queue.async { [self] in
            guard self.mode != mode else { return }
            self.mode = mode
            resetTracking()
            if session.isRunning { publish(.framing) }
        }
    }

    func beginCounting() {
        queue.async { [self] in
            isCounting = true
            resetTracking()
        }
    }

    private func configureIfNeeded() -> Bool {
        if isConfigured { return true }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device)
        else { return false }

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)

        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if session.canSetSessionPreset(.vga640x480) { session.sessionPreset = .vga640x480 }
        guard session.canAddInput(input) else { return false }
        session.addInput(input)
        guard session.canAddOutput(output) else {
            session.removeInput(input)
            return false
        }
        session.addOutput(output)
        if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
            }
        }
        isConfigured = true
        return true
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput buffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let image = CMSampleBufferGetImageBuffer(buffer) else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastAnalysisAt >= 1.0 / 16 else { return }
        lastAnalysisAt = now

        let orientation: CGImagePropertyOrientation = connection.videoRotationAngle == 90 ? .up : .leftMirrored
        let handler = VNImageRequestHandler(cvPixelBuffer: image, orientation: orientation)
        let width = CVPixelBufferGetWidth(image)
        let height = CVPixelBufferGetHeight(image)
        let size = orientation == .up ? CGSize(width: width, height: height) : CGSize(width: height, height: width)
        let joints = recognizedJoints(using: handler)
        let points = Dictionary(uniqueKeysWithValues: Self.displayJoints.compactMap { joint, key -> (PoseGeometry.Joint, CGPoint)? in
            guard let point = joints[key], point.confidence >= (joint.isLegJoint ? 0.25 : 0.35),
                  (0...1).contains(point.x), (0...1).contains(point.y) else { return nil }
            return (joint, point.location)
        })
        let pose = PoseGeometry.Frame(imageSize: size, points: points)
        lastPose = pose.smoothed(from: lastPose)

        switch mode {
        case .front:
            let measurement = pose.frontMeasurement
            if isCounting, frontCounter.update(pose, measurement: measurement, at: now) { repetitions += 1 }
            publish(.front(arms: pose.visibleArms, legs: pose.visibleLegs, inPosition: measurement != nil,
                           followingDescent: isCounting && frontCounter.isFollowingDescent), pose: lastPose)
        case .side:
            analyzeSide(joints, size: size, at: now)
        }
    }

    private func recognizedJoints(using handler: VNImageRequestHandler) -> [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint] {
        do {
            try handler.perform([poseRequest])
            guard let results = poseRequest.results, results.count == 1 else { return [:] }
            return try results[0].recognizedPoints(.all)
        } catch {
            return [:]
        }
    }

    private func analyzeSide(
        _ joints: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint], size: CGSize, at now: TimeInterval
    ) {
        let measurements = Dictionary(uniqueKeysWithValues: Arm.allCases.compactMap { arm in
            arm.measurement(of: joints, size: size).map { (arm, $0) }
        })
        if now - lastSideAt > 0.45 {
            trackedSide = measurements.max { $0.value.confidence < $1.value.confidence }?.key
            counter = PushUpCounter()
        }
        let angle = trackedSide.flatMap { measurements[$0]?.angle }
        if angle != nil { lastSideAt = now }
        if isCounting, counter.update(angle: angle, at: now) { repetitions += 1 }
        publish(angle == nil ? .searching : .ready, pose: lastPose)
    }

    private func resetTracking() {
        lastAnalysisAt = -.infinity
        lastSideAt = -.infinity
        trackedSide = nil
        counter = PushUpCounter()
        frontCounter = FrontPushUpCounter()
        lastPose = nil
    }

    private func publish(_ status: Status, pose: PoseGeometry.Frame? = nil) {
        let update = Update(status: status, repetitions: repetitions, pose: pose)
        guard update != lastUpdate else { return }
        lastUpdate = update
        continuation.yield(update)
    }

    private static let displayJoints: [(PoseGeometry.Joint, VNHumanBodyPoseObservation.JointName)] = [
        (.leftShoulder, .leftShoulder), (.leftElbow, .leftElbow), (.leftWrist, .leftWrist),
        (.leftHip, .leftHip), (.leftKnee, .leftKnee), (.leftAnkle, .leftAnkle),
        (.rightShoulder, .rightShoulder), (.rightElbow, .rightElbow), (.rightWrist, .rightWrist),
        (.rightHip, .rightHip), (.rightKnee, .rightKnee), (.rightAnkle, .rightAnkle)
    ]

    private struct Measurement {
        let angle: Double
        let confidence: Float
    }

    private enum Arm: CaseIterable {
        case left, right

        func measurement(
            of joints: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint], size: CGSize
        ) -> Measurement? {
            let names: [VNHumanBodyPoseObservation.JointName] = switch self {
            case .left: [.leftShoulder, .leftElbow, .leftWrist, .leftHip]
            case .right: [.rightShoulder, .rightElbow, .rightWrist, .rightHip]
            }
            let points = names.compactMap { joints[$0] }
            guard points.count == names.count,
                  let confidence = points.map(\.confidence).min(), confidence >= 0.35 else { return nil }

            let scaled = points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
            guard let angle = PoseGeometry.elbowAngle(
                shoulder: scaled[0], elbow: scaled[1], wrist: scaled[2], hip: scaled[3]
            ) else { return nil }
            return Measurement(angle: angle, confidence: confidence)
        }
    }
}

import Foundation

struct PushUpCounter {
    enum Phase: Equatable {
        case waitingForTop, waitingForBottom, waitingForReturn
    }

    enum Position: Equatable { case top, middle, bottom }

    private(set) var phase = Phase.waitingForTop
    private var candidateSince: TimeInterval?
    private var lastTrackedAt: TimeInterval?
    private let trackingTimeout: TimeInterval

    init(trackingTimeout: TimeInterval = 0.45) {
        self.trackingTimeout = trackingTimeout
    }

    @discardableResult
    mutating func update(angle: Double?, at seconds: TimeInterval) -> Bool {
        let position = angle.flatMap { value -> Position? in
            guard value.isFinite else { return nil }
            if value >= 150 { return .top }
            if value <= 105 { return .bottom }
            return .middle
        }
        return update(position: position, at: seconds)
    }

    @discardableResult
    mutating func update(position: Position?, at seconds: TimeInterval) -> Bool {
        if let lastTrackedAt, seconds - lastTrackedAt > trackingTimeout {
            self = Self(trackingTimeout: trackingTimeout)
        }
        guard let position else {
            candidateSince = nil
            return false
        }
        lastTrackedAt = seconds

        let reachedPosition = phase == .waitingForBottom ? position == .bottom : position == .top
        guard reachedPosition else {
            candidateSince = nil
            return false
        }
        guard let candidateSince else {
            self.candidateSince = seconds
            return false
        }
        guard seconds - candidateSince >= 0.085 else { return false }

        self.candidateSince = nil
        switch phase {
        case .waitingForTop:
            phase = .waitingForBottom
        case .waitingForBottom:
            phase = .waitingForReturn
        case .waitingForReturn:
            phase = .waitingForBottom
            return true
        }
        return false
    }
}

struct FrontPushUpCounter {
    private struct Reference {
        let frame: PoseGeometry.Frame
        let height: CGFloat
    }

    private var cycle = PushUpCounter(trackingTimeout: 1.5)
    private var reference: Reference?
    private var nearBottomAt: TimeInterval?

    var isFollowingDescent: Bool {
        cycle.phase == .waitingForReturn || nearBottomAt != nil
    }

    mutating func update(
        _ frame: PoseGeometry.Frame, measurement: PoseGeometry.FrontMeasurement?, at seconds: TimeInterval
    ) -> Bool {
        if let reference, measurement != nil, !frame.hasMatchingWrists(to: reference.frame) {
            self = Self()
        }

        let previousPhase = cycle.phase
        let position = position(of: frame, measurement: measurement, at: seconds)
        let counted = cycle.update(position: position, at: seconds)

        if cycle.phase == .waitingForTop {
            reference = nil
            nearBottomAt = nil
        } else if (previousPhase == .waitingForTop || counted), let measurement {
            reference = Reference(frame: frame, height: measurement.relativeHeight)
            nearBottomAt = nil
        }

        return counted
    }

    private mutating func position(
        of frame: PoseGeometry.Frame, measurement: PoseGeometry.FrontMeasurement?, at seconds: TimeInterval
    ) -> PushUpCounter.Position? {
        guard let reference else {
            return measurement.map { $0.armsExtended && $0.relativeHeight >= 0.62 ? .top : .middle }
        }

        if let drop = frame.shoulderDrop(from: reference.frame) {
            nearBottomAt = drop >= reference.height * 0.30 ? seconds : nil
            if drop >= reference.height * 0.35 { return .bottom }
            if let measurement, measurement.armsExtended, measurement.relativeHeight >= reference.height * 0.85,
               drop <= reference.height * 0.20 {
                return .top
            }
            return .middle
        }

        // A short occlusion can complete a descent only when the shoulders were already near the bottom.
        if let nearBottomAt, seconds - nearBottomAt <= 0.22 {
            return .bottom
        }
        return nil
    }
}

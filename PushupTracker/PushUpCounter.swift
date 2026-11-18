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


// Front tracking uses a calibrated eye line and a down/up hysteresis cycle.
// Reference: https://github.com/quickpose/Flappy-Pushups-iOS-Demo-App
struct FrontPushUpCounter {
    struct Head {
        /// Horizontal coordinates and widths are expressed in units of image height.
        let x: CGFloat
        let y: CGFloat
        let width: CGFloat

        var isUsable: Bool { x.isFinite && (0...1).contains(y) && width.isFinite && width >= 0.017 }
    }

    private static let trackingTimeout: TimeInterval = 1.25
    private var cycle = PushUpCounter(trackingTimeout: trackingTimeout)
    private var baseline: Head?
    private var calibration: (head: Head, since: TimeInterval)?
    private var lastSeenAt: TimeInterval?
    private var nearBottomAt: TimeInterval?

    var isFollowingDescent: Bool {
        cycle.phase == .waitingForReturn || nearBottomAt != nil
    }

    mutating func update(_ head: Head?, at seconds: TimeInterval) -> Bool {
        if let lastSeenAt, seconds - lastSeenAt > Self.trackingTimeout {
            self = Self()
        }

        guard let head, head.isUsable else {
            calibration = nil
            let inferredBottom = nearBottomAt.map { seconds - $0 <= 0.30 } ?? false
            return cycle.update(position: inferredBottom ? .bottom : nil, at: seconds)
        }
        lastSeenAt = seconds

        guard let baseline else {
            calibrate(head, at: seconds)
            return false
        }
        if abs(head.x - baseline.x) > max(baseline.width * 1.25, 0.05) {
            self = Self()
            lastSeenAt = seconds
            calibrate(head, at: seconds)
            return false
        }

        let drop = baseline.y - head.y
        let bottomDepth = max(baseline.width * 0.55, 0.022)
        let returnTolerance = max(baseline.width * 0.24, 0.010)
        nearBottomAt = drop >= bottomDepth * 0.9 ? seconds : nil

        let position: PushUpCounter.Position
        if drop >= bottomDepth {
            position = .bottom
        } else if abs(drop) <= returnTolerance {
            position = .top
        } else {
            position = .middle
        }

        let counted = cycle.update(position: position, at: seconds)
        if counted {
            self.baseline = head
            nearBottomAt = nil
        }
        return counted
    }

    private mutating func calibrate(_ head: Head, at seconds: TimeInterval) {
        guard let calibration,
              abs(head.y - calibration.head.y) <= max(head.width * 0.12, 0.005),
              abs(head.x - calibration.head.x) <= max(head.width * 0.20, 0.008) else {
            calibration = (head, seconds)
            return
        }
        guard seconds - calibration.since >= 0.24 else { return }
        baseline = head
        self.calibration = nil
        cycle.update(position: .top, at: calibration.since)
        cycle.update(position: .top, at: seconds)
    }
}

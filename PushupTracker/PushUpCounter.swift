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
    struct Thresholds {
        let extensionAngle: Double
        let flexionAngle: Double
        let shortReach: CGFloat
        let returnReach: CGFloat
        let wristTravel: CGFloat

        static let standard = Self(extensionAngle: 140, flexionAngle: 123, shortReach: 0.68,
                                   returnReach: 0.82, wristTravel: 0.38)
    }

    private let thresholds: Thresholds
    private var left = ArmCycle()
    private var right = ArmCycle()

    init(thresholds: Thresholds = .standard) {
        self.thresholds = thresholds
    }

    var isFollowingFlexion: Bool {
        left.isFollowingFlexion || right.isFollowingFlexion
    }

    mutating func update(left: PoseGeometry.Arm?, right: PoseGeometry.Arm?, at seconds: TimeInterval) -> Bool {
        let leftCounted = self.left.update(left, at: seconds, thresholds: thresholds)
        let rightCounted = self.right.update(right, at: seconds, thresholds: thresholds)

        // An arm that is still returning cannot count the same repetition later.
        if leftCounted && !rightCounted { self.right = ArmCycle() }
        if rightCounted && !leftCounted { self.left = ArmCycle() }
        return leftCounted || rightCounted
    }

    private struct ArmCycle {
        private var cycle = PushUpCounter(trackingTimeout: .infinity)
        private var extensionPose: PoseGeometry.Arm?
        private var newPlacement: (arm: PoseGeometry.Arm, since: TimeInterval)?

        var isFollowingFlexion: Bool { cycle.phase == .waitingForReturn }

        mutating func update(_ arm: PoseGeometry.Arm?, at seconds: TimeInterval, thresholds: Thresholds) -> Bool {
            // Missing observations pause the sequence. A new, observed hand placement can replace it.
            guard let arm else { return false }
            let angle = arm.elbowAngle
            let isExtended = (angle.map { $0 >= thresholds.extensionAngle } ?? false) &&
                arm.verticalReach >= arm.reach * 0.4

            if let extensionPose, arm.wristDistance(from: extensionPose) > extensionPose.reach * thresholds.wristTravel {
                guard isExtended else {
                    newPlacement = nil
                    return false
                }
                if let newPlacement,
                   arm.wristDistance(from: newPlacement.arm) <= newPlacement.arm.reach * thresholds.wristTravel {
                    guard seconds - newPlacement.since >= 0.085 else { return false }
                    self = ArmCycle()
                    cycle.update(position: .top, at: newPlacement.since)
                } else {
                    newPlacement = (arm, seconds)
                    return false
                }
            }
            newPlacement = nil

            let phase = cycle.phase
            let position: PushUpCounter.Position
            if let reference = extensionPose {
                let reach = reference.reach
                // A bend toward the camera compresses the arm's projection, even if its angle looks straight.
                let isForeshortened = arm.reach <= reach * thresholds.shortReach &&
                    reference.verticalReach - arm.verticalReach >= reach * 0.20
                if (angle.map { $0 <= thresholds.flexionAngle } ?? false) || isForeshortened {
                    position = .bottom
                } else if (isExtended && arm.reach >= reach * thresholds.returnReach) ||
                            (angle.map { $0 >= thresholds.extensionAngle - 10 } == true && arm.reach >= reach * 0.94) {
                    position = .top
                } else {
                    position = .middle
                }
            } else {
                position = isExtended ? .top : .middle
            }

            let counted = cycle.update(position: position, at: seconds)
            if (phase == .waitingForTop && cycle.phase == .waitingForBottom) || counted {
                extensionPose = arm
            }
            return counted
        }
    }
}

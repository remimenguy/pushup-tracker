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
    private var left = ArmCycle()
    private var right = ArmCycle()

    var isFollowingFlexion: Bool {
        left.isFollowingFlexion || right.isFollowingFlexion
    }

    mutating func update(left: PoseGeometry.Arm?, right: PoseGeometry.Arm?, at seconds: TimeInterval) -> Bool {
        let leftCounted = self.left.update(left, at: seconds)
        let rightCounted = self.right.update(right, at: seconds)

        // An arm that is still returning cannot count the same repetition later.
        if leftCounted && !rightCounted { self.right = ArmCycle() }
        if rightCounted && !leftCounted { self.left = ArmCycle() }
        return leftCounted || rightCounted
    }

    private struct ArmCycle {
        private var cycle = PushUpCounter(trackingTimeout: 0.85)
        private var extensionPose: PoseGeometry.Arm?
        private var lastFlexionAt: TimeInterval?

        var isFollowingFlexion: Bool { cycle.phase == .waitingForReturn }

        mutating func update(_ arm: PoseGeometry.Arm?, at seconds: TimeInterval) -> Bool {
            let phase = cycle.phase
            let position = arm.flatMap { classify($0, relativeTo: extensionPose) }
            // Keep a low candidate across a dropped frame. Only another measured low frame can confirm it.
            if position == nil, phase == .waitingForBottom,
               let lastFlexionAt, seconds - lastFlexionAt <= 0.22 {
                return false
            }
            lastFlexionAt = position == .bottom ? seconds : nil
            let counted = cycle.update(position: position, at: seconds)

            if cycle.phase == .waitingForTop {
                extensionPose = nil
            } else if phase == .waitingForTop || counted {
                extensionPose = arm
            }
            return counted
        }

        private func classify(_ arm: PoseGeometry.Arm, relativeTo extensionPose: PoseGeometry.Arm?) -> PushUpCounter.Position? {
            let angle = arm.elbowAngle
            guard let extensionPose else {
                guard let angle else { return nil }
                return angle >= 140 && arm.verticalReach >= arm.reach * 0.4 ? .top : .middle
            }

            let reach = extensionPose.reach
            guard arm.wristDistance(from: extensionPose) <= reach * 0.38 else { return nil }

            // An elbow can bend toward the camera without changing its projected angle much.
            let isForeshortened = arm.reach <= reach * 0.68 &&
                extensionPose.verticalReach - arm.verticalReach >= reach * 0.20
            if (angle.map { $0 <= 123 } ?? false) || isForeshortened { return .bottom }
            guard let angle else { return .middle }
            if (angle >= 140 && arm.reach >= reach * 0.82) ||
                (angle >= 130 && arm.reach >= reach * 0.94) {
                return .top
            }
            return .middle
        }
    }
}

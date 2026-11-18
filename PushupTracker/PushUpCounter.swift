import Foundation

struct PushUpCounter {
    enum Phase: Equatable {
        case waitingForTop, waitingForBottom, waitingForReturn
    }

    enum Position: Equatable { case top, middle, bottom }

    private(set) var phase = Phase.waitingForTop
    private var candidateSince: TimeInterval?
    private var lastTrackedAt: TimeInterval?

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
        if let lastTrackedAt, seconds - lastTrackedAt > 0.45 {
            self = Self()
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
    private var cycle = PushUpCounter()
    private var topHeight: CGFloat?

    mutating func update(_ measurement: PoseGeometry.FrontMeasurement?, at seconds: TimeInterval) -> Bool {
        let phase = cycle.phase
        let position = measurement.map { measurement -> PushUpCounter.Position in
            let height = measurement.relativeHeight
            if phase != .waitingForTop, let topHeight, height <= topHeight * 0.65 {
                return .bottom
            }
            let minimumHeight = phase == .waitingForTop ? 0.62 : (topHeight ?? 0.62) * 0.85
            return height >= minimumHeight && measurement.armsExtended ? .top : .middle
        }

        let counted = cycle.update(position: position, at: seconds)
        if phase == .waitingForTop && cycle.phase == .waitingForBottom {
            topHeight = measurement?.relativeHeight
        } else if counted, let height = measurement?.relativeHeight, let topHeight {
            self.topHeight = topHeight * 0.75 + height * 0.25
        }
        return counted
    }
}

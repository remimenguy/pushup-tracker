import Foundation

struct PushUpCounter {
    enum Phase: Equatable {
        case waitingForTop, waitingForBottom, waitingForReturn
    }

    private(set) var phase = Phase.waitingForTop
    private var candidateSince: TimeInterval?
    private var lastTrackedAt: TimeInterval?

    @discardableResult
    mutating func update(angle: Double?, at seconds: TimeInterval) -> Bool {
        if let lastTrackedAt, seconds - lastTrackedAt > 0.45 {
            self = Self()
        }
        guard let angle, angle.isFinite else {
            candidateSince = nil
            return false
        }
        lastTrackedAt = seconds

        let reachedPosition = phase == .waitingForBottom ? angle <= 105 : angle >= 150
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

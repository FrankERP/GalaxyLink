struct Decision: Equatable {
    let send: Bool
    let requestKeyframe: Bool
}

struct BackpressurePolicy {
    private enum State { case normal, dropping, awaitingKeyframe }
    private var state: State = .normal
    let highWatermark: Int
    let lowWatermark: Int

    init(highWatermark: Int = 3_000_000, lowWatermark: Int = 500_000) {
        self.highWatermark = highWatermark
        self.lowWatermark = lowWatermark
    }

    mutating func decide(isKeyframe: Bool, queuedBytes: Int) -> Decision {
        if queuedBytes > highWatermark { state = .dropping }
        switch state {
        case .normal:
            return Decision(send: true, requestKeyframe: false)
        case .dropping:
            if queuedBytes < lowWatermark {
                state = .awaitingKeyframe
                return Decision(send: false, requestKeyframe: true)
            }
            return Decision(send: false, requestKeyframe: false)
        case .awaitingKeyframe:
            if isKeyframe {
                state = .normal
                return Decision(send: true, requestKeyframe: false)
            }
            return Decision(send: false, requestKeyframe: false)
        }
    }
}

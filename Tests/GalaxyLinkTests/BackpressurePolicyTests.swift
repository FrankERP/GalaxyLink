import XCTest
@testable import GalaxyLink

final class BackpressurePolicyTests: XCTestCase {
    func testNormalSendsEverything() {
        var p = BackpressurePolicy(highWatermark: 100, lowWatermark: 10)
        XCTAssertEqual(p.decide(isKeyframe: false, queuedBytes: 0), Decision(send: true, requestKeyframe: false))
        XCTAssertEqual(p.decide(isKeyframe: true, queuedBytes: 50), Decision(send: true, requestKeyframe: false))
    }

    func testEntersDroppingAboveHighWatermark() {
        var p = BackpressurePolicy(highWatermark: 100, lowWatermark: 10)
        XCTAssertEqual(p.decide(isKeyframe: false, queuedBytes: 101), Decision(send: false, requestKeyframe: false))
        // still dropping, even keyframes, while congested
        XCTAssertEqual(p.decide(isKeyframe: true, queuedBytes: 60), Decision(send: false, requestKeyframe: false))
    }

    func testRecoveryRequestsKeyframeThenResumesOnKeyframe() {
        var p = BackpressurePolicy(highWatermark: 100, lowWatermark: 10)
        _ = p.decide(isKeyframe: false, queuedBytes: 101)              // -> dropping
        XCTAssertEqual(p.decide(isKeyframe: false, queuedBytes: 5),    // drained -> ask for keyframe
                       Decision(send: false, requestKeyframe: true))
        XCTAssertEqual(p.decide(isKeyframe: false, queuedBytes: 5),    // deltas still dropped
                       Decision(send: false, requestKeyframe: false))
        XCTAssertEqual(p.decide(isKeyframe: true, queuedBytes: 5),     // keyframe resumes
                       Decision(send: true, requestKeyframe: false))
        XCTAssertEqual(p.decide(isKeyframe: false, queuedBytes: 5),
                       Decision(send: true, requestKeyframe: false))
    }

    func testRecongestionWhileAwaitingKeyframe() {
        var p = BackpressurePolicy(highWatermark: 100, lowWatermark: 10)
        _ = p.decide(isKeyframe: false, queuedBytes: 101)
        _ = p.decide(isKeyframe: false, queuedBytes: 5)                // awaitingKeyframe
        XCTAssertEqual(p.decide(isKeyframe: true, queuedBytes: 200),   // congested again -> drop
                       Decision(send: false, requestKeyframe: false))
    }
}

import Foundation
import Testing
@testable import CampComicsCore

@Suite("SwipeBlockedReason — maps a blocked swipe-right to the banner it should surface")
struct SwipeBlockedReasonTests {

    @Test func returnsNilWhenSwipeIsAllowedToFire() {
        let reason = SwipeBlockedReason.evaluate(
            rerollDecision: .fire,
            isRerollInFlight: false,
            isTopStuck: false
        )

        #expect(reason == nil)
    }

    @Test func budgetExhaustedMapsToOutOfRerolls() {
        let reason = SwipeBlockedReason.evaluate(
            rerollDecision: .bounce,
            isRerollInFlight: false,
            isTopStuck: false
        )

        #expect(reason == .outOfRerolls)
    }

    @Test func fireableSwipeWhileRerollInFlightMapsToStillRolling() {
        // Budget says fire, but a prior re-roll task hasn't completed. Existing
        // gesture code silently bounces; #117 surfaces this as a banner.
        let reason = SwipeBlockedReason.evaluate(
            rerollDecision: .fire,
            isRerollInFlight: true,
            isTopStuck: false
        )

        #expect(reason == .stillRolling)
    }

    @Test func stuckHeadAlwaysReportsNoCandidateYet() {
        // The stuck branch in ReviewDeckView's gesture handler bypasses
        // RerollDecider entirely (see commitAdvancePastStuck / line 508).
        // Whatever budget says, swipe-right on stuck = no candidate to re-roll.
        for inFlight in [false, true] {
            for decision in [RerollDecision.fire, .bounce, .requireConfirm] {
                let reason = SwipeBlockedReason.evaluate(
                    rerollDecision: decision,
                    isRerollInFlight: inFlight,
                    isTopStuck: true
                )
                #expect(reason == .noCandidateYet,
                        "stuck should win over decision=\(decision) inFlight=\(inFlight)")
            }
        }
    }

    @Test func bannerCopyIsAllCapsForEveryReason() {
        // The deck's headingFont (Optima-Bold) reads as a tutorial stamp when
        // SCREAMED. Lowercase would soften it past the D&D-card vibe.
        #expect(SwipeBlockedReason.outOfRerolls.bannerCopy   == "OUT OF REROLLS")
        #expect(SwipeBlockedReason.stillRolling.bannerCopy   == "STILL ROLLING…")
        #expect(SwipeBlockedReason.noCandidateYet.bannerCopy == "NO CANDIDATE YET")
    }
}

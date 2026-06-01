import Foundation
import Testing
@testable import CampComicsCore

@Suite("RerollCounter per-unit tally")
struct RerollCounterTests {

    @Test func freshCounterReportsZeroForAnyUnit() {
        let counter = RerollCounter()

        #expect(counter.count(unitId: "panel_03") == 0)
        #expect(counter.count(unitId: "pIn") == 0)
    }

    @Test func incrementAdvancesOnlyTheNamedUnit() {
        var counter = RerollCounter()

        counter.increment(unitId: "panel_03")
        counter.increment(unitId: "panel_03")
        counter.increment(unitId: "pIn")

        #expect(counter.count(unitId: "panel_03") == 2)
        #expect(counter.count(unitId: "pIn") == 1)
        #expect(counter.count(unitId: "panel_07") == 0)
    }
}

@Suite("RerollDecider routes the operator's swipe-right")
struct RerollDeciderTests {

    @Test func exhaustedBudgetBouncesSilently() {
        let decision = RerollDecider.decide(remaining: 0, cost: 1, priorRerolls: 0)

        #expect(decision == .bounce)
    }

    @Test func budgetTooSmallForTriptychCostBounces() {
        // Triptych spends 3; if only 2 remain we soft-block this unit even
        // though `remaining > 0` — partial spend on a triptych is incoherent.
        let decision = RerollDecider.decide(remaining: 2, cost: 3, priorRerolls: 0)

        #expect(decision == .bounce)
    }

    @Test func firstThreeRerollsFireWithoutFriction() {
        for prior in 0...2 {
            let decision = RerollDecider.decide(remaining: 10, cost: 1, priorRerolls: prior)
            #expect(decision == .fire, "prior=\(prior) should fire")
        }
    }

    @Test func fourthRerollSurfacesConfirm() {
        let decision = RerollDecider.decide(remaining: 10, cost: 1, priorRerolls: 3)

        #expect(decision == .requireConfirm)
    }

    @Test func frictionConfirmStaysStickyAfterTheFourth() {
        // 5th, 10th, 100th — the confirm doesn't escalate, but it doesn't
        // disappear either. Per ADR-0010: "no hard ceiling, no escalating
        // friction. Confirming fires the re-roll; cancelling no-ops."
        for prior in [4, 5, 10, 100] {
            let decision = RerollDecider.decide(remaining: 10, cost: 1, priorRerolls: prior)
            #expect(decision == .requireConfirm, "prior=\(prior) should still confirm")
        }
    }

    @Test func bounceWinsOverFrictionWhenBudgetIsZero() {
        // Even if the operator has hammered re-roll on this card, an exhausted
        // budget still soft-blocks. No confirm dialog, no API call — just bounce.
        let decision = RerollDecider.decide(remaining: 0, cost: 1, priorRerolls: 7)

        #expect(decision == .bounce)
    }
}

@Suite("ReviewUnit friction key (per-unit counter address)")
struct ReviewUnitFrictionKeyTests {

    private func spec(_ n: Int) -> PanelSpec {
        PanelSpec(n: n, beat: "", emotion: .neutral, position: .front)
    }

    @Test func singlePanelKeyIsDiskName() {
        let unit: ReviewUnit = .single(.panel(n: 7, spec: spec(7)))

        #expect(unit.frictionKey == "panel_07")
    }

    @Test func coverKeyIsCoverLiteral() {
        let cover: PanelTarget = .cover(spec: CoverSpec(emotion: .neutral,
                                                         position: .front))
        let unit: ReviewUnit = .single(cover)

        #expect(unit.frictionKey == "cover")
    }

    @Test func triptychKeysAreShared() {
        let pIn = PanelTriptych(kind: .pIn, subTargets: [
            .panel(n: 3, spec: spec(3)),
            .panel(n: 4, spec: spec(4)),
            .panel(n: 5, spec: spec(5))
        ])
        let hOut = PanelTriptych(kind: .hOut, subTargets: [
            .panel(n: 12, spec: spec(12)),
            .panel(n: 13, spec: spec(13)),
            .panel(n: 14, spec: spec(14))
        ])

        #expect(ReviewUnit.triptych(pIn).frictionKey == "triptych_pIn")
        #expect(ReviewUnit.triptych(hOut).frictionKey == "triptych_hOut")
        // Distinct from any sub-panel disk name: if the operator hammers
        // re-roll on the triptych, only one counter ticks.
        #expect(ReviewUnit.triptych(pIn).frictionKey != "panel_03")
    }
}



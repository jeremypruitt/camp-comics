import Foundation
import Testing
@testable import CampComicsCore

@Suite("PanelTriptych")
struct PanelTriptychTests {

    // MARK: - Fixtures

    private func makeStore() throws -> (PlayerStore, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("camp-comics-triptych-tests-\(UUID().uuidString)",
                                    isDirectory: true)
        let store = try PlayerStore(root: root)
        return (store, root)
    }

    private func makeTemplate() -> ClassTemplate {
        ClassTemplate(
            classKey: "druid",
            name: "Druid",
            costume: "leaves",
            palette: Palette(lighting: "warm", colors: "green"),
            panels: (1...15).map {
                PanelSpec(n: $0, beat: "beat \($0)", emotion: .neutral, position: .front)
            },
            cover: CoverSpec(emotion: .neutral, position: .front, poseDirective: "p")
        )
    }

    // MARK: - Kind / containment

    @Test func pInRangeIsPanels3Through5() {
        #expect(PanelTriptych.Kind.containing(panelNumber: 3) == .pIn)
        #expect(PanelTriptych.Kind.containing(panelNumber: 4) == .pIn)
        #expect(PanelTriptych.Kind.containing(panelNumber: 5) == .pIn)
    }

    @Test func hOutRangeIsPanels12Through14() {
        #expect(PanelTriptych.Kind.containing(panelNumber: 12) == .hOut)
        #expect(PanelTriptych.Kind.containing(panelNumber: 13) == .hOut)
        #expect(PanelTriptych.Kind.containing(panelNumber: 14) == .hOut)
    }

    @Test func nonTriptychPanelsReturnNil() {
        for n in [1, 2, 6, 7, 8, 9, 10, 11, 15] {
            #expect(PanelTriptych.Kind.containing(panelNumber: n) == nil,
                    "panel \(n) should not be a triptych member")
        }
    }

    @Test func subPanelNumbersAreOrderedLeftMiddleRight() {
        #expect(PanelTriptych.Kind.pIn.subPanelNumbers == [3, 4, 5])
        #expect(PanelTriptych.Kind.hOut.subPanelNumbers == [12, 13, 14])
    }

    // MARK: - Construction from template

    @Test func makePullsTheThreeSubTargetsInOrder() throws {
        let template = makeTemplate()
        let trip = try #require(PanelTriptych.make(kind: .pIn, from: template))
        #expect(trip.subTargets.count == 3)
        #expect(trip.subTargets.map(\.diskName) == ["panel_03", "panel_04", "panel_05"])
    }

    @Test func makeReturnsNilWhenTemplateMissingASubPanel() {
        // Build a template missing panel 4 — the P-in triptych can't be formed.
        let template = ClassTemplate(
            classKey: "x", name: "X", costume: "",
            palette: Palette(lighting: "", colors: ""),
            panels: [3, 5].map { PanelSpec(n: $0, beat: "", emotion: .neutral, position: .front) },
            cover: CoverSpec(emotion: .neutral, position: .front, poseDirective: "")
        )
        #expect(PanelTriptych.make(kind: .pIn, from: template) == nil)
    }

    // MARK: - Budget cost

    @Test func budgetCostIsThree() {
        // Issue #67: triptych Re-roll / Re-prompt spends exactly 3 budget
        // calls because each sub-panel is an independent API call.
        #expect(PanelTriptych.budgetCost == 3)
    }

    @Test func budgetCostEqualsSubTargetCount() throws {
        // The "spends 3" contract is structurally true so long as `budgetCost`
        // and `subTargets.count` stay in lockstep. If a future template
        // changes triptychs to have a different fan-out, both numbers move
        // together — this guard catches a one-sided change.
        let trip = try #require(PanelTriptych.make(kind: .pIn, from: makeTemplate()))
        #expect(trip.subTargets.count == PanelTriptych.budgetCost)
    }

    // MARK: - Atomic Accept

    @Test func acceptAtomicallyWritesAllThreePanelFiles() throws {
        let (store, _) = try makeStore()
        let player = try store.create(playerName: "Alex", characterName: "", classKey: "druid")
        let trip = try #require(PanelTriptych.make(kind: .pIn, from: makeTemplate()))

        // Seed one candidate per sub-panel.
        for (n, byte) in zip([3, 4, 5], [Data([0x33]), Data([0x44]), Data([0x55])]) {
            _ = try store.savePendingCandidate(playerId: player.id,
                                               target: .panel(n),
                                               pngData: byte)
        }

        let choices: [PanelTargetID: Int] = [
            .panel(3): 0, .panel(4): 0, .panel(5): 0
        ]
        try trip.acceptAtomically(playerId: player.id, store: store, choices: choices)

        #expect(store.loadPanel(playerId: player.id, target: .panel(3)) == Data([0x33]))
        #expect(store.loadPanel(playerId: player.id, target: .panel(4)) == Data([0x44]))
        #expect(store.loadPanel(playerId: player.id, target: .panel(5)) == Data([0x55]))
    }

    @Test func acceptAtomicallyClearsAllThreeCandidateGalleries() throws {
        let (store, _) = try makeStore()
        let player = try store.create(playerName: "Alex", characterName: "", classKey: "druid")
        let trip = try #require(PanelTriptych.make(kind: .pIn, from: makeTemplate()))

        for n in [3, 4, 5] {
            // Seed two candidates per sub-panel so we can verify the gallery
            // is wiped, not just the accepted index.
            _ = try store.savePendingCandidate(playerId: player.id, target: .panel(n),
                                               pngData: Data([0xA0 | UInt8(n)]))
            _ = try store.savePendingCandidate(playerId: player.id, target: .panel(n),
                                               pngData: Data([0xB0 | UInt8(n)]))
        }
        let choices: [PanelTargetID: Int] = [
            .panel(3): 1, .panel(4): 0, .panel(5): 1
        ]
        try trip.acceptAtomically(playerId: player.id, store: store, choices: choices)

        for n in [3, 4, 5] {
            #expect(store.listCandidates(playerId: player.id, target: .panel(n)).isEmpty,
                    "panel \(n) gallery should be empty after atomic accept")
        }
    }

    @Test func acceptAtomicallyThrowsWhenAnyChoiceIsMissing() throws {
        let (store, _) = try makeStore()
        let player = try store.create(playerName: "Alex", characterName: "", classKey: "druid")
        let trip = try #require(PanelTriptych.make(kind: .pIn, from: makeTemplate()))

        for n in [3, 4, 5] {
            _ = try store.savePendingCandidate(playerId: player.id, target: .panel(n),
                                               pngData: Data([UInt8(n)]))
        }
        // Missing choice for panel 4 — must throw and write nothing.
        let choices: [PanelTargetID: Int] = [.panel(3): 0, .panel(5): 0]

        #expect(throws: PanelTriptychError.self) {
            try trip.acceptAtomically(playerId: player.id, store: store, choices: choices)
        }
        for n in [3, 4, 5] {
            #expect(store.hasPanel(playerId: player.id, target: .panel(n)) == false,
                    "panel \(n) must not have been written on rollback")
        }
    }

    @Test func acceptAtomicallyThrowsWhenAChosenCandidateIndexIsAbsent() throws {
        let (store, _) = try makeStore()
        let player = try store.create(playerName: "Alex", characterName: "", classKey: "druid")
        let trip = try #require(PanelTriptych.make(kind: .pIn, from: makeTemplate()))

        // Panel 4 has only one candidate (index 0) but we ask for index 2.
        for n in [3, 4, 5] {
            _ = try store.savePendingCandidate(playerId: player.id, target: .panel(n),
                                               pngData: Data([UInt8(n)]))
        }
        let choices: [PanelTargetID: Int] = [.panel(3): 0, .panel(4): 2, .panel(5): 0]

        #expect(throws: PanelTriptychError.self) {
            try trip.acceptAtomically(playerId: player.id, store: store, choices: choices)
        }
        for n in [3, 4, 5] {
            #expect(store.hasPanel(playerId: player.id, target: .panel(n)) == false,
                    "no panel files should land when the staging phase throws")
        }
    }

    // MARK: - Pre-display predicates

    @Test func allSubPanelsHaveCandidateIsFalseUntilEveryGalleryIsNonEmpty() throws {
        let (store, _) = try makeStore()
        let player = try store.create(playerName: "Alex", characterName: "", classKey: "druid")
        let trip = try #require(PanelTriptych.make(kind: .pIn, from: makeTemplate()))

        #expect(trip.allSubPanelsHaveCandidate(playerId: player.id, store: store) == false)
        _ = try store.savePendingCandidate(playerId: player.id, target: .panel(3),
                                           pngData: Data([0x33]))
        #expect(trip.allSubPanelsHaveCandidate(playerId: player.id, store: store) == false)
        _ = try store.savePendingCandidate(playerId: player.id, target: .panel(4),
                                           pngData: Data([0x44]))
        _ = try store.savePendingCandidate(playerId: player.id, target: .panel(5),
                                           pngData: Data([0x55]))
        #expect(trip.allSubPanelsHaveCandidate(playerId: player.id, store: store))
    }

    @Test func allSubPanelsAcceptedReflectsDisk() throws {
        let (store, _) = try makeStore()
        let player = try store.create(playerName: "Alex", characterName: "", classKey: "druid")
        let trip = try #require(PanelTriptych.make(kind: .hOut, from: makeTemplate()))

        #expect(trip.allSubPanelsAccepted(playerId: player.id, store: store) == false)
        for n in [12, 13, 14] {
            try store.savePanel(playerId: player.id, target: .panel(n),
                                pngData: Data([UInt8(n)]))
        }
        #expect(trip.allSubPanelsAccepted(playerId: player.id, store: store))
    }
}

@Suite("ReviewUnit")
struct ReviewUnitTests {

    private func makeTemplate() -> ClassTemplate {
        ClassTemplate(
            classKey: "druid",
            name: "Druid",
            costume: "leaves",
            palette: Palette(lighting: "warm", colors: "green"),
            panels: (1...15).map {
                PanelSpec(n: $0, beat: "beat \($0)", emotion: .neutral, position: .front)
            },
            cover: CoverSpec(emotion: .neutral, position: .front, poseDirective: "p")
        )
    }

    @Test func phase2UnitsCollapsesContiguousTriptychSubPanelsIntoOneUnit() {
        // Expected order for the 15-panel ADR-0007 template:
        //   panel 2, [P-in 3+4+5], panel 6, 7, 8, 9, 10, 11,
        //   [H-out 12+13+14], panel 15, cover
        // 8 single panels + 2 triptychs + cover = 11 units.
        let units = ReviewUnit.phase2Units(from: makeTemplate())
        #expect(units.count == 11)

        // P-in lands at index 1 (right after panel 2).
        if case .triptych(let trip) = units[1] {
            #expect(trip.kind == .pIn)
        } else {
            Issue.record("expected .triptych(.pIn) at index 1")
        }
        // H-out lands at index 8 (after panels 6,7,8,9,10,11).
        if case .triptych(let trip) = units[8] {
            #expect(trip.kind == .hOut)
        } else {
            Issue.record("expected .triptych(.hOut) at index 8")
        }
        // Last unit is always the cover.
        if case .single(let target) = units.last ?? .single(.cover(spec: makeTemplate().cover)) {
            #expect(target.id == .cover)
        } else {
            Issue.record("last unit should be the cover")
        }
    }

    @Test func phase2UnitsExcludesPanel1() {
        let units = ReviewUnit.phase2Units(from: makeTemplate())
        // Panel 1 must never appear in any single unit (Phase 1 owns it).
        for unit in units {
            if case .single(let t) = unit, case .panel(let n, _) = t {
                #expect(n != 1, "panel 1 must not appear in Phase 2 units")
            }
        }
    }

    @Test func phase2UnitsKeepsStoryOrder() {
        // Strict story order: panel 2 before P-in; P-in before 6,7,…11; H-out
        // before 15; 15 before cover.
        let units = ReviewUnit.phase2Units(from: makeTemplate())
        var seenP2 = false, seenPIn = false, seen11 = false, seenHOut = false, seen15 = false
        for unit in units {
            switch unit {
            case .single(let t) where t.id == .panel(2):
                #expect(!seenPIn)
                seenP2 = true
            case .triptych(let trip) where trip.kind == .pIn:
                #expect(seenP2)
                seenPIn = true
            case .single(let t) where t.id == .panel(11):
                #expect(seenPIn && !seenHOut)
                seen11 = true
            case .triptych(let trip) where trip.kind == .hOut:
                #expect(seen11)
                seenHOut = true
            case .single(let t) where t.id == .panel(15):
                #expect(seenHOut)
                seen15 = true
            case .single(let t) where t.id == .cover:
                #expect(seen15)
            default:
                break
            }
        }
    }

    // MARK: - Slice I (#69) — grid jump-to-head + completion predicate

    @Test func unitIndexForSinglePanelFindsItsOwnUnit() {
        let units = ReviewUnit.phase2Units(from: makeTemplate())
        // Panel 2 is at index 0 in Phase-2 (panel 1 is excluded).
        #expect(ReviewUnit.unitIndex(for: .panel(2), in: units) == 0)
        // Panel 6 is at index 2 (after panel 2 + P-in triptych).
        #expect(ReviewUnit.unitIndex(for: .panel(6), in: units) == 2)
        // Cover is the last unit (index 10 in an 11-unit list).
        #expect(ReviewUnit.unitIndex(for: .cover, in: units) == 10)
    }

    @Test func unitIndexForTriptychSubPanelReturnsTheTriptychUnit() {
        let units = ReviewUnit.phase2Units(from: makeTemplate())
        // P-in triptych is at index 1; any of panels 3/4/5 must map there.
        #expect(ReviewUnit.unitIndex(for: .panel(3), in: units) == 1)
        #expect(ReviewUnit.unitIndex(for: .panel(4), in: units) == 1)
        #expect(ReviewUnit.unitIndex(for: .panel(5), in: units) == 1)
        // H-out triptych is at index 8.
        #expect(ReviewUnit.unitIndex(for: .panel(12), in: units) == 8)
        #expect(ReviewUnit.unitIndex(for: .panel(14), in: units) == 8)
    }

    @Test func unitIndexForPanel1IsNilBecausePhase1OwnsIt() {
        let units = ReviewUnit.phase2Units(from: makeTemplate())
        // Panel 1 isn't a Phase-2 unit; tapping it in the grid is a no-op
        // from the swipe surface's perspective.
        #expect(ReviewUnit.unitIndex(for: .panel(1), in: units) == nil)
    }

    // MARK: - Slice I (#69) — allTerminal: drives grid auto-presentation

    private func makeStoreForTerminal() throws -> (PlayerStore, String) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("camp-comics-review-unit-terminal-\(UUID().uuidString)",
                                    isDirectory: true)
        let store = try PlayerStore(root: root)
        let player = try store.create(playerName: "Alex", characterName: "",
                                      classKey: "druid")
        return (store, player.id)
    }

    private func acceptAll(units: [ReviewUnit], playerId: String, store: PlayerStore) throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        for unit in units {
            switch unit {
            case .single(let target):
                try store.savePanel(playerId: playerId, target: target.id, pngData: png)
            case .triptych(let trip):
                for id in trip.subTargetIDs {
                    try store.savePanel(playerId: playerId, target: id, pngData: png)
                }
            }
        }
    }

    @Test func allTerminalIsFalseWhenNothingOnDisk() throws {
        let (store, playerId) = try makeStoreForTerminal()
        let units = ReviewUnit.phase2Units(from: makeTemplate())
        #expect(ReviewUnit.allTerminal(units: units, playerId: playerId, store: store) == false)
    }

    @Test func allTerminalIsTrueWhenEveryUnitAcceptedOnDisk() throws {
        let (store, playerId) = try makeStoreForTerminal()
        let units = ReviewUnit.phase2Units(from: makeTemplate())
        try acceptAll(units: units, playerId: playerId, store: store)
        #expect(ReviewUnit.allTerminal(units: units, playerId: playerId, store: store) == true)
    }

    @Test func allTerminalCountsDeferredAsResolvedForSinglePanels() throws {
        let (store, playerId) = try makeStoreForTerminal()
        let units = ReviewUnit.phase2Units(from: makeTemplate())
        // Accept everything, then delete panel 6's PNG and mark it deferred —
        // a deferred single counts as terminal per ADR-0009 failed-card recovery.
        try acceptAll(units: units, playerId: playerId, store: store)
        try store.deletePanel(playerId: playerId, target: .panel(6))
        try store.markDeferred(playerId: playerId, target: .panel(6))
        #expect(ReviewUnit.allTerminal(units: units, playerId: playerId, store: store) == true)
    }

    @Test func allTerminalRequiresEveryTriptychSubPanelResolved() throws {
        let (store, playerId) = try makeStoreForTerminal()
        let units = ReviewUnit.phase2Units(from: makeTemplate())
        // Accept everything except panel 4 (the middle of the P-in triptych).
        try acceptAll(units: units, playerId: playerId, store: store)
        try store.deletePanel(playerId: playerId, target: .panel(4))
        // With one sub-panel still pending, the triptych is not terminal.
        #expect(ReviewUnit.allTerminal(units: units, playerId: playerId, store: store) == false)
        // Defer it — now the whole triptych is terminal again (mixed
        // accepted+deferred across sub-panels is allowed; per-sub-panel
        // resolution is what matters for the completion gate).
        try store.markDeferred(playerId: playerId, target: .panel(4))
        #expect(ReviewUnit.allTerminal(units: units, playerId: playerId, store: store) == true)
    }

    // MARK: - Slice N (#95) — deck units include panel 1

    @Test func deckUnitsIncludesPanel1AsFirstSingle() {
        // Slice N: the card-deck surface mounts every reviewable unit from t=0,
        // including panel 1 (which Phase 1 owned in ADR-0009). Panel 1 is the
        // first unit so it's the top card.
        let units = ReviewUnit.deckUnits(from: makeTemplate())
        if case .single(let target) = units.first ?? .single(.cover(spec: makeTemplate().cover)) {
            #expect(target.id == .panel(1))
        } else {
            Issue.record("expected .single(.panel(1)) at index 0")
        }
    }

    @Test func deckUnitsCountIsPhase2UnitsPlusOne() {
        // Panel 1 prepended to the Phase-2 build: same triptych collapsing,
        // same story order, same cover terminator. Druid template (15 panels)
        // yields 11 Phase-2 units → 12 deck units.
        let p2 = ReviewUnit.phase2Units(from: makeTemplate())
        let deck = ReviewUnit.deckUnits(from: makeTemplate())
        #expect(deck.count == p2.count + 1)
        #expect(deck.count == 12)
    }

    @Test func deckUnitsKeepsStoryOrderAndCollapsesTriptychs() {
        let units = ReviewUnit.deckUnits(from: makeTemplate())
        // index 0: panel 1; index 1: panel 2; index 2: P-in triptych;
        // index 9: H-out triptych; last: cover.
        if case .single(let t) = units[0] { #expect(t.id == .panel(1)) }
        else { Issue.record("expected panel 1 at 0") }
        if case .single(let t) = units[1] { #expect(t.id == .panel(2)) }
        else { Issue.record("expected panel 2 at 1") }
        if case .triptych(let trip) = units[2] { #expect(trip.kind == .pIn) }
        else { Issue.record("expected P-in at 2") }
        if case .triptych(let trip) = units[9] { #expect(trip.kind == .hOut) }
        else { Issue.record("expected H-out at 9") }
        guard let last = units.last else {
            Issue.record("deck units must not be empty")
            return
        }
        if case .single(let t) = last { #expect(t.id == .cover) }
        else { Issue.record("last unit should be the cover") }
    }

    // MARK: - Slice P (#97) — empty-deck quiet completion message

    @Test func emptyDeckMessagePointsAtPersistentFinalizeToolbar() {
        // ADR-0010 "The Finalize button is persistent": when the operator has
        // worked through every card, the deck shows a quiet message that
        // routes them to the toolbar Finalize — no celebratory modal, no
        // auto-finalize. The wording is contractual; this test exists to
        // catch silent drift.
        let message = ReviewUnit.emptyDeckQuietMessage
        #expect(message == "All cards reviewed — Finalize from the toolbar.")
    }
}

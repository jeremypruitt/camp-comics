import Foundation
import Testing
@testable import CampComicsCore

@Suite("PhotoReferenceResolver")
struct PhotoReferenceResolverTests {

    private func makeStore() throws -> (PlayerStore, String) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("camp-comics-tests-\(UUID().uuidString)", isDirectory: true)
        let store = try PlayerStore(root: root)
        let player = try store.create(playerName: "Alex", characterName: "", classKey: "druid")
        return (store, player.id)
    }

    private func panel(n: Int, referencePanel: Int? = nil) -> PanelTarget {
        .panel(n: n, spec: PanelSpec(n: n, beat: "test",
                                     referencePanel: referencePanel,
                                     emotion: .neutral, position: .front))
    }

    private static let coverSpec = CoverSpec(emotion: .neutral, position: .profile,
                                             poseDirective: "heroic")

    @Test func panel1HasNoContinuity() throws {
        let (store, playerId) = try makeStore()

        let plan = PhotoReferenceResolver.references(for: panel(n: 1),
                                                     playerId: playerId,
                                                     store: store)

        #expect(plan.slots == [.photo, .hero])
        #expect(plan.outOfOrder == false)
    }

    @Test func panelNAnchorsOnPanel1WhenPanel1Accepted() throws {
        // Slice B (ADR-0009): every panel 2..15 + cover anchors on panel 1, not
        // its immediate predecessor. Drops the chained "telephone" drift.
        let (store, playerId) = try makeStore()
        try acceptPanels(playerId: playerId, store: store, ns: [1, 2])

        let plan = PhotoReferenceResolver.references(for: panel(n: 3),
                                                     playerId: playerId,
                                                     store: store)

        #expect(plan.slots == [.photo, .hero, .panel(n: 1)])
        #expect(plan.outOfOrder == false)
    }

    @Test func gapsBetweenPanel1AndNNoLongerBlockAnchor() throws {
        // Slice B (ADR-0009): the chained predecessor rule is gone, so a gap
        // between panel 1 and panel N is no longer a special case. Panel 4
        // with only 1+2 accepted still anchors on panel 1.
        let (store, playerId) = try makeStore()
        try acceptPanels(playerId: playerId, store: store, ns: [1, 2])

        let plan = PhotoReferenceResolver.references(for: panel(n: 4),
                                                     playerId: playerId,
                                                     store: store)

        #expect(plan.slots == [.photo, .hero, .panel(n: 1)])
        #expect(plan.outOfOrder == false)
    }

    @Test func unfinishedEarlierPanelTriggersOutOfOrder() throws {
        // Operator jumped to panel 7 with panels 1-6 unstarted (nothing on disk).
        let (store, playerId) = try makeStore()

        let plan = PhotoReferenceResolver.references(for: panel(n: 7),
                                                     playerId: playerId,
                                                     store: store)

        #expect(plan.slots == [.photo, .hero])
        #expect(plan.outOfOrder == true)
    }

    @Test func referencePanelOverrideHitUsesNamedPanel() throws {
        // Druid panel 12 overrides reference_panel = 1 so it chains off the
        // everyday-clothes panel instead of the most recent (panel 11, regalia).
        let (store, playerId) = try makeStore()
        try acceptPanels(playerId: playerId, store: store, ns: Array(1...11))

        let plan = PhotoReferenceResolver.references(
            for: panel(n: 12, referencePanel: 1),
            playerId: playerId,
            store: store
        )

        #expect(plan.slots == [.photo, .hero, .panel(n: 1)])
        #expect(plan.outOfOrder == false)
    }

    @Test func referencePanelOverrideMissDropsContinuityWithNoFallback() throws {
        // ADR-0002: if the named override panel doesn't exist on disk, do NOT
        // fall back to the default-rule panel — preserve YAML intent. The
        // override path wins over the out-of-order check, so the resolver
        // returns the base [photo, hero] with outOfOrder = false.
        let (store, playerId) = try makeStore()
        try acceptPanels(playerId: playerId, store: store, ns: [1, 2])

        let plan = PhotoReferenceResolver.references(
            for: panel(n: 4, referencePanel: 3),
            playerId: playerId,
            store: store
        )

        #expect(plan.slots == [.photo, .hero])
        #expect(plan.outOfOrder == false)
    }

    @Test func lateStackPanelStillAnchorsOnPanel1() throws {
        // Slice B (ADR-0009): panel 15 with only panel 1 accepted still
        // anchors on panel 1 — the batch worker pool can start any panel
        // the moment phase 1 finishes, without waiting on predecessors.
        let (store, playerId) = try makeStore()
        try acceptPanels(playerId: playerId, store: store, ns: [1])

        let plan = PhotoReferenceResolver.references(for: panel(n: 15),
                                                     playerId: playerId,
                                                     store: store)

        #expect(plan.slots == [.photo, .hero, .panel(n: 1)])
        #expect(plan.outOfOrder == false)
    }

    @Test func coverGetsPhotoAndHeroNeverContinuity() throws {
        // Slice 11b / CONTEXT.md: cover always sends [photo, hero] regardless
        // of how many panels are accepted. No continuity reference, ever — the
        // cover is a sibling artifact, not "panel 13".
        let (store, playerId) = try makeStore()
        try acceptPanels(playerId: playerId, store: store, ns: Array(1...12))

        let plan = PhotoReferenceResolver.references(for: .cover(spec: Self.coverSpec),
                                                     playerId: playerId,
                                                     store: store)

        #expect(plan.slots == [.photo, .hero])
        #expect(plan.outOfOrder == false)
    }

    private func acceptPanels(playerId: String, store: PlayerStore, ns: [Int]) throws {
        for n in ns {
            _ = try store.savePendingCandidate(playerId: playerId, target: .panel(n), pngData: Data([0xAA]))
            try store.acceptCandidate(playerId: playerId, target: .panel(n), candidateIndex: 0)
        }
    }
}

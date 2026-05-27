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

    private func spec(n: Int, referencePanel: Int? = nil) -> PanelSpec {
        PanelSpec(n: n,
                  beat: "test",
                  referencePanel: referencePanel,
                  emotion: .neutral,
                  position: .front)
    }

    @Test func panel1HasNoContinuity() throws {
        let (store, playerId) = try makeStore()

        let plan = PhotoReferenceResolver.plan(forPanel: 1,
                                               spec: spec(n: 1),
                                               playerId: playerId,
                                               store: store)

        #expect(plan.slots == [.photo, .hero])
        #expect(plan.outOfOrder == false)
    }

    @Test func inOrderPanelChainsOffMostRecentAccepted() throws {
        let (store, playerId) = try makeStore()
        try acceptPanels(playerId: playerId, store: store, ns: [1, 2])

        let plan = PhotoReferenceResolver.plan(forPanel: 3,
                                               spec: spec(n: 3),
                                               playerId: playerId,
                                               store: store)

        #expect(plan.slots == [.photo, .hero, .panel(n: 2)])
        #expect(plan.outOfOrder == false)
    }

    @Test func gapInAcceptanceTriggersOutOfOrder() throws {
        // Slice 11a: with Skip gone, an unfinalized earlier panel is always
        // genuinely out-of-order. Panel 4 with 1+2 accepted but 3 unfinished
        // can't chain — the resolver drops to [photo, hero] + flag.
        let (store, playerId) = try makeStore()
        try acceptPanels(playerId: playerId, store: store, ns: [1, 2])

        let plan = PhotoReferenceResolver.plan(forPanel: 4,
                                               spec: spec(n: 4),
                                               playerId: playerId,
                                               store: store)

        #expect(plan.slots == [.photo, .hero])
        #expect(plan.outOfOrder == true)
    }

    @Test func unfinishedEarlierPanelTriggersOutOfOrder() throws {
        // Operator jumped to panel 7 with panels 1-6 unstarted (nothing on disk).
        let (store, playerId) = try makeStore()

        let plan = PhotoReferenceResolver.plan(forPanel: 7,
                                               spec: spec(n: 7),
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

        let plan = PhotoReferenceResolver.plan(forPanel: 12,
                                               spec: spec(n: 12, referencePanel: 1),
                                               playerId: playerId,
                                               store: store)

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

        let plan = PhotoReferenceResolver.plan(forPanel: 4,
                                               spec: spec(n: 4, referencePanel: 3),
                                               playerId: playerId,
                                               store: store)

        #expect(plan.slots == [.photo, .hero])
        #expect(plan.outOfOrder == false)
    }

    @Test func multiGapAcceptanceStillTriggersOutOfOrder() throws {
        // Slice 11a: without Skip, panels 4 and 5 being unfinished is genuine
        // out-of-order. The chip fires; no continuity panel is substituted.
        let (store, playerId) = try makeStore()
        try acceptPanels(playerId: playerId, store: store, ns: [1, 2, 3])

        let plan = PhotoReferenceResolver.plan(forPanel: 6,
                                               spec: spec(n: 6),
                                               playerId: playerId,
                                               store: store)

        #expect(plan.slots == [.photo, .hero])
        #expect(plan.outOfOrder == true)
    }

    private func acceptPanels(playerId: String, store: PlayerStore, ns: [Int]) throws {
        for n in ns {
            _ = try store.savePendingCandidate(playerId: playerId, n: n, pngData: Data([0xAA]))
            try store.acceptCandidate(playerId: playerId, n: n, candidateIndex: 0)
        }
    }
}

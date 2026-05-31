import Foundation
import Testing
@testable import CampComicsCore

@Suite("Panel1CascadeWarning")
struct Panel1CascadeWarningTests {

    private func makeStore() throws -> (PlayerStore, PlayerRecord) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("camp-comics-tests-\(UUID().uuidString)", isDirectory: true)
        let store = try PlayerStore(root: root)
        let player = try store.create(playerName: "Alex", characterName: "", classKey: "druid")
        return (store, player)
    }

    // MARK: - shouldWarn

    @Test func indexZeroNeverWarns() throws {
        // Accepting candidate index 0 commits the demoted prior bytes back to
        // panel_01.png — bytes unchanged, no cascade exposure even if every
        // downstream is on disk.
        let (store, player) = try makeStore()
        for n in 2...15 {
            _ = try store.savePendingCandidate(playerId: player.id, target: .panel(n), pngData: Data([0x01]))
            try store.acceptCandidate(playerId: player.id, target: .panel(n), candidateIndex: 0)
        }
        #expect(Panel1CascadeWarning.shouldWarn(playerId: player.id,
                                                acceptingCandidateIndex: 0,
                                                store: store,
                                                panelCount: 15) == false)
    }

    @Test func noDownstreamAcceptedNeverWarns() throws {
        // Phase 1 first-time accept: no panels 2..N exist on disk yet.
        let (store, player) = try makeStore()
        #expect(Panel1CascadeWarning.shouldWarn(playerId: player.id,
                                                acceptingCandidateIndex: 1,
                                                store: store,
                                                panelCount: 15) == false)
    }

    @Test func oneDownstreamPanelAcceptedWarns() throws {
        let (store, player) = try makeStore()
        _ = try store.savePendingCandidate(playerId: player.id, target: .panel(5), pngData: Data([0x05]))
        try store.acceptCandidate(playerId: player.id, target: .panel(5), candidateIndex: 0)
        #expect(Panel1CascadeWarning.shouldWarn(playerId: player.id,
                                                acceptingCandidateIndex: 1,
                                                store: store,
                                                panelCount: 15))
    }

    @Test func coverAcceptedAloneWarns() throws {
        let (store, player) = try makeStore()
        _ = try store.savePendingCandidate(playerId: player.id, target: .cover, pngData: Data([0xCC]))
        try store.acceptCandidate(playerId: player.id, target: .cover, candidateIndex: 0)
        #expect(Panel1CascadeWarning.shouldWarn(playerId: player.id,
                                                acceptingCandidateIndex: 1,
                                                store: store,
                                                panelCount: 15))
    }

    @Test func onlyPanel1AcceptedDoesNotWarn() throws {
        // Panel 1 alone is not "downstream of itself"; this is the post-Phase-1
        // pre-Phase-2 moment.
        let (store, player) = try makeStore()
        _ = try store.savePendingCandidate(playerId: player.id, target: .panel(1), pngData: Data([0x01]))
        try store.acceptCandidate(playerId: player.id, target: .panel(1), candidateIndex: 0)
        #expect(Panel1CascadeWarning.shouldWarn(playerId: player.id,
                                                acceptingCandidateIndex: 1,
                                                store: store,
                                                panelCount: 15) == false)
    }

    @Test func reRollAfterDownstreamWarnsAtIndexOne() throws {
        // Canonical case: panel 1 accepted, panels 2..4 accepted, operator
        // re-rolls panel 1 (demote → new candidate at index 1) and Accepts the
        // new one.
        let (store, player) = try makeStore()
        _ = try store.savePendingCandidate(playerId: player.id, target: .panel(1), pngData: Data([0x01]))
        try store.acceptCandidate(playerId: player.id, target: .panel(1), candidateIndex: 0)
        for n in 2...4 {
            _ = try store.savePendingCandidate(playerId: player.id, target: .panel(n), pngData: Data([UInt8(n)]))
            try store.acceptCandidate(playerId: player.id, target: .panel(n), candidateIndex: 0)
        }
        try store.demoteAcceptedToCandidate(playerId: player.id, target: .panel(1))
        let fresh = try store.savePendingCandidate(playerId: player.id, target: .panel(1), pngData: Data([0xFF]))
        #expect(fresh.index == 1)
        #expect(Panel1CascadeWarning.shouldWarn(playerId: player.id,
                                                acceptingCandidateIndex: fresh.index,
                                                store: store,
                                                panelCount: 15))
    }

    // MARK: - hasAnyDownstreamAccepted

    @Test func hasAnyDownstreamAcceptedIgnoresPanel1() throws {
        let (store, player) = try makeStore()
        _ = try store.savePendingCandidate(playerId: player.id, target: .panel(1), pngData: Data([0x01]))
        try store.acceptCandidate(playerId: player.id, target: .panel(1), candidateIndex: 0)
        #expect(Panel1CascadeWarning.hasAnyDownstreamAccepted(playerId: player.id,
                                                              store: store,
                                                              panelCount: 15) == false)
    }

    @Test func hasAnyDownstreamAcceptedDetectsCover() throws {
        let (store, player) = try makeStore()
        _ = try store.savePendingCandidate(playerId: player.id, target: .cover, pngData: Data([0xCC]))
        try store.acceptCandidate(playerId: player.id, target: .cover, candidateIndex: 0)
        #expect(Panel1CascadeWarning.hasAnyDownstreamAccepted(playerId: player.id,
                                                              store: store,
                                                              panelCount: 15))
    }

    @Test func hasAnyDownstreamAcceptedScansAllPanels() throws {
        let (store, player) = try makeStore()
        _ = try store.savePendingCandidate(playerId: player.id, target: .panel(15), pngData: Data([0x0F]))
        try store.acceptCandidate(playerId: player.id, target: .panel(15), candidateIndex: 0)
        #expect(Panel1CascadeWarning.hasAnyDownstreamAccepted(playerId: player.id,
                                                              store: store,
                                                              panelCount: 15))
    }

    @Test func hasAnyDownstreamAcceptedHandlesSmallPanelCounts() throws {
        // Pathological: a template with only panel 1. panelCount=1 means the
        // 2...panelCount range is empty; only the cover can warn.
        let (store, player) = try makeStore()
        #expect(Panel1CascadeWarning.hasAnyDownstreamAccepted(playerId: player.id,
                                                              store: store,
                                                              panelCount: 1) == false)
        _ = try store.savePendingCandidate(playerId: player.id, target: .cover, pngData: Data([0xCC]))
        try store.acceptCandidate(playerId: player.id, target: .cover, candidateIndex: 0)
        #expect(Panel1CascadeWarning.hasAnyDownstreamAccepted(playerId: player.id,
                                                              store: store,
                                                              panelCount: 1))
    }
}

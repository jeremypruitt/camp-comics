import Foundation
import Testing
@testable import CampComicsCore

@Suite("PanelReviewState")
struct PanelReviewStateMachineTests {

    @Test func newReviewStartsUnstarted() {
        let state = PanelReviewState()

        #expect(state.phase == .unstarted)
    }

    @Test func startGenerationMovesUnstartedToGenerating() {
        var state = PanelReviewState()

        state.startGeneration()

        #expect(state.phase == .generating)
    }

    @Test func candidateReceivedMovesGeneratingToReviewing() {
        var state = PanelReviewState()
        state.startGeneration()

        state.candidateReceived()

        #expect(state.phase == .reviewing)
    }

    @Test func cancelFromFirstAttemptReturnsToUnstarted() {
        var state = PanelReviewState()
        state.startGeneration()

        state.cancelGeneration()

        #expect(state.phase == .unstarted)
    }

    @Test func cancelFromReRollReturnsToReviewing() {
        // After at least one candidate is in the gallery, re-roll fires a fresh
        // generation. Canceling that one must drop back to Reviewing, not erase
        // the gallery the operator already built up.
        var state = PanelReviewState()
        state.startGeneration()
        state.candidateReceived()
        state.startGeneration()

        state.cancelGeneration()

        #expect(state.phase == .reviewing)
    }

    @Test func acceptMovesReviewingToAccepted() {
        var state = PanelReviewState()
        state.startGeneration()
        state.candidateReceived()

        state.accept()

        #expect(state.phase == .accepted)
    }

    @Test func skipFromUnstartedMovesToSkipped() {
        var state = PanelReviewState()

        state.skip()

        #expect(state.phase == .skipped)
    }

    @Test func skipFromReviewingMovesToSkipped() {
        // Operator generated candidates but decided to skip the slot anyway.
        var state = PanelReviewState()
        state.startGeneration()
        state.candidateReceived()

        state.skip()

        #expect(state.phase == .skipped)
    }

    @Test func markThrottledFromGeneratingHoldsAtThrottled() {
        // Vertex 429 during generation. Recovery (auto-retry once, then operator
        // tap) lands in slice 13 — for now the state machine just holds here.
        var state = PanelReviewState()
        state.startGeneration()

        state.markThrottled()

        #expect(state.phase == .throttled)
    }

    @Test func markFailedFromGeneratingCarriesMessage() {
        var state = PanelReviewState()
        state.startGeneration()

        state.markFailed(message: "Network unreachable")

        #expect(state.phase == .failed(message: "Network unreachable"))
    }

    @Test func markMissingPhotoFromUnstartedHoldsAtMissingPhoto() {
        var state = PanelReviewState()

        state.markMissingPhoto()

        #expect(state.phase == .missingPhoto)
    }

    @Test func hydrateFromDiskPrefersCandidatesOverStaleSkipMarker() throws {
        // Issue #12: when a skipped panel is Re-generated, the _skipped_NN
        // marker stays on disk alongside the fresh candidate. Hydrate must
        // treat the candidate as the more recent intent — without this, the
        // panel snaps back to .skipped after the operator navigates away.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("camp-comics-hydrate-\(UUID().uuidString)", isDirectory: true)
        let store = try PlayerStore(root: tmp)
        let player = try store.create(playerName: "Alex", characterName: "", classKey: "druid")
        try store.markSkipped(playerId: player.id, n: 3)
        _ = try store.savePendingCandidate(playerId: player.id, n: 3, pngData: Data([0xAB]))

        let state = PanelReviewState.hydrate(playerId: player.id, n: 3, store: store)

        #expect(state.phase == .reviewing)
    }

    @Test func hydrateReturnsSkippedWhenOnlySkipMarkerExists() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("camp-comics-hydrate-\(UUID().uuidString)", isDirectory: true)
        let store = try PlayerStore(root: tmp)
        let player = try store.create(playerName: "Alex", characterName: "", classKey: "druid")
        try store.markSkipped(playerId: player.id, n: 6)

        let state = PanelReviewState.hydrate(playerId: player.id, n: 6, store: store)

        #expect(state.phase == .skipped)
    }
}

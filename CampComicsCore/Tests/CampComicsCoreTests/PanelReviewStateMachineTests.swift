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

    @Test func firstThrottleFromGeneratingMarksAutoRetryPending() {
        // First Vertex 429 in this generation cycle. The state machine grants
        // the one-shot auto-retry budget; the view layer reads pending=true and
        // schedules the retry. Distinct from the held-throttled case below.
        var state = PanelReviewState()
        state.startGeneration()

        state.markThrottled()

        #expect(state.phase == .throttled(autoRetryPending: true))
    }

    @Test func autoRetryBudgetResetsAfterCandidateReceived() {
        // First gen throttled → auto-retried → succeeded. The operator now
        // re-rolls and is throttled again. That's a new generation cycle, so
        // it should get its own auto-retry budget (pending=true), not inherit
        // the prior consumed state.
        var state = PanelReviewState()
        state.startGeneration()
        state.markThrottled()
        state.startGeneration()
        state.candidateReceived()
        state.startGeneration()   // re-roll

        state.markThrottled()

        #expect(state.phase == .throttled(autoRetryPending: true))
    }

    @Test func secondThrottleAfterAutoRetryHoldsForOperator() {
        // The view auto-retried once after the first throttle (autoRetry()),
        // and Vertex 429d again. The budget is spent — the SM must now hold
        // with pending=false so the UI shows Retry.
        var state = PanelReviewState()
        state.startGeneration()
        state.markThrottled()
        state.autoRetry()           // system-initiated retry; preserves budget

        state.markThrottled()

        #expect(state.phase == .throttled(autoRetryPending: false))
    }

    @Test func operatorRetryFromHeldThrottledRefreshesBudget() {
        // Operator tapped Retry on a held-throttled panel. That's a deliberate
        // new attempt cycle (startGeneration, not autoRetry), so the next 429
        // should auto-retry again (pending=true), not hold immediately.
        var state = PanelReviewState()
        state.startGeneration()
        state.markThrottled()       // pending true
        state.autoRetry()
        state.markThrottled()       // pending false — held
        state.startGeneration()     // operator Retry refreshes budget

        state.markThrottled()

        #expect(state.phase == .throttled(autoRetryPending: true))
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

    @Test func markUnstartedFromMissingPhotoMovesToUnstarted() {
        // After the operator captures the missing reference photo via the
        // deep-link sheet, the view tells the SM the photo is now on disk so
        // it can re-fire generation. This is the explicit recovery transition.
        var state = PanelReviewState()
        state.markMissingPhoto()

        state.markUnstarted()

        #expect(state.phase == .unstarted)
    }

    @Test func hydrateReturnsReviewingWhenCandidatesPresent() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("camp-comics-hydrate-\(UUID().uuidString)", isDirectory: true)
        let store = try PlayerStore(root: tmp)
        let player = try store.create(playerName: "Alex", characterName: "", classKey: "druid")
        _ = try store.savePendingCandidate(playerId: player.id, target: .panel(3),
                                           pngData: Data([0xAB]))

        let state = PanelReviewState.hydrate(playerId: player.id, target: .panel(3),
                                             store: store)

        #expect(state.phase == .reviewing)
    }

    @Test func hydrateReturnsUnstartedWhenNothingOnDisk() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("camp-comics-hydrate-\(UUID().uuidString)", isDirectory: true)
        let store = try PlayerStore(root: tmp)
        let player = try store.create(playerName: "Alex", characterName: "", classKey: "druid")

        let state = PanelReviewState.hydrate(playerId: player.id, target: .panel(6),
                                             store: store)

        #expect(state.phase == .unstarted)
    }

    @Test func hydrateRecognizesAcceptedCover() throws {
        // Slice 11b: hydrate is target-shaped, so a saved cover.png surfaces
        // as `.accepted` just like a panel does.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("camp-comics-hydrate-\(UUID().uuidString)", isDirectory: true)
        let store = try PlayerStore(root: tmp)
        let player = try store.create(playerName: "Alex", characterName: "", classKey: "druid")
        try store.savePanel(playerId: player.id, target: .cover, pngData: Data([0xC0]))

        let state = PanelReviewState.hydrate(playerId: player.id, target: .cover,
                                             store: store)

        #expect(state.phase == .accepted)
    }
}

import Foundation
import Testing
@testable import CampComicsCore

@Suite("SponsoredTrial value math")
struct SponsoredTrialValueTests {

    @Test func emptyHasFullRemaining() {
        let trial = SponsoredTrial.empty

        #expect(trial.remaining == SponsoredTrial.limit)
        #expect(trial.remaining == 2)
        #expect(trial.isExhausted == false)
    }

    @Test func containsUnknownPlayerIsFalse() {
        let trial = SponsoredTrial.empty

        #expect(trial.contains("player_001") == false)
    }

    @Test func exhaustsAtLimit() {
        let trial = SponsoredTrial(finalizedPlayerIds: ["player_001", "player_002"])

        #expect(trial.remaining == 0)
        #expect(trial.isExhausted)
    }

    @Test func remainingClampsAtZero() {
        let trial = SponsoredTrial(finalizedPlayerIds: ["a", "b", "c"])

        #expect(trial.remaining == 0)
    }
}

@Suite("SponsoredTrialBackend round-trip")
struct SponsoredTrialBackendTests {

    @Test func recordedPlayerAppearsInFetch() async throws {
        let backend = InMemorySponsoredTrialBackend()

        try await backend.recordFinalized(playerId: "player_001")
        let trial = try await backend.fetch()

        #expect(trial.finalizedPlayerIds == ["player_001"])
        #expect(trial.remaining == 1)
    }

    @Test func multipleDistinctRecordsAccumulate() async throws {
        let backend = InMemorySponsoredTrialBackend()

        try await backend.recordFinalized(playerId: "player_001")
        try await backend.recordFinalized(playerId: "player_002")
        let trial = try await backend.fetch()

        #expect(trial.finalizedPlayerIds == ["player_001", "player_002"])
        #expect(trial.isExhausted)
    }

    // Mirrors Firestore arrayUnion semantics — the backend must be
    // idempotent so a re-export of the same player doesn't double-decrement.
    @Test func repeatedRecordIsIdempotent() async throws {
        let backend = InMemorySponsoredTrialBackend()

        try await backend.recordFinalized(playerId: "player_001")
        try await backend.recordFinalized(playerId: "player_001")
        let trial = try await backend.fetch()

        #expect(trial.finalizedPlayerIds == ["player_001"])
        #expect(trial.remaining == 1)
    }
}

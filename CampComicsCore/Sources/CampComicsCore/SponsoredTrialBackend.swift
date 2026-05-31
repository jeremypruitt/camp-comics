import Foundation

public protocol SponsoredTrialBackend: Sendable {
    func fetch() async throws -> SponsoredTrial
    func recordFinalized(playerId: String) async throws
    /// ADR-0009 shifts the trial-decrement moment from PDF-finalize to
    /// "Start campaign" — the operator commits one trial unit at the CTA, not
    /// at the end. The default impl routes through `recordFinalized` so the
    /// disk/Firestore semantics stay identical (idempotent Set insert); a
    /// follow-up Start→PDF round trip on the same player is a no-op.
    func spend(playerId: String) async throws
}

extension SponsoredTrialBackend {
    public func spend(playerId: String) async throws {
        try await recordFinalized(playerId: playerId)
    }
}

public actor InMemorySponsoredTrialBackend: SponsoredTrialBackend {
    private var ids: Set<String>

    public init(initial: Set<String> = []) {
        self.ids = initial
    }

    public func fetch() async throws -> SponsoredTrial {
        SponsoredTrial(finalizedPlayerIds: ids)
    }

    public func recordFinalized(playerId: String) async throws {
        ids.insert(playerId)
    }
}

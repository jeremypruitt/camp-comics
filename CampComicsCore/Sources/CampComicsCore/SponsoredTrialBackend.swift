import Foundation

public protocol SponsoredTrialBackend: Sendable {
    func fetch() async throws -> SponsoredTrial
    func recordFinalized(playerId: String) async throws
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

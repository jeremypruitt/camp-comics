import Foundation

public struct SponsoredTrial: Equatable, Sendable {
    public static let limit = 2
    public static let empty = SponsoredTrial(finalizedPlayerIds: [])

    public let finalizedPlayerIds: Set<String>

    public init(finalizedPlayerIds: Set<String>) {
        self.finalizedPlayerIds = finalizedPlayerIds
    }

    public var remaining: Int {
        max(0, Self.limit - finalizedPlayerIds.count)
    }

    public var isExhausted: Bool {
        remaining == 0
    }

    public func contains(_ playerId: String) -> Bool {
        finalizedPlayerIds.contains(playerId)
    }
}

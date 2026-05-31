import Foundation

/// Per-comic budget for `gemini-2.5-flash-image` calls under `BillingMode.sponsored`.
/// Caps Jeremy's worst-case sponsored spend at `limit × ~$0.04` (~$1.25). See
/// ADR-0008. QA-gate calls are exempt by virtue of going through
/// `PanelGenerator.generateQAPanel`; only `generatePanel` decrements.
public struct GenerationBudget: Equatable, Codable, Sendable {
    public static let limit = 32
    public static let empty = GenerationBudget(spent: 0)

    public let spent: Int

    public init(spent: Int) {
        self.spent = spent
    }

    public var remaining: Int {
        max(0, Self.limit - spent)
    }

    public var isExhausted: Bool {
        remaining == 0
    }

    public func decremented() -> GenerationBudget {
        GenerationBudget(spent: spent + 1)
    }
}

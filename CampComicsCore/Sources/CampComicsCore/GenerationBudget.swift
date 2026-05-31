import Foundation

/// Per-comic budget for `gemini-2.5-flash-image` calls under `BillingMode.sponsored`.
/// `limit = (panelCount + 1) × 2` — template-dynamic per ADR-0009, so a 15-panel
/// template caps at 32 and a future 9-panel template caps at 20. Caps Jeremy's
/// worst-case sponsored spend at `limit × ~$0.04`. See ADR-0008. QA-gate calls
/// are exempt by virtue of going through `PanelGenerator.generateQAPanel`; only
/// `generatePanel` decrements.
public struct GenerationBudget: Equatable, Codable, Sendable {
    public let spent: Int
    public let limit: Int

    public init(spent: Int, panelCount: Int) {
        self.spent = spent
        self.limit = Self.limit(panelCount: panelCount)
    }

    /// Direct init for persistence round-tripping. Keep `panelCount`-based init
    /// as the primary call site.
    public init(spent: Int, limit: Int) {
        self.spent = spent
        self.limit = limit
    }

    public static func empty(panelCount: Int) -> GenerationBudget {
        GenerationBudget(spent: 0, panelCount: panelCount)
    }

    public static func limit(panelCount: Int) -> Int {
        (panelCount + 1) * 2
    }

    public var remaining: Int {
        max(0, limit - spent)
    }

    public var isExhausted: Bool {
        remaining == 0
    }

    public func decremented() -> GenerationBudget {
        GenerationBudget(spent: spent + 1, limit: limit)
    }
}

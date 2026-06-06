import Foundation

/// One line in the per-comic budget audit log (#90 instrumentation). Each
/// `gemini-2.5-flash-image` decrement writes a `spend`; each soft-block and
/// 4th-re-roll friction confirm writes a `bounce`/`friction`. Purely a
/// diagnostic artifact — logging is additive and changes no budget behavior.
/// Persisted as a pretty JSON array at `players/NNN/panels/_budget_log.json`,
/// matching the `attemptsState` house style.
public struct BudgetLogEntry: Codable, Equatable, Sendable {
    public enum Event: String, Codable, Sendable {
        /// A budget decrement that actually fired a generation call.
        case spend
        /// A swipe-right blocked by the budget soft-block (`remaining < cost`).
        /// The key "is 32 too thin?" signal — one bounce = one unmet re-roll.
        case bounce
        /// A 4th-or-later re-roll on one card surfaced the friction confirm.
        case friction
    }

    public enum Reason: String, Codable, Sendable {
        /// Panel-1 sequential bootstrap.
        case bootstrap
        /// Initial 2–15 + cover fan-out via the queue worker.
        case initial
        /// Operator swipe-right re-roll (single or one triptych sub-panel).
        case reroll
        /// Stuck-card tap-to-retry.
        case stuckRetry
    }

    public let timestamp: Date
    public let event: Event
    public let reason: Reason
    public let target: String
    public let spentAfter: Int
    public let remainingAfter: Int
    public let cost: Int

    public init(timestamp: Date,
                event: Event,
                reason: Reason,
                target: String,
                spentAfter: Int,
                remainingAfter: Int,
                cost: Int) {
        self.timestamp = timestamp
        self.event = event
        self.reason = reason
        self.target = target
        self.spentAfter = spentAfter
        self.remainingAfter = remainingAfter
        self.cost = cost
    }
}

import Foundation

/// Per-card re-roll tally for `ReviewDeckView` (ADR-0010, slice O / issue #96).
/// Lives in memory for the duration of the deck session — by design not
/// persisted. The counter keys are opaque strings derived from each
/// `ReviewUnit` so triptychs share one counter across their three sub-panels
/// (matches the unit-level re-roll cost of 3).
public struct RerollCounter: Sendable {
    private var counts: [String: Int] = [:]

    public init() {}

    public func count(unitId: String) -> Int {
        counts[unitId] ?? 0
    }

    public mutating func increment(unitId: String) {
        counts[unitId, default: 0] += 1
    }
}

/// Routes a swipe-right (re-roll) gesture through the two ADR-0010 gates:
/// budget soft-block at `remaining == 0` (silent bounce, no modal) and the
/// per-card 4th-re-roll friction confirm. `cost` is the budget the re-roll
/// would spend — 1 for a single panel, 3 for a triptych unit.
public enum RerollDecision: Equatable, Sendable {
    /// Budget can't cover the cost. Bounce the swipe silently with a haptic;
    /// no API call, no modal. Per ADR-0010 this is the *new* exhaustion UX.
    case bounce
    /// Proceed with the re-roll. Caller spends budget + fires generation.
    case fire
    /// 4th-or-later re-roll on this same unit during this deck session.
    /// Caller surfaces a one-question confirm; confirming fires, cancel no-ops.
    case requireConfirm
}

public enum RerollDecider {
    /// Re-rolls beyond this prior count surface the friction confirm. `3` means
    /// the 4th attempt (priorRerolls == 3) is the first one that confirms.
    public static let frictionPriorThreshold: Int = 3

    public static func decide(remaining: Int,
                              cost: Int,
                              priorRerolls: Int) -> RerollDecision {
        if remaining < cost { return .bounce }
        if priorRerolls >= frictionPriorThreshold { return .requireConfirm }
        return .fire
    }
}

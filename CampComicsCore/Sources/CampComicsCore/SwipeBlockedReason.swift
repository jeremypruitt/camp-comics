import Foundation

/// Why a swipe-right gesture on the head deck card was dropped without firing
/// a re-roll. Issue #117 — every silently-bounced swipe should surface a
/// stamped banner explaining itself; this enum is what the banner reads from.
///
/// The 4th-re-roll friction confirm (`RerollDecision.requireConfirm`) is NOT
/// a blocked swipe — it opens an alert. So `evaluate` returns nil in that case.
public enum SwipeBlockedReason: Equatable, Sendable {
    /// `GenerationBudget.remaining < cost`. Banner: "OUT OF REROLLS".
    case outOfRerolls
    /// A previous re-roll task is still in flight. Banner: "STILL ROLLING…".
    case stillRolling
    /// The head unit is stuck — no candidate exists yet, so there's nothing
    /// to re-roll FROM. Banner: "NO CANDIDATE YET".
    case noCandidateYet

    public var bannerCopy: String {
        switch self {
        case .outOfRerolls:  return "OUT OF REROLLS"
        case .stillRolling:  return "STILL ROLLING…"
        case .noCandidateYet: return "NO CANDIDATE YET"
        }
    }

    public static func evaluate(rerollDecision: RerollDecision,
                                isRerollInFlight: Bool,
                                isTopStuck: Bool) -> SwipeBlockedReason? {
        // Stuck branch mirrors the gesture handler's ordering: a stuck head
        // bypasses RerollDecider entirely because there's no candidate to
        // re-roll FROM.
        if isTopStuck { return .noCandidateYet }
        if rerollDecision == .bounce { return .outOfRerolls }
        if isRerollInFlight { return .stillRolling }
        return nil
    }
}

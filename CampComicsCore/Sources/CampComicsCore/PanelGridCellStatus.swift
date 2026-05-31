import Foundation

/// Disk-derived per-target status used by the slice-11d grid overlay. A
/// *snapshot* of every target's state on sheet open — it can't observe
/// runtime-only phases like `.generating` or `.throttled` that live only
/// inside an active session. Five cases below are exactly the states a fresh
/// `PlayerStore` inspection can prove from disk; `.failed` (slice H) is the
/// persisted deferred-failure marker from ADR-0009's failed-card recovery
/// path.
public enum PanelGridCellStatus: Equatable, Sendable {
    case unstarted
    case reviewing
    case accepted
    case missingPhoto
    case failed

    /// Priority: accepted winner on disk wins over everything (a successful
    /// retry-and-accept supersedes any stale deferred state); the `.failed`
    /// sentinel beats lingering candidates because Defer is an explicit
    /// operator decision; candidates beat a missing photo; absence of the
    /// photo flags the operator to deep-link into capture.
    public static func derive(target: PanelTarget,
                              playerId: String,
                              store: PlayerStore) -> PanelGridCellStatus {
        if store.hasPanel(playerId: playerId, target: target.id) {
            return .accepted
        }
        if store.isDeferred(playerId: playerId, target: target.id) {
            return .failed
        }
        if !store.listCandidates(playerId: playerId, target: target.id).isEmpty {
            return .reviewing
        }
        if store.loadPhoto(playerId: playerId, requirement: target.requirement) == nil {
            return .missingPhoto
        }
        return .unstarted
    }
}

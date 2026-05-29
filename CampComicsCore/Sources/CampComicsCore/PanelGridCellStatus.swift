import Foundation

/// Disk-derived per-target status used by the slice-11d grid overlay. Distinct
/// from `PanelReviewState.Phase` because the grid is a *snapshot* of every
/// target's state on sheet open — it can't observe runtime-only phases like
/// `.generating`, `.throttled`, or `.failed` that live only inside an active
/// `PanelReviewView` session. The four cases below are exactly the states a
/// fresh `PlayerStore` inspection can prove from disk.
public enum PanelGridCellStatus: Equatable, Sendable {
    case unstarted
    case reviewing
    case accepted
    case missingPhoto

    /// Priority: accepted winner on disk wins over candidates; candidates win
    /// over a missing reference photo; absence of the photo flags the operator
    /// to deep-link into capture before the loop can advance.
    public static func derive(target: PanelTarget,
                              playerId: String,
                              store: PlayerStore) -> PanelGridCellStatus {
        if store.hasPanel(playerId: playerId, target: target.id) {
            return .accepted
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

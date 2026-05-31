import Foundation

/// Cascade-warning predicate from ADR-0009 (slice J / #70). Re-rolling panel 1
/// after downstream panels have been accepted leaves them anchored on the OLD
/// panel 1 — every panel 2..N + cover uses `panel_01.png` as its continuity
/// reference (slice B / #62). Accepting a NEW panel-1 candidate while any
/// downstream is already accepted is the moment we warn the operator that the
/// new look won't auto-propagate.
///
/// Warn-only by design: no auto-cascade. Re-generating downstream panels would
/// burn budget without operator consent and might overwrite work they were
/// happy with. The operator picks what to re-roll from the grid (slice I).
///
/// "Differs from prior" check is via candidate index. `demoteAcceptedToCandidate`
/// always puts the prior winner at index 0; a fresh re-roll candidate lands at
/// index 1+. Accepting index 0 is therefore a no-op (committing the prior bytes
/// back to `panel_01.png`) and never warns.
public enum Panel1CascadeWarning {

    /// Returns true iff accepting `acceptingCandidateIndex` for `.panel(1)`
    /// should fire the warn-only confirm. Pure — derives its answer from disk
    /// via `store.hasPanel` for panels 2..panelCount and the cover.
    ///
    /// - Parameters:
    ///   - playerId: player whose panel-1 Accept is about to commit.
    ///   - acceptingCandidateIndex: index in `_candidates/01/`. Index 0 is the
    ///     demoted prior winner (or the only candidate on a first-time Accept);
    ///     index > 0 is necessarily a new candidate.
    ///   - store: read-only view of the player's panels directory.
    ///   - panelCount: total panel count in the active template (15 for the
    ///     bookend-triptych templates; old field copies were 12).
    public static func shouldWarn(playerId: String,
                                  acceptingCandidateIndex: Int,
                                  store: PlayerStore,
                                  panelCount: Int) -> Bool {
        // Index 0 = prior winner re-accepted; bytes unchanged so no cascade
        // exposure. Skip the disk scan entirely.
        guard acceptingCandidateIndex > 0 else { return false }
        return hasAnyDownstreamAccepted(playerId: playerId,
                                        store: store,
                                        panelCount: panelCount)
    }

    /// Additive helper on top of `PlayerStore.hasPanel` — true if ANY of panels
    /// 2..panelCount or the cover is already accepted on disk. Exposed so other
    /// surfaces (e.g. the slice-I grid) can reuse without re-deriving.
    public static func hasAnyDownstreamAccepted(playerId: String,
                                                store: PlayerStore,
                                                panelCount: Int) -> Bool {
        if store.hasPanel(playerId: playerId, target: .cover) { return true }
        guard panelCount >= 2 else { return false }
        for n in 2...panelCount {
            if store.hasPanel(playerId: playerId, target: .panel(n)) { return true }
        }
        return false
    }
}

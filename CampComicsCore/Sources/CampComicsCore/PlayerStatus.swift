import Foundation

/// Disk-derived summary of a player's progress through the panel-generation
/// loop, used by the player-list state pills. Pure derivation — deleting a
/// `panel_NN.png` from Documents moves a `.done` player back to `.generating`
/// on next recomputation. Counts are over `template.panels.count` (12 today;
/// 13 once slice 11 lands cover).
public enum PlayerStatus: Equatable, Sendable {
    case captured
    case generating(done: Int, total: Int)
    case done
    case needsPhoto

    public static func derive(playerId: String,
                              template: ClassTemplate,
                              store: PlayerStore) -> PlayerStatus {
        let total = template.panels.count
        var done = 0
        let captured = store.capturedRequirements(playerId: playerId)
        var needsPhoto = false
        for panel in template.panels {
            if store.hasPanel(playerId: playerId, n: panel.n) {
                done += 1
            } else if !captured.contains(panel.requirement) {
                needsPhoto = true
            }
        }
        if needsPhoto {
            return .needsPhoto
        }
        if done == total {
            return .done
        }
        if done > 0 {
            return .generating(done: done, total: total)
        }
        return .captured
    }
}

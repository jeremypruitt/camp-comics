import Foundation

/// Disk-derived summary of a player's progress through the generation loop,
/// used by the player-list state pills. Pure derivation — deleting a
/// `panel_NN.png` or `cover.png` from Documents moves a `.done` player back to
/// `.generating` on next recomputation. Total is `template.panels.count + 1`
/// (12 panels + the cover sibling, slice 11b).
public enum PlayerStatus: Equatable, Sendable {
    case captured
    case generating(done: Int, total: Int)
    case done
    case needsPhoto

    public static func derive(playerId: String,
                              template: ClassTemplate,
                              store: PlayerStore) -> PlayerStatus {
        let total = template.panels.count + 1
        var done = 0
        let captured = store.capturedRequirements(playerId: playerId)
        var needsPhoto = false
        for panel in template.panels {
            if store.hasPanel(playerId: playerId, target: .panel(panel.n)) {
                done += 1
            } else if !captured.contains(panel.requirement) {
                needsPhoto = true
            }
        }
        if store.hasPanel(playerId: playerId, target: .cover) {
            done += 1
        } else if !captured.contains(template.cover.requirement) {
            needsPhoto = true
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

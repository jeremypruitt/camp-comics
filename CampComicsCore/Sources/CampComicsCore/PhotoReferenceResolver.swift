import Foundation

/// One reference slot in a panel generation call. The caller materialises each
/// case to bytes: `.photo` → the player's source photo, `.hero` → the class
/// hero card, `.panel(n:)` → the on-disk accepted `panel_NN.png`.
public enum ReferenceSlot: Equatable, Sendable {
    case photo
    case hero
    case panel(n: Int)
}

/// What references to send Vertex for one panel generation, plus the
/// out-of-order flag the UI uses to show the
/// "Continuity reference: none — earlier panels not yet approved" chip.
public struct ReferencePlan: Equatable, Sendable {
    public let slots: [ReferenceSlot]
    public let outOfOrder: Bool

    public init(slots: [ReferenceSlot], outOfOrder: Bool) {
        self.slots = slots
        self.outOfOrder = outOfOrder
    }
}

/// Resolves the reference list for one generation call. Pure given a
/// `PlayerStore` snapshot: re-reading after on-disk state changes is the
/// caller's responsibility.
///
/// Rules (CONTEXT.md + ADR-0002 + project_panel_loop_design.md #8):
/// - Cover: `[photo, hero]` always (no continuity, never out-of-order).
/// - Panel 1: `[photo, hero]`.
/// - Any earlier panel not yet accepted → out-of-order; slots = `[photo, hero]`.
/// - `spec.referencePanel = M` override hits → `[photo, hero, .panel(M)]`.
/// - `spec.referencePanel = M` override misses → `[photo, hero]` with no
///   substitute (ADR-0002 — preserve YAML intent).
/// - Otherwise → `[photo, hero, .panel(M)]` for the largest `m < n` with an
///   accepted image.
public enum PhotoReferenceResolver {

    public static func references(for target: PanelTarget,
                                  playerId: String,
                                  store: PlayerStore) -> ReferencePlan {
        switch target {
        case .cover:
            return ReferencePlan(slots: [.photo, .hero], outOfOrder: false)
        case .panel(let n, let spec):
            return panelPlan(n: n, spec: spec, playerId: playerId, store: store)
        }
    }

    private static func panelPlan(n: Int,
                                  spec: PanelSpec,
                                  playerId: String,
                                  store: PlayerStore) -> ReferencePlan {
        if n <= 1 {
            return ReferencePlan(slots: [.photo, .hero], outOfOrder: false)
        }
        if let override = spec.referencePanel {
            // ADR-0002: override miss → no continuity, no fallback. Override
            // also wins over the out-of-order check because the YAML pinned the
            // specific reference; if that reference is on disk, use it.
            if store.hasPanel(playerId: playerId, target: .panel(override)) {
                return ReferencePlan(slots: [.photo, .hero, .panel(n: override)],
                                     outOfOrder: false)
            }
            return ReferencePlan(slots: [.photo, .hero], outOfOrder: false)
        }
        if anyEarlierUnfinished(before: n, playerId: playerId, store: store) {
            return ReferencePlan(slots: [.photo, .hero], outOfOrder: true)
        }
        if let m = mostRecentAcceptedPriorTo(n: n, playerId: playerId, store: store) {
            return ReferencePlan(slots: [.photo, .hero, .panel(n: m)], outOfOrder: false)
        }
        return ReferencePlan(slots: [.photo, .hero], outOfOrder: false)
    }

    private static func anyEarlierUnfinished(before n: Int,
                                             playerId: String,
                                             store: PlayerStore) -> Bool {
        for m in 1..<n {
            if !store.hasPanel(playerId: playerId, target: .panel(m)) { return true }
        }
        return false
    }

    private static func mostRecentAcceptedPriorTo(n: Int,
                                                  playerId: String,
                                                  store: PlayerStore) -> Int? {
        for m in stride(from: n - 1, through: 1, by: -1) {
            if store.hasPanel(playerId: playerId, target: .panel(m)) {
                return m
            }
        }
        return nil
    }
}

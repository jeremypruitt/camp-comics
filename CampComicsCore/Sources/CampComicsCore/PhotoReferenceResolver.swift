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
/// Rules (CONTEXT.md + ADR-0009 supersedes ADR-0002 chained rule):
/// - Cover: `[photo, hero]` always (no continuity, never out-of-order).
/// - Panel 1: `[photo, hero]`.
/// - Panel N ≥ 2, panel 1 accepted → `[photo, hero, .panel(1)]`. Anchoring on
///   panel 1 (not the chained predecessor) is the load-bearing simplification
///   that lets the batch worker pool run without artificial sequencing.
/// - Panel N ≥ 2, panel 1 absent → `[photo, hero]`, `outOfOrder = true`.
/// - `spec.referencePanel = M` override hits → `[photo, hero, .panel(M)]`.
/// - `spec.referencePanel = M` override misses → `[photo, hero]` with no
///   substitute (ADR-0002 escape hatch — preserve YAML intent).
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
            if store.hasPanel(playerId: playerId, target: .panel(override)) {
                return ReferencePlan(slots: [.photo, .hero, .panel(n: override)],
                                     outOfOrder: false)
            }
            return ReferencePlan(slots: [.photo, .hero], outOfOrder: false)
        }
        if store.hasPanel(playerId: playerId, target: .panel(1)) {
            return ReferencePlan(slots: [.photo, .hero, .panel(n: 1)], outOfOrder: false)
        }
        return ReferencePlan(slots: [.photo, .hero], outOfOrder: true)
    }
}

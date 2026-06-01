import Foundation

/// Slice G (#67). Phase-2 review-surface grouping for ADR-0007's two transition
/// triptychs: P-in (panels 3–5) and H-out (panels 12–14). Each triptych is one
/// reviewable unit — the operator Accepts / Re-rolls / Re-prompts all three
/// sub-panels atomically.
///
/// **Not a `PanelTarget` variant.** Generation, persistence, the prompt builder,
/// and the print layout all keep operating on per-panel `PanelTarget.panel(n)`
/// for the six sub-panel slots; the triptych is purely a Phase-2 review-surface
/// concept that groups three sub-targets into one card. This keeps the queue
/// (which dispatches in story order) and the on-disk layout (which writes
/// `panel_03.png … panel_14.png`) unchanged from slices A–F.
///
/// Atomicity is enforced at the moment of Accept (`acceptAtomically` writes all
/// three `panel_NN.png` files in one pass after verifying every chosen
/// candidate is readable from disk) and at the moment of Re-roll / Re-prompt
/// (the caller spawns three concurrent `runOneAppendingCandidate` tasks and
/// renders the card in `.placeholder` state until every sub-panel has a fresh
/// candidate). Re-roll and Re-prompt each spend exactly **3** budget calls
/// because each sub-panel is an independent API call — bookend-middle-bookend
/// are not composable into one model request.
public struct PanelTriptych: Equatable, Sendable {

    /// Which of ADR-0007's two transition triptychs this is. `pIn` is the
    /// page-2 P-in (panels 3–5, parallelogram middle + trapezoid bookends);
    /// `hOut` is the page-4 H-out (panels 12–14, hexagonal diamond-middle +
    /// pentagon bookends).
    public enum Kind: Sendable, Equatable {
        case pIn
        case hOut

        /// Story-ordered sub-panel numbers (left, middle, right).
        public var subPanelNumbers: [Int] {
            switch self {
            case .pIn: return [3, 4, 5]
            case .hOut: return [12, 13, 14]
            }
        }

        public static let pInRange: ClosedRange<Int> = 3...5
        public static let hOutRange: ClosedRange<Int> = 12...14

        /// Maps a panel number to the triptych it belongs to, or nil if the
        /// panel is a standalone single-panel slot.
        public static func containing(panelNumber n: Int) -> Kind? {
            if pInRange.contains(n) { return .pIn }
            if hOutRange.contains(n) { return .hOut }
            return nil
        }
    }

    public let kind: Kind
    /// Always 3 elements, ordered left/middle/right per `Kind.subPanelNumbers`.
    /// Each is a `.panel(n:spec:)` — triptychs never contain the cover.
    public let subTargets: [PanelTarget]

    public init(kind: Kind, subTargets: [PanelTarget]) {
        precondition(subTargets.count == 3,
                     "PanelTriptych always has exactly 3 sub-panels")
        self.kind = kind
        self.subTargets = subTargets
    }

    /// Build a `PanelTriptych` from a template by pulling the three sub-panels
    /// for `kind`. Returns nil if the template is missing any of them (e.g. a
    /// non-bookend template that doesn't have panel 4).
    public static func make(kind: Kind, from template: ClassTemplate) -> PanelTriptych? {
        let wanted = kind.subPanelNumbers
        let matched = wanted.compactMap { n -> PanelTarget? in
            guard let spec = template.panels.first(where: { $0.n == n }) else { return nil }
            return .panel(n: n, spec: spec)
        }
        guard matched.count == wanted.count else { return nil }
        return PanelTriptych(kind: kind, subTargets: matched)
    }

    /// Per-Re-roll / per-Re-prompt budget cost. ADR-0009 + issue #67 AC pin
    /// this at 3 because each sub-panel is an independent model call.
    public static let budgetCost: Int = 3

    /// IDs of the three sub-panels, ordered left/middle/right. Used by the
    /// Phase-2 surface to subscribe to per-sub-panel completion events from
    /// `GenerationQueue` and to address candidates in `PlayerStore`.
    public var subTargetIDs: [PanelTargetID] {
        subTargets.map { $0.id }
    }

    /// True iff every sub-panel has at least one candidate in its gallery —
    /// the precondition for showing the composited triptych card in the head
    /// (rather than the placeholder spinner).
    public func allSubPanelsHaveCandidate(playerId: String, store: PlayerStore) -> Bool {
        subTargetIDs.allSatisfy { id in
            !store.listCandidates(playerId: playerId, target: id).isEmpty
                || store.hasPanel(playerId: playerId, target: id)
        }
    }

    /// True iff every sub-panel is already accepted (`panel_NN.png` exists).
    /// Used by the head iterator to advance past a triptych whose sub-panels
    /// were accepted in a prior session.
    public func allSubPanelsAccepted(playerId: String, store: PlayerStore) -> Bool {
        subTargetIDs.allSatisfy { id in
            store.hasPanel(playerId: playerId, target: id)
        }
    }

    /// Atomic Accept (issue #67 AC: "writes panel_03.png, panel_04.png,
    /// panel_05.png in one transaction"). Reads every chosen candidate's bytes
    /// into memory first; if any read fails the whole call throws and no
    /// `panel_NN.png` files are written, so the operator's prior state is
    /// preserved. Once all three reads succeed we write all three accepted
    /// files and then clear the candidate galleries.
    ///
    /// `choices` maps each sub-panel ID to the candidate index that should be
    /// promoted (the one the operator was viewing on the head card). Missing
    /// entries throw — partial acceptance is the failure mode the ADR
    /// explicitly rejects.
    public func acceptAtomically(playerId: String,
                                 store: PlayerStore,
                                 choices: [PanelTargetID: Int]) throws {
        // Phase 1: gather bytes for every sub-panel before writing anything.
        // If any sub-panel's chosen candidate file is unreadable, we throw
        // here and the on-disk state is untouched.
        var staged: [(PanelTargetID, Data)] = []
        for id in subTargetIDs {
            guard let chosen = choices[id] else {
                throw PanelTriptychError.missingChoice(id)
            }
            let candidates = store.listCandidates(playerId: playerId, target: id)
            guard let candidate = candidates.first(where: { $0.index == chosen }) else {
                throw PanelTriptychError.candidateNotFound(id, chosen)
            }
            let data = try Data(contentsOf: candidate.url)
            staged.append((id, data))
        }
        // Phase 2: commit. `savePanel` overwrites atomically (write-options
        // `.atomic`) and `clearCandidates` is wiped via `acceptCandidate`'s
        // helper-equivalent path — we use `savePanel` then per-target clear.
        for (id, data) in staged {
            try store.savePanel(playerId: playerId, target: id, pngData: data)
        }
        for id in subTargetIDs {
            try store.clearCandidates(playerId: playerId, target: id)
        }
    }
}

public enum PanelTriptychError: Error, Equatable {
    case missingChoice(PanelTargetID)
    case candidateNotFound(PanelTargetID, Int)
}

/// One reviewable unit at the head of the Phase-2 stack. The stack iterator
/// walks `[ReviewUnit]`, collapsing P-in and H-out's contiguous sub-panels
/// into a single `.triptych` so the operator sees one super-card per ADR-0007.
public enum ReviewUnit: Equatable, Sendable {
    case single(PanelTarget)
    case triptych(PanelTriptych)

    /// Slice I (#69): true when every unit has reached a terminal disk state —
    /// either accepted (`panel_NN.png` on disk) or deferred (`.failed`
    /// sentinel). For triptychs every sub-panel must be individually resolved;
    /// mixed accepted+deferred across sub-panels is allowed. Drives the grid
    /// sheet's auto-presentation: when the last unaccepted unit lands in a
    /// terminal state, the operator gets the grid + Generate-PDF CTA without
    /// having to hunt for the toolbar.
    public static func allTerminal(units: [ReviewUnit],
                                   playerId: String,
                                   store: PlayerStore) -> Bool {
        units.allSatisfy { unit in
            switch unit {
            case .single(let target):
                return store.hasPanel(playerId: playerId, target: target.id)
                    || store.isDeferred(playerId: playerId, target: target.id)
            case .triptych(let trip):
                return trip.subTargetIDs.allSatisfy { id in
                    store.hasPanel(playerId: playerId, target: id)
                        || store.isDeferred(playerId: playerId, target: id)
                }
            }
        }
    }

    /// Slice I (#69): index of the unit containing `targetID`, or nil if the
    /// id isn't owned by any Phase-2 unit (e.g. panel 1, which Phase 1 owns).
    /// Drives jump-to-panel from the grid: the operator taps a cell, we look
    /// up its unit, and the stack head re-positions to that index.
    public static func unitIndex(for targetID: PanelTargetID,
                                 in units: [ReviewUnit]) -> Int? {
        for (i, unit) in units.enumerated() {
            switch unit {
            case .single(let target):
                if target.id == targetID { return i }
            case .triptych(let trip):
                if trip.subTargetIDs.contains(targetID) { return i }
            }
        }
        return nil
    }

    /// Slice O (#96): stable per-unit identity for the in-memory re-roll
    /// counter. Singles key off the on-disk panel/cover name so the counter
    /// survives view-redraws; triptychs share one counter across their three
    /// sub-panels because the unit re-rolls atomically.
    public var frictionKey: String {
        switch self {
        case .single(let target): return target.diskName
        case .triptych(let trip):
            switch trip.kind {
            case .pIn: return "triptych_pIn"
            case .hOut: return "triptych_hOut"
            }
        }
    }

    /// Slice N (#95): card-deck variant — same story-ordered build as
    /// `phase2Units`, but panel 1 is included as the first `.single` so it can
    /// be the top card of the deck from t=0. ADR-0010 supersedes ADR-0009's
    /// Phase 1 / Phase 2 split, so the deck mounts everything together.
    public static func deckUnits(from template: ClassTemplate) -> [ReviewUnit] {
        var units: [ReviewUnit] = []
        if let panel1 = template.panels.first(where: { $0.n == 1 }) {
            units.append(.single(.panel(n: 1, spec: panel1)))
        }
        units.append(contentsOf: phase2Units(from: template))
        return units
    }

    /// Story-ordered build: panels 2..N then cover, with the two triptychs
    /// collapsed into single units. Panel 1 is excluded (Phase 1 owns it).
    public static func phase2Units(from template: ClassTemplate) -> [ReviewUnit] {
        let sortedPanels = template.panels
            .filter { $0.n != 1 }
            .sorted { $0.n < $1.n }
        var units: [ReviewUnit] = []
        var emittedPIn = false
        var emittedHOut = false
        for panel in sortedPanels {
            switch PanelTriptych.Kind.containing(panelNumber: panel.n) {
            case .pIn:
                if !emittedPIn, let trip = PanelTriptych.make(kind: .pIn, from: template) {
                    units.append(.triptych(trip))
                    emittedPIn = true
                }
            case .hOut:
                if !emittedHOut, let trip = PanelTriptych.make(kind: .hOut, from: template) {
                    units.append(.triptych(trip))
                    emittedHOut = true
                }
            case .none:
                units.append(.single(.panel(n: panel.n, spec: panel)))
            }
        }
        units.append(.single(.cover(spec: template.cover)))
        return units
    }
}

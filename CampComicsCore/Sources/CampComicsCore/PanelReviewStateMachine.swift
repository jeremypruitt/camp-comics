import Foundation

/// Drives one panel's review surface through the 7-state lifecycle from
/// ADR-0003 (amended 2026-05-27 to drop Skipped):
///
///   Unstarted → Generating → (Reviewing | Throttled | Failed)
///   Reviewing → (Accepted | Generating  /* re-roll */)
///   Unstarted → MissingPhoto
///   Generating → prior  (cancel)
public struct PanelReviewState: Equatable, Sendable {

    public enum Phase: Equatable, Sendable {
        case unstarted
        case generating
        case reviewing
        case accepted
        /// `autoRetryPending == true` is the first 429 in this generation cycle
        /// — the view should countdown + auto-retry once. `false` means the
        /// one-shot budget was already spent; operator must tap Retry.
        case throttled(autoRetryPending: Bool)
        case failed(message: String)
        case missingPhoto
    }

    public private(set) var phase: Phase

    /// Phase to restore on `cancelGeneration`. Set when entering `.generating`
    /// from `.unstarted` (first try) or `.reviewing` (re-roll); cleared on any
    /// non-cancel exit from `.generating`.
    private var priorToGenerating: Phase?

    /// One-shot auto-retry budget for Throttled. Set when the first 429 in a
    /// generation cycle fires; the next 429 (after the view auto-retried) sees
    /// it set and emits `.throttled(autoRetryPending: false)` to wait for the
    /// operator. Cleared by terminal transitions and `candidateReceived()`.
    private var autoRetryConsumed: Bool = false

    public init(phase: Phase = .unstarted) {
        self.phase = phase
    }

    public mutating func startGeneration() {
        priorToGenerating = phase
        phase = .generating
        autoRetryConsumed = false
    }

    /// System-initiated retry from `.throttled(autoRetryPending: true)`. Unlike
    /// `startGeneration`, this preserves the consumed-budget flag so a second
    /// 429 in the same cycle holds for the operator. Cancel from here drops to
    /// `.unstarted` (no priorToGenerating set) so we don't re-enter the auto-
    /// retry loop on cancel.
    public mutating func autoRetry() {
        priorToGenerating = nil
        phase = .generating
    }

    public mutating func candidateReceived() {
        phase = .reviewing
        priorToGenerating = nil
        autoRetryConsumed = false
    }

    public mutating func cancelGeneration() {
        phase = priorToGenerating ?? .unstarted
        priorToGenerating = nil
    }

    public mutating func accept() {
        phase = .accepted
    }

    public mutating func markThrottled() {
        let pending = !autoRetryConsumed
        autoRetryConsumed = true
        phase = .throttled(autoRetryPending: pending)
        priorToGenerating = nil
    }

    public mutating func markFailed(message: String) {
        phase = .failed(message: message)
        priorToGenerating = nil
    }

    public mutating func markMissingPhoto() {
        phase = .missingPhoto
    }

    /// Recovery transition from `.missingPhoto` after the operator captured the
    /// missing reference photo via the deep-link sheet. The view layer then
    /// re-fires generation. Caller-side responsibility to confirm the photo is
    /// actually on disk before invoking — the SM is pure.
    public mutating func markUnstarted() {
        phase = .unstarted
    }

    /// Disk-derived initial state for a panel slot, used on view entry and
    /// after navigation. Priority: `hasPanel` (accepted winner exists) →
    /// candidates present (live review session) → `.unstarted`. Legacy
    /// `_skipped_NN` markers on disk are inert post-slice-11a.
    public static func hydrate(playerId: String, n: Int, store: PlayerStore) -> PanelReviewState {
        if store.hasPanel(playerId: playerId, n: n) {
            return PanelReviewState(phase: .accepted)
        }
        if !store.listCandidates(playerId: playerId, n: n).isEmpty {
            return PanelReviewState(phase: .reviewing)
        }
        return PanelReviewState(phase: .unstarted)
    }
}

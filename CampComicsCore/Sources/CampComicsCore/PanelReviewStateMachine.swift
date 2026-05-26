import Foundation

/// Drives one panel's review surface through the 8-state lifecycle from
/// `project_panel_loop_design.md` decision #7 and ADR-0003:
///
///   Unstarted → Generating → (Reviewing | Throttled | Failed)
///   Reviewing → (Accepted | Skipped | Generating  /* re-roll */)
///   Unstarted → (Skipped | MissingPhoto)
///   Generating → prior  (cancel)
///
/// Slice 9 implements the happy path + cancel-during-generating. Throttled,
/// Failed, and MissingPhoto are reachable but their recovery affordances
/// (auto-retry, deep-link to capture flow) land in slice 13.
public struct PanelReviewState: Equatable, Sendable {

    public enum Phase: Equatable, Sendable {
        case unstarted
        case generating
        case reviewing
        case accepted
        case skipped
        case throttled
        case failed(message: String)
        case missingPhoto
    }

    public private(set) var phase: Phase

    /// Phase to restore on `cancelGeneration`. Set when entering `.generating`
    /// from `.unstarted` (first try) or `.reviewing` (re-roll); cleared on any
    /// non-cancel exit from `.generating`.
    private var priorToGenerating: Phase?

    public init(phase: Phase = .unstarted) {
        self.phase = phase
    }

    public mutating func startGeneration() {
        priorToGenerating = phase
        phase = .generating
    }

    public mutating func candidateReceived() {
        phase = .reviewing
        priorToGenerating = nil
    }

    public mutating func cancelGeneration() {
        phase = priorToGenerating ?? .unstarted
        priorToGenerating = nil
    }

    public mutating func accept() {
        phase = .accepted
    }

    public mutating func skip() {
        phase = .skipped
    }

    public mutating func markThrottled() {
        phase = .throttled
        priorToGenerating = nil
    }

    public mutating func markFailed(message: String) {
        phase = .failed(message: message)
        priorToGenerating = nil
    }

    public mutating func markMissingPhoto() {
        phase = .missingPhoto
    }
}

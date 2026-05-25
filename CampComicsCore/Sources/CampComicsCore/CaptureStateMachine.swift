import Foundation

/// One photo the user has captured for a specific (emotion, position) requirement.
/// The state machine only tracks *that* a requirement was satisfied and *when* —
/// the actual image bytes/URL live in the UI/storage layer keyed off `id`.
public struct CapturedPhoto: Equatable, Hashable, Sendable {
    public let id: UUID
    public let capturedAt: Date

    public init(id: UUID = UUID(), capturedAt: Date = Date()) {
        self.id = id
        self.capturedAt = capturedAt
    }
}

/// Drives the Variant B checklist: tracks which (emotion, position) shots have
/// been captured against an immutable plan. UI reads `isReadyToSubmit` to gate
/// the submit button and `capturedPhoto(for:)` to decide whether each row shows
/// a thumbnail or a placeholder.
public struct CaptureState: Equatable, Sendable {
    public let plan: [PanelRequirement]
    private var captures: [PanelRequirement: CapturedPhoto]

    public init(plan: [PanelRequirement]) {
        self.plan = plan
        self.captures = [:]
    }

    /// Every plan requirement has a captured photo.
    public var isReadyToSubmit: Bool {
        captures.count == plan.count
    }

    /// How many plan rows still need a photo.
    public var remainingCount: Int {
        plan.count - captures.count
    }

    /// How many plan rows already have a photo.
    public var capturedCount: Int {
        captures.count
    }

    /// Plan requirements that have not yet been captured, in plan order.
    public var remaining: [PanelRequirement] {
        plan.filter { captures[$0] == nil }
    }

    public func capturedPhoto(for requirement: PanelRequirement) -> CapturedPhoto? {
        captures[requirement]
    }

    public func isCaptured(_ requirement: PanelRequirement) -> Bool {
        captures[requirement] != nil
    }

    /// Record a new capture for a requirement. Replaces any existing capture for
    /// the same requirement (the natural retake-then-recapture sequence collapses
    /// to a single `record` call). Traps if the requirement isn't in the plan —
    /// that's a programmer error, not a runtime condition.
    public mutating func record(_ photo: CapturedPhoto, for requirement: PanelRequirement) {
        precondition(plan.contains(requirement),
                     "record(for:) called with requirement \(requirement) that is not in the current plan")
        captures[requirement] = photo
    }

    /// Drop the capture for a requirement so the user can re-shoot. No-op if
    /// there isn't one yet. Returns the discarded photo so the UI/storage layer
    /// can clean up its corresponding image data.
    @discardableResult
    public mutating func retake(_ requirement: PanelRequirement) -> CapturedPhoto? {
        captures.removeValue(forKey: requirement)
    }
}

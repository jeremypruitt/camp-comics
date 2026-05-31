import Foundation

/// Pure value type that tracks "which candidate in this panel's gallery is the
/// review card currently showing", driving slice-E swipe-up / swipe-down cycle
/// + the dot indicator + the "N of M" position label. The cursor lives in view
/// state — never persisted — and resets when the head advances to the next
/// panel. The on-disk gallery is the source of truth for the candidate list;
/// `GalleryCursor` is just an `Int` and a `count` plus the cycle arithmetic.
///
/// Cycle direction follows the gesture: swipe-up advances forward (older →
/// newer), swipe-down advances backward (newer → older). Wraps at both ends so
/// "1 of 3" → swipe-down → "3 of 3". Wrapping was preferred over clamping so a
/// 2-candidate gallery feels symmetric: swipe-up + swipe-down land in the same
/// place.
///
/// Slice E also requires that the newly-appended re-roll candidate becomes the
/// visible one — `.afterAppend(count:)` snaps the cursor to the last index
/// (newest), matching the ADR-0009 "newest on top" rule.
public struct GalleryCursor: Equatable, Sendable {
    public let index: Int
    public let count: Int

    public init(index: Int, count: Int) {
        precondition(count >= 0, "GalleryCursor count must be ≥ 0")
        if count == 0 {
            self.index = 0
        } else {
            self.index = ((index % count) + count) % count
        }
        self.count = count
    }

    /// "N of M" label, 1-indexed for humans. Returns ("0", "0") when empty so
    /// callers can branch on `count == 0` if they want to hide the label.
    public var positionLabel: String {
        guard count > 0 else { return "0 of 0" }
        return "\(index + 1) of \(count)"
    }

    public var isEmpty: Bool { count == 0 }

    /// Swipe-up — advance forward (older → newer). Wraps.
    public func advanced() -> GalleryCursor {
        GalleryCursor(index: index + 1, count: count)
    }

    /// Swipe-down — advance backward (newer → older). Wraps.
    public func retreated() -> GalleryCursor {
        GalleryCursor(index: index - 1, count: count)
    }

    /// Called immediately after a re-roll candidate lands on disk: the cursor
    /// jumps to the last (newest) index. The newly appended candidate's index
    /// is `count - 1` because indices are dense.
    public static func afterAppend(count: Int) -> GalleryCursor {
        precondition(count > 0, "afterAppend requires at least one candidate")
        return GalleryCursor(index: count - 1, count: count)
    }

    /// Called when the head advances to a new panel: cursor resets to 0 so the
    /// operator sees that panel's first candidate. Empty gallery is legal here
    /// (panel still in flight).
    public static func forNewHead(count: Int) -> GalleryCursor {
        GalleryCursor(index: 0, count: count)
    }
}

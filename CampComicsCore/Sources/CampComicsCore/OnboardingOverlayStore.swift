import Foundation

/// First-launch flag for the swipe-review tutorial overlay (ADR-0009 Slice K;
/// gestures inverted in ADR-0010 Slice S). The overlay auto-presents the first
/// time an operator lands on `ReviewDeckView`, then sets `hasSeen = true` and
/// never auto-shows again. Settings → "Show review tutorial" flips it back to
/// false to re-summon on next deck mount.
public struct OnboardingOverlayStore: @unchecked Sendable {
    public static let defaultsKey = "hasSeenReviewTutorial"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var hasSeen: Bool {
        get { defaults.bool(forKey: Self.defaultsKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.defaultsKey) }
    }
}

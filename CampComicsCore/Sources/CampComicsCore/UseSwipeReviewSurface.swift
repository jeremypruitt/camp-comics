import Foundation

/// Feature flag gating the ADR-0009 swipe-review surface. Off by default so the
/// legacy `PanelReviewView` keeps owning the review path until slice L (#72)
/// tears it down. Both surfaces coexist behind this flag through slices D–K —
/// without the flag, the partial swipe surface collides with `PanelReviewView`
/// state and corrupts candidate galleries.
public struct UseSwipeReviewSurfaceStore: @unchecked Sendable {
    public static let defaultsKey = "useSwipeReviewSurface"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var isEnabled: Bool {
        get { defaults.bool(forKey: Self.defaultsKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.defaultsKey) }
    }
}

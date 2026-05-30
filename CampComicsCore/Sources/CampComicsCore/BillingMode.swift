import Foundation

public enum BillingMode: String, Sendable, CaseIterable {
    case sponsored
    case byo
}

public struct BillingModeStore: @unchecked Sendable {
    public static let defaultsKey = "billingMode"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var current: BillingMode {
        get {
            guard let raw = defaults.string(forKey: Self.defaultsKey),
                  let mode = BillingMode(rawValue: raw) else {
                return .sponsored
            }
            return mode
        }
        nonmutating set {
            defaults.set(newValue.rawValue, forKey: Self.defaultsKey)
        }
    }
}

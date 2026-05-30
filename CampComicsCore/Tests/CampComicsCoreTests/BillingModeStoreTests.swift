import Foundation
import Testing
@testable import CampComicsCore

@Suite("BillingModeStore")
struct BillingModeStoreTests {

    private func makeIsolatedDefaults() -> UserDefaults {
        let suite = "BillingModeStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func defaultIsSponsoredWhenUnset() {
        let store = BillingModeStore(defaults: makeIsolatedDefaults())

        #expect(store.current == .sponsored)
    }

    @Test func writeRoundTripsAcrossInstances() {
        let defaults = makeIsolatedDefaults()
        let writer = BillingModeStore(defaults: defaults)
        writer.current = .byo

        let reader = BillingModeStore(defaults: defaults)

        #expect(reader.current == .byo)
    }

    @Test func unknownRawValueFallsBackToSponsored() {
        let defaults = makeIsolatedDefaults()
        defaults.set("vertex", forKey: BillingModeStore.defaultsKey)

        let store = BillingModeStore(defaults: defaults)

        #expect(store.current == .sponsored)
    }
}

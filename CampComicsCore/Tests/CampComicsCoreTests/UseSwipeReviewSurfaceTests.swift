import Foundation
import Testing
@testable import CampComicsCore

@Suite("UseSwipeReviewSurfaceStore")
struct UseSwipeReviewSurfaceStoreTests {

    private func makeIsolatedDefaults() -> UserDefaults {
        let suite = "UseSwipeReviewSurfaceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func defaultIsOffWhenUnset() {
        let store = UseSwipeReviewSurfaceStore(defaults: makeIsolatedDefaults())

        #expect(store.isEnabled == false)
    }

    @Test func writeRoundTripsAcrossInstances() {
        let defaults = makeIsolatedDefaults()
        let writer = UseSwipeReviewSurfaceStore(defaults: defaults)
        writer.isEnabled = true

        let reader = UseSwipeReviewSurfaceStore(defaults: defaults)

        #expect(reader.isEnabled == true)
    }

    @Test func flipBackToFalseRoundTrips() {
        let defaults = makeIsolatedDefaults()
        let store = UseSwipeReviewSurfaceStore(defaults: defaults)
        store.isEnabled = true
        store.isEnabled = false

        #expect(UseSwipeReviewSurfaceStore(defaults: defaults).isEnabled == false)
    }
}

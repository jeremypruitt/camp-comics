import Foundation
import Testing
@testable import CampComicsCore

@Suite("OnboardingOverlayStore")
struct OnboardingOverlayStoreTests {

    private func makeIsolatedDefaults() -> UserDefaults {
        let suite = "OnboardingOverlayStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func defaultIsUnseenWhenUnset() {
        let store = OnboardingOverlayStore(defaults: makeIsolatedDefaults())

        #expect(store.hasSeen == false)
    }

    @Test func markingSeenRoundTripsAcrossInstances() {
        let defaults = makeIsolatedDefaults()
        let writer = OnboardingOverlayStore(defaults: defaults)
        writer.hasSeen = true

        let reader = OnboardingOverlayStore(defaults: defaults)

        #expect(reader.hasSeen == true)
    }

    @Test func flipBackToUnseenRoundTrips() {
        let defaults = makeIsolatedDefaults()
        let store = OnboardingOverlayStore(defaults: defaults)
        store.hasSeen = true
        store.hasSeen = false

        #expect(OnboardingOverlayStore(defaults: defaults).hasSeen == false)
    }

    @Test func defaultsKeyIsStableAndDocumented() {
        // Slice L (#72) clears this key on legacy-teardown; keep it stable.
        #expect(OnboardingOverlayStore.defaultsKey == "hasSeenReviewTutorial")
    }
}

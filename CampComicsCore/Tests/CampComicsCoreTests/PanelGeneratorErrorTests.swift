import Foundation
import Testing
@testable import CampComicsCore

@Suite("PanelGeneratorError")
struct PanelGeneratorErrorTests {

    @Test func parseRetryAfterFromGoogleProtobufRetryDelay() {
        // RESOURCE_EXHAUSTED responses from Vertex include a RetryInfo
        // protobuf rendered into the error description as `retryDelay { ... }`.
        let raw = "RESOURCE_EXHAUSTED: quota exceeded; retryDelay { seconds: 16 } for project foo"

        let parsed = PanelGeneratorError.parseRetryAfterSeconds(from: raw)

        #expect(parsed == 16)
    }

    @Test func parseRetryAfterFromHttpHeaderEcho() {
        // Some upstream errors surface the raw HTTP header in the description.
        let raw = "Request failed (429). Retry-After: 30. Try again later."

        let parsed = PanelGeneratorError.parseRetryAfterSeconds(from: raw)

        #expect(parsed == 30)
    }

    @Test func parseRetryAfterReturnsNilWhenAbsent() {
        // Falls back to a UI-level default when Vertex doesn't include retry info.
        let raw = "RESOURCE_EXHAUSTED: quota exceeded for project foo"

        let parsed = PanelGeneratorError.parseRetryAfterSeconds(from: raw)

        #expect(parsed == nil)
    }
}

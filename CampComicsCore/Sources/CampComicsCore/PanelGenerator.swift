import Foundation

public enum PanelGeneratorError: Error, Equatable, Sendable {
    case noImageReturned
    /// Vertex 429 / RESOURCE_EXHAUSTED. `retryAfterSeconds` is parsed from the
    /// underlying RetryInfo if present; nil means the UI should fall back to
    /// a constant default. Drives the throttled-state countdown in the swipe
    /// surface.
    case throttled(retryAfterSeconds: TimeInterval?)
    case underlying(String)

    /// Pull a retry-delay-in-seconds out of an opaque Vertex/Firebase error
    /// description. Handles two shapes observed in practice:
    ///   • protobuf RetryInfo rendered as `retryDelay { seconds: N }`
    ///   • HTTP-style `Retry-After: N` header echoed into the message body.
    /// Returns nil when neither shape matches — the caller falls back to a
    /// constant default.
    public static func parseRetryAfterSeconds(from raw: String) -> TimeInterval? {
        let patterns = [
            #"retryDelay\s*\{\s*seconds:\s*(\d+)"#,
            #"(?i)Retry-After:\s*(\d+)"#
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: raw,
                                            range: NSRange(raw.startIndex..., in: raw)),
               match.numberOfRanges >= 2,
               let range = Range(match.range(at: 1), in: raw),
               let seconds = TimeInterval(raw[range]) {
                return seconds
            }
        }
        return nil
    }
}

public struct ImageReference: Sendable {
    public let data: Data
    public let mimeType: String   // "image/jpeg" | "image/png"

    public init(data: Data, mimeType: String) {
        self.data = data
        self.mimeType = mimeType
    }
}

public protocol PanelGenerator: Sendable {
    func generateQAPanel(prompt: String, photo: Data) async throws -> Data
    func generatePanel(prompt: String, references: [ImageReference]) async throws -> Data
}

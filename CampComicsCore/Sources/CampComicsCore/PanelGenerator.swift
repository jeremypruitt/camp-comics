import Foundation

public enum PanelGeneratorError: Error, Equatable, Sendable {
    case noImageReturned
    /// Vertex 429 / RESOURCE_EXHAUSTED. Lands in `PanelReviewState.throttled`;
    /// auto-retry-once + countdown UI is slice 13's job.
    case throttled
    case underlying(String)
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

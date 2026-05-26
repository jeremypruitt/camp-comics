import Foundation

public enum PanelGeneratorError: Error, Equatable, Sendable {
    case noImageReturned
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

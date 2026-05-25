import Foundation

public enum PanelGeneratorError: Error, Equatable, Sendable {
    case noImageReturned
    case underlying(String)
}

public protocol PanelGenerator: Sendable {
    func generateQAPanel(prompt: String, photo: Data) async throws -> Data
}

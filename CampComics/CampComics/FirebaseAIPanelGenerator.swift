import Foundation
import FirebaseAI
import CampComicsCore

struct FirebaseAIPanelGenerator: PanelGenerator {
    static let modelName = "gemini-2.5-flash-image"

    func generateQAPanel(prompt: String, photo: Data) async throws -> Data {
        try await callVertex(prompt: prompt,
                             references: [ImageReference(data: photo, mimeType: "image/jpeg")])
    }

    func generatePanel(prompt: String, references: [ImageReference]) async throws -> Data {
        try await callVertex(prompt: prompt, references: references)
    }

    private func callVertex(prompt: String, references: [ImageReference]) async throws -> Data {
        let ai = FirebaseAI.firebaseAI(backend: .vertexAI())
        let model = ai.generativeModel(modelName: Self.modelName)
        var parts: [any Part] = references.map {
            InlineDataPart(data: $0.data, mimeType: $0.mimeType)
        }
        parts.append(TextPart(prompt))
        do {
            let response = try await model.generateContent([ModelContent(parts: parts)])
            guard let firstImage = response.inlineDataParts.first else {
                throw PanelGeneratorError.noImageReturned
            }
            return firstImage.data
        } catch let err as PanelGeneratorError {
            throw err
        } catch {
            throw PanelGeneratorError.underlying(humanReadable(error))
        }
    }

    private func humanReadable(_ error: Error) -> String {
        let raw = String(describing: error)
        if raw.contains("quota") || raw.contains("RESOURCE_EXHAUSTED") {
            return "Vertex per-minute quota exceeded. Wait a minute and retry."
        }
        if raw.contains("PERMISSION_DENIED") {
            return "Firebase AI permission denied — check Firebase project config and GoogleService-Info.plist."
        }
        return raw
    }
}

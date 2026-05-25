import Foundation
import FirebaseAI
import CampComicsCore

struct FirebaseAIPanelGenerator: PanelGenerator {
    static let modelName = "gemini-2.5-flash-image"

    func generateQAPanel(prompt: String, photo: Data) async throws -> Data {
        let ai = FirebaseAI.firebaseAI()
        let model = ai.generativeModel(modelName: Self.modelName)
        let imagePart = InlineDataPart(data: photo, mimeType: "image/jpeg")
        do {
            let response = try await model.generateContent(imagePart, prompt)
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

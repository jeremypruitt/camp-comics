import SwiftUI
import UIKit
import CampComicsCore

private enum GenerationState {
    case idle
    case generating
    case succeeded(UIImage)
    case failed(String)
}

struct PlayerDetailView: View {
    let player: PlayerRecord
    let template: ClassTemplate
    let store: PlayerStore
    let generator: any PanelGenerator

    @State private var state: GenerationState = .idle
    @State private var savedPanel1: UIImage?

    init(player: PlayerRecord,
         template: ClassTemplate,
         store: PlayerStore,
         generator: any PanelGenerator = FirebaseAIPanelGenerator()) {
        self.player = player
        self.template = template
        self.store = store
        self.generator = generator
        let existing = store.loadPanel(playerId: player.id, n: 1).flatMap(UIImage.init(data:))
        _savedPanel1 = State(initialValue: existing)
        if let existing { _state = State(initialValue: .succeeded(existing)) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                summary
                if let image = currentPanelImage {
                    panelPreview(image)
                }
                generateButton
                if case .failed(let msg) = state {
                    Text(msg)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.top, 4)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(player.playerName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(headline).font(.title2.weight(.semibold))
            Text("Class: \(template.name) · \(player.id)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func panelPreview(_ image: UIImage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Panel 1").font(.headline)
            if let beat = template.panels.first?.beat, !beat.isEmpty {
                Text(beat).font(.footnote).foregroundStyle(.secondary).italic()
            }
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var generateButton: some View {
        Button {
            Task { await generate() }
        } label: {
            Group {
                if isGenerating {
                    HStack(spacing: 8) {
                        ProgressView().tint(.white)
                        Text("Generating panel 1…")
                    }
                } else {
                    Text(savedPanel1 == nil ? "Generate panel 1" : "Regenerate panel 1")
                }
            }
            .frame(maxWidth: .infinity)
            .fontWeight(.semibold)
            .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(isGenerating)
    }

    private var isGenerating: Bool {
        if case .generating = state { return true }
        return false
    }

    private var currentPanelImage: UIImage? {
        if case .succeeded(let image) = state { return image }
        return savedPanel1
    }

    private var headline: String {
        if player.characterName.isEmpty {
            return player.playerName
        }
        return "\(player.characterName) (\(player.playerName))"
    }

    private func generate() async {
        guard let panel1 = template.panels.first else {
            state = .failed("Class template has no panel 1.")
            return
        }
        let gate = PanelRequirement(emotion: .neutral, position: .front)
        guard let photoData = store.loadPhoto(playerId: player.id, requirement: gate) else {
            state = .failed("Missing neutral|front photo — capture it first.")
            return
        }
        let heroData = BundledTemplates.heroCardData(forClassKey: template.classKey)

        // YAML scenes use {camper_name} (legacy token name). Until shared
        // templates rename to {player_name}, both legacy + iOS substitute
        // through this key.
        let prompt = PromptBuilder.buildPanelPrompt(
            spec: panel1,
            template: template,
            tokens: ["camper_name": player.playerName]
        )
        let references: [ImageReference] = [
            ImageReference(data: photoData, mimeType: "image/jpeg"),
            ImageReference(data: heroData, mimeType: "image/png"),
        ]

        state = .generating
        do {
            let panelData = try await generator.generatePanel(prompt: prompt, references: references)
            guard let image = UIImage(data: panelData) else {
                state = .failed("Generator returned data that wasn't a usable image.")
                return
            }
            try store.savePanel(playerId: player.id, n: 1, pngData: panelData)
            savedPanel1 = image
            state = .succeeded(image)
        } catch let err as PanelGeneratorError {
            state = .failed(message(for: err))
        } catch {
            state = .failed(String(describing: error))
        }
    }

    private func message(for error: PanelGeneratorError) -> String {
        switch error {
        case .noImageReturned: return "Gemini returned no image."
        case .underlying(let msg): return msg
        }
    }
}

#Preview {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("camp-comics-preview", isDirectory: true)
    let store = try! PlayerStore(root: tmp)
    let player = try! store.create(playerName: "Alex", characterName: "", classKey: "druid")
    return NavigationStack {
        PlayerDetailView(
            player: player,
            template: BundledTemplates.template(forClassKey: "druid"),
            store: store
        )
    }
}

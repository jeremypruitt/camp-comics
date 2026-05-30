import SwiftUI
import UIKit
import CampComicsCore

enum SubmissionState {
    case idle
    case submitting
    case succeeded(UIImage)
    case failed(String)
}

struct CaptureFlowView: View {
    @Environment(\.themeKind) private var theme
    let player: PlayerRecord
    let template: ClassTemplate
    let store: PlayerStore
    let generator: any PanelGenerator

    @State private var captureState: CaptureState
    @State private var photoStore: [UUID: UIImage] = [:]
    @State private var reviewing: PanelRequirement?
    @State private var capturing: PanelRequirement?
    @State private var submission: SubmissionState = .idle
    @State private var savedAvatar: UIImage?
    @State private var viewingSavedAvatar = false

    init(player: PlayerRecord,
         template: ClassTemplate,
         store: PlayerStore,
         generator: any PanelGenerator = FirebaseAIPanelGenerator(billingMode: BillingModeStore().current)) {
        self.player = player
        self.template = template
        self.store = store
        self.generator = generator
        let plan = CapturePlanner.plan(for: template)
        var state = CaptureState(plan: plan)
        var hydrated: [UUID: UIImage] = [:]
        for requirement in store.capturedRequirements(playerId: player.id) {
            guard plan.contains(requirement),
                  let data = store.loadPhoto(playerId: player.id, requirement: requirement),
                  let image = UIImage(data: data) else { continue }
            let photo = CapturedPhoto()
            hydrated[photo.id] = image
            state.record(photo, for: requirement)
        }
        _captureState = State(initialValue: state)
        _photoStore = State(initialValue: hydrated)
        let avatar = store.loadQAPanel(playerId: player.id).flatMap(UIImage.init(data:))
        _savedAvatar = State(initialValue: avatar)
    }

    var body: some View {
        let p = theme.palette
        ZStack {
            ThemedBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    summary
                    if let savedAvatar {
                        SavedAvatarChip(image: savedAvatar) { viewingSavedAvatar = true }
                    }
                    VStack(spacing: 12) {
                        ForEach(captureState.plan) { requirement in
                            ChecklistRow(
                                requirement: requirement,
                                isCaptured: captureState.isCaptured(requirement),
                                thumbnail: image(for: requirement),
                                onTap: { handleTap(requirement) }
                            )
                        }
                    }
                    submitButton
                }
                .padding()
                .padding(.bottom, 120)
            }
        }
        .navigationTitle("\(template.name) capture")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(p.paper, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(theme.preferredColorScheme, for: .navigationBar)
        .sheet(item: $reviewing) { requirement in
            ReviewSheet(
                requirement: requirement,
                image: image(for: requirement),
                onRetake: {
                    discardPhoto(for: requirement)
                    captureState.retake(requirement)
                    reviewing = nil
                    capturing = requirement
                },
                onConfirm: { reviewing = nil }
            )
        }
        .fullScreenCover(item: $capturing) { requirement in
            ImagePicker(sourceType: ImagePicker.preferredSourceType) { image in
                if let image {
                    record(image, for: requirement)
                }
                capturing = nil
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: isShowingResult) {
            if case .succeeded(let panel) = submission {
                QAResultSheet(
                    image: panel,
                    onReroll: {
                        submission = .idle
                        Task { await submit() }
                    },
                    onRetake: { retakeGatePhoto() },
                    onDone: { submission = .idle }
                )
            }
        }
        .sheet(isPresented: $viewingSavedAvatar) {
            if let savedAvatar {
                QAResultSheet(
                    image: savedAvatar,
                    onReroll: {
                        viewingSavedAvatar = false
                        Task { await submit() }
                    },
                    onRetake: {
                        viewingSavedAvatar = false
                        retakeGatePhoto()
                    },
                    onDone: { viewingSavedAvatar = false }
                )
            }
        }
        .alert("Generation failed", isPresented: isShowingError) {
            Button("OK") { submission = .idle }
        } message: {
            if case .failed(let msg) = submission { Text(msg) }
        }
    }

    private var isSubmitting: Bool {
        if case .submitting = submission { return true }
        return false
    }

    private var isShowingResult: Binding<Bool> {
        Binding(
            get: { if case .succeeded = submission { true } else { false } },
            set: { if !$0 { submission = .idle } }
        )
    }

    private var isShowingError: Binding<Bool> {
        Binding(
            get: { if case .failed = submission { true } else { false } },
            set: { if !$0 { submission = .idle } }
        )
    }

    private var summary: some View {
        let p = theme.palette
        return ThemedCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(playerHeadline)
                    .font(theme.headingFont(22))
                    .foregroundStyle(p.inkPrimary)
                Text("\(captureState.capturedCount) of \(captureState.plan.count) photos · tap any row.")
                    .font(theme.bodyFont(14))
                    .foregroundStyle(p.inkSecondary)
                ProgressSegments(total: captureState.plan.count, captured: captureState.capturedCount)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var submitButton: some View {
        let label = isSubmitting
            ? "Generating test panel…"
            : (captureState.isReadyToSubmit
               ? "All set — submit"
               : "\(captureState.remainingCount) more to go")
        return ThemedPrimaryButton(
            label,
            systemImage: isSubmitting ? nil : "checkmark.seal.fill",
            isLoading: isSubmitting,
            isEnabled: captureState.isReadyToSubmit && !isSubmitting
        ) {
            Task { await submit() }
        }
        .padding(.top, 6)
    }

    private func submit() async {
        let gate = PanelRequirement(emotion: .neutral, position: .front)
        guard let photo = image(for: gate),
              let photoData = photo.jpegData(compressionQuality: 0.9) else {
            submission = .failed("No neutral|front photo found. Retake it before submitting.")
            return
        }
        submission = .submitting
        let prompt = QAGatePrompt.assemble(for: template)
        do {
            let panelData = try await generator.generateQAPanel(prompt: prompt, photo: photoData)
            guard let panel = UIImage(data: panelData) else {
                submission = .failed("Generator returned data that wasn't a usable image.")
                return
            }
            try? store.saveQAPanel(playerId: player.id, pngData: panelData)
            savedAvatar = panel
            submission = .succeeded(panel)
        } catch let err as PanelGeneratorError {
            submission = .failed(message(for: err))
        } catch {
            submission = .failed(String(describing: error))
        }
    }

    private func message(for error: PanelGeneratorError) -> String {
        switch error {
        case .noImageReturned: return "Gemini returned no image."
        case .throttled: return "Vertex per-minute quota exceeded. Wait a moment and retry."
        case .underlying(let msg): return msg
        }
    }

    private func retakeGatePhoto() {
        let gate = PanelRequirement(emotion: .neutral, position: .front)
        discardPhoto(for: gate)
        captureState.retake(gate)
        try? store.deleteQAPanel(playerId: player.id)
        savedAvatar = nil
        submission = .idle
        capturing = gate
    }

    private var playerHeadline: String {
        if player.characterName.isEmpty {
            return "\(player.playerName) — \(template.name)"
        }
        return "\(player.characterName) (\(player.playerName)) — \(template.name)"
    }

    private func handleTap(_ requirement: PanelRequirement) {
        if captureState.isCaptured(requirement) {
            reviewing = requirement
        } else {
            capturing = requirement
        }
    }

    private func image(for requirement: PanelRequirement) -> UIImage? {
        guard let photo = captureState.capturedPhoto(for: requirement) else { return nil }
        return photoStore[photo.id]
    }

    private func record(_ image: UIImage, for requirement: PanelRequirement) {
        let photo = CapturedPhoto()
        photoStore[photo.id] = image
        captureState.record(photo, for: requirement)
        if let data = image.jpegData(compressionQuality: 0.9) {
            try? store.savePhoto(playerId: player.id, requirement: requirement, jpegData: data)
        }
    }

    private func discardPhoto(for requirement: PanelRequirement) {
        if let photo = captureState.capturedPhoto(for: requirement) {
            photoStore[photo.id] = nil
        }
        try? store.deletePhoto(playerId: player.id, requirement: requirement)
    }
}

private struct ChecklistRow: View {
    @Environment(\.themeKind) private var theme
    let requirement: PanelRequirement
    let isCaptured: Bool
    let thumbnail: UIImage?
    let onTap: () -> Void

    var body: some View {
        let copy = PromptCopyBook.copy(for: requirement)
        let p = theme.palette
        Button(action: onTap) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: tileCorner, style: .continuous)
                        .fill(isCaptured ? p.accent.opacity(0.22) : p.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: tileCorner, style: .continuous)
                                .stroke(isCaptured ? p.accent.opacity(0.7) : p.divider, lineWidth: 1)
                        )
                    if let thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: tileCorner, style: .continuous))
                    } else if isCaptured {
                        Image(systemName: "checkmark")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(p.accent)
                    } else {
                        Text(copy.emoji).font(.title)
                    }
                }
                .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 2) {
                    Text(copy.title)
                        .font(theme.headingFont(17))
                        .foregroundStyle(p.inkPrimary)
                    Text("\(requirement.emotion.rawValue) · \(requirement.position.rawValue)")
                        .font(theme.captionFont(12))
                        .foregroundStyle(p.inkSecondary)
                }
                Spacer()
                Image(systemName: isCaptured ? "checkmark.circle.fill" : "chevron.right")
                    .foregroundStyle(isCaptured ? p.accent : p.inkSecondary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: cardCorner, style: .continuous)
                    .fill(isCaptured ? p.accent.opacity(0.08) : p.surfaceRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cardCorner, style: .continuous)
                    .stroke(p.divider.opacity(0.7), lineWidth: 0.8)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var tileCorner: CGFloat { 10 }
    private var cardCorner: CGFloat { 4 }
}

private struct SavedAvatarChip: View {
    @Environment(\.themeKind) private var theme
    let image: UIImage
    let onTap: () -> Void

    var body: some View {
        let p = theme.palette
        Button(action: onTap) {
            ThemedCard {
                HStack(spacing: 14) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Test panel ready")
                            .font(theme.headingFont(17))
                            .foregroundStyle(p.inkPrimary)
                        Text("Tap to view, re-roll, or retake the gate photo.")
                            .font(theme.captionFont(12))
                            .foregroundStyle(p.inkSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(p.accent)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct ProgressSegments: View {
    @Environment(\.themeKind) private var theme
    let total: Int
    let captured: Int

    var body: some View {
        let p = theme.palette
        HStack(spacing: 4) {
            ForEach(0..<total, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(i < captured ? p.accent : p.divider.opacity(0.4))
                    .frame(height: 6)
            }
        }
    }
}

private struct ReviewSheet: View {
    let requirement: PanelRequirement
    let image: UIImage?
    let onRetake: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        let copy = PromptCopyBook.copy(for: requirement)
        VStack(spacing: 20) {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                Text(copy.emoji).font(.system(size: 96))
            }
            VStack(spacing: 6) {
                Text(copy.title).font(.title2.weight(.semibold))
                Text(copy.subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button("Retake", role: .destructive, action: onRetake)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                Button("Looks good", action: onConfirm)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
        .padding()
        .presentationDetents([.medium, .large])
    }
}

private struct QAResultSheet: View {
    let image: UIImage
    let onReroll: () -> Void
    let onRetake: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Test panel generated")
                .font(.title2.weight(.semibold))
            Text("Pinch to zoom. Re-roll to regenerate from the same photo, or retake the gate photo.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            ZoomableImage(image: image)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(spacing: 12) {
                Button("Retake photo", role: .destructive, action: onRetake)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                Button("Re-roll", action: onReroll)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                Button("Done", action: onDone)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
        .padding()
        .presentationDetents([.large])
    }
}

#Preview {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("camp-comics-preview", isDirectory: true)
    let store = try! PlayerStore(root: tmp)
    let player = try! store.create(playerName: "Alex", characterName: "", classKey: "druid")
    return NavigationStack {
        CaptureFlowView(
            player: player,
            template: BundledTemplates.template(forClassKey: "druid"),
            store: store
        )
    }
}

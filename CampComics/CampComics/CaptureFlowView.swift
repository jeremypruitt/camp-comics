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
    let player: PlayerProfile
    let template: ClassTemplate
    let generator: any PanelGenerator

    @State private var captureState: CaptureState
    @State private var photoStore: [UUID: UIImage] = [:]
    @State private var reviewing: PanelRequirement?
    @State private var capturing: PanelRequirement?
    @State private var submission: SubmissionState = .idle

    init(player: PlayerProfile, template: ClassTemplate, generator: any PanelGenerator = FirebaseAIPanelGenerator()) {
        self.player = player
        self.template = template
        self.generator = generator
        let plan = CapturePlanner.plan(for: template)
        _captureState = State(initialValue: CaptureState(plan: plan))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                summary
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
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("\(template.name) capture")
        .navigationBarTitleDisplayMode(.inline)
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
        VStack(alignment: .leading, spacing: 8) {
            Text(playerHeadline)
                .font(.title2.weight(.semibold))
            Text("\(captureState.capturedCount) of \(captureState.plan.count) photos · tap any row.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ProgressSegments(total: captureState.plan.count, captured: captureState.capturedCount)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var submitButton: some View {
        Button {
            Task { await submit() }
        } label: {
            Group {
                if isSubmitting {
                    HStack(spacing: 8) {
                        ProgressView().tint(.white)
                        Text("Generating test panel…")
                    }
                } else {
                    Text(captureState.isReadyToSubmit
                         ? "All set — submit"
                         : "\(captureState.remainingCount) more to go")
                }
            }
            .frame(maxWidth: .infinity)
            .fontWeight(.semibold)
            .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!captureState.isReadyToSubmit || isSubmitting)
        .padding(.top, 8)
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
        case .underlying(let msg): return msg
        }
    }

    private func retakeGatePhoto() {
        let gate = PanelRequirement(emotion: .neutral, position: .front)
        discardPhoto(for: gate)
        captureState.retake(gate)
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
    }

    private func discardPhoto(for requirement: PanelRequirement) {
        if let photo = captureState.capturedPhoto(for: requirement) {
            photoStore[photo.id] = nil
        }
    }
}

private struct ChecklistRow: View {
    let requirement: PanelRequirement
    let isCaptured: Bool
    let thumbnail: UIImage?
    let onTap: () -> Void

    var body: some View {
        let copy = PromptCopyBook.copy(for: requirement)
        Button(action: onTap) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isCaptured ? Color.accentColor.opacity(0.18) : Color(.tertiarySystemFill))
                    if let thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    } else if isCaptured {
                        Image(systemName: "checkmark")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.tint)
                    } else {
                        Text(copy.emoji).font(.title)
                    }
                }
                .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 2) {
                    Text(copy.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("\(requirement.emotion.rawValue) · \(requirement.position.rawValue)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isCaptured ? "checkmark.circle.fill" : "chevron.right")
                    .foregroundStyle(isCaptured ? Color.accentColor : Color.secondary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isCaptured ? Color.accentColor.opacity(0.08) : Color(.secondarySystemGroupedBackground))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ProgressSegments: View {
    let total: Int
    let captured: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<total, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(i < captured ? Color.accentColor : Color(.tertiarySystemFill))
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

private struct ZoomableImage: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.delegate = context.coordinator
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = 6
        scroll.bouncesZoom = true
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false

        let iv = UIImageView(image: image)
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.isUserInteractionEnabled = true
        scroll.addSubview(iv)
        NSLayoutConstraint.activate([
            iv.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            iv.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            iv.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            iv.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            iv.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            iv.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
        ])

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(doubleTap)

        context.coordinator.imageView = iv
        return scroll
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.imageView?.image = image
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        @objc func handleDoubleTap(_ gr: UITapGestureRecognizer) {
            guard let scroll = gr.view as? UIScrollView else { return }
            let target: CGFloat = scroll.zoomScale > 1.01 ? 1 : 2.5
            scroll.setZoomScale(target, animated: true)
        }
    }
}

#Preview {
    NavigationStack {
        CaptureFlowView(
            player: PlayerProfile(playerName: "Alex", characterName: "", classKey: "druid"),
            template: BundledTemplates.druid
        )
    }
}

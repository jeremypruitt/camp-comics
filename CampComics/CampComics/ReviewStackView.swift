import SwiftUI
import UIKit
import CampComicsCore

/// ADR-0009 Phase 1 surface. Single-card stack scoped to panel 1 only — the
/// "panel 1 sets your style" beat that must clear before the Phase 2 batch
/// worker pool (Slice D / #64) gets enqueued. Auto-fires generation on mount
/// (the Start CTA is the operator commitment, not a second tap here). Swipe
/// right accepts the current candidate → writes `panel_01.png` → flips to the
/// Phase 2 placeholder. Phase 2's worker pool, gallery cycling, Re-roll, and
/// Re-prompt land in Slices D–H; this slice deliberately ships gestures and
/// gallery state as out-of-scope.
struct ReviewStackView: View {
    @Environment(\.themeKind) private var theme
    let player: PlayerRecord
    let template: ClassTemplate
    let store: PlayerStore
    let generator: any PanelGenerator

    @State private var phase: Phase = .generatingPhase1
    @State private var candidate: PanelCandidate?
    @State private var pendingTask: Task<Void, Never>?
    @State private var lastError: String?
    @State private var swipeOffset: CGSize = .zero

    private enum Phase: Equatable {
        case generatingPhase1
        case reviewingPhase1
        case phase2Pending
        case failedPhase1(String)
    }

    init(player: PlayerRecord,
         template: ClassTemplate,
         store: PlayerStore,
         generator: any PanelGenerator = FirebaseAIPanelGenerator(billingMode: BillingModeStore().current)) {
        self.player = player
        self.template = template
        self.store = store
        self.generator = generator
    }

    var body: some View {
        let p = theme.palette
        ZStack {
            ThemedBackground()
            VStack(spacing: 18) {
                Text(headerText)
                    .font(theme.headingFont(18))
                    .foregroundStyle(p.inkPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                cardBody
                if let lastError {
                    Text(lastError)
                        .font(theme.captionFont(12))
                        .foregroundStyle(p.danger)
                        .padding(.horizontal)
                }
                Spacer()
            }
            .padding(.vertical)
        }
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(p.paper, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(theme.preferredColorScheme, for: .navigationBar)
        .onAppear {
            // Re-entering with panel 1 already accepted (e.g. mid-flight player
            // flipped flag on, navigated back) skips straight to the Phase 2
            // placeholder rather than re-firing the generation.
            if store.hasPanel(playerId: player.id, target: .panel(1)) {
                phase = .phase2Pending
            } else if pendingTask == nil, case .generatingPhase1 = phase {
                startPanel1Generation()
            }
        }
        .onDisappear { pendingTask?.cancel() }
    }

    private var headerText: String {
        switch phase {
        case .generatingPhase1, .reviewingPhase1: return "Panel 1 — sets the style"
        case .phase2Pending: return "Phase 2 — batch generation"
        case .failedPhase1: return "Panel 1 — failed"
        }
    }

    @ViewBuilder
    private var cardBody: some View {
        switch phase {
        case .generatingPhase1:
            placeholderCard
        case .reviewingPhase1:
            if let candidate, let image = loadImage(candidate.url) {
                candidateCard(image: image)
            } else {
                placeholderCard
            }
        case .phase2Pending:
            phase2PlaceholderCard
        case .failedPhase1(let message):
            failedCard(message: message)
        }
    }

    private var placeholderCard: some View {
        let p = theme.palette
        return RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(p.surfaceRaised)
            .overlay {
                VStack(spacing: 14) {
                    ProgressView()
                    Text("Generating…")
                        .font(theme.captionFont(13))
                        .foregroundStyle(p.inkSecondary)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .padding(.horizontal)
    }

    private func candidateCard(image: UIImage) -> some View {
        let p = theme.palette
        return Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal)
            .offset(swipeOffset)
            .rotationEffect(.degrees(Double(swipeOffset.width / 20)))
            .overlay(alignment: .topTrailing) {
                if swipeOffset.width > 40 {
                    Text("ACCEPT")
                        .font(theme.headingFont(20))
                        .foregroundStyle(p.accent)
                        .padding(8)
                        .background(p.paper, in: RoundedRectangle(cornerRadius: 8))
                        .padding(24)
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { swipeOffset = $0.translation }
                    .onEnded { value in
                        if value.translation.width > 120 {
                            commitAcceptPanel1()
                        } else {
                            withAnimation(.spring) { swipeOffset = .zero }
                        }
                    }
            )
    }

    private var phase2PlaceholderCard: some View {
        let p = theme.palette
        return ThemedCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Panel 1 locked in.")
                    .font(theme.headingFont(18))
                    .foregroundStyle(p.inkPrimary)
                Text("Phase 2 — panels 2–15 and the cover — lands in Slice D. Tap back to return to the campaign log.")
                    .font(theme.bodyFont(14))
                    .foregroundStyle(p.inkSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal)
    }

    private func failedCard(message: String) -> some View {
        let p = theme.palette
        return ThemedCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Panel 1 didn't generate")
                    .font(theme.headingFont(18))
                    .foregroundStyle(p.inkPrimary)
                Text(message)
                    .font(theme.captionFont(12))
                    .foregroundStyle(p.danger)
                ThemedPrimaryButton("Retry", systemImage: "arrow.clockwise") {
                    startPanel1Generation()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal)
    }

    // MARK: - Actions

    private func startPanel1Generation() {
        guard let spec = template.panels.first(where: { $0.n == 1 }) else {
            phase = .failedPhase1("Template is missing panel 1.")
            return
        }
        let target: PanelTarget = .panel(n: 1, spec: spec)
        guard let photoData = store.loadPhoto(playerId: player.id,
                                              requirement: target.requirement) else {
            phase = .failedPhase1("Missing reference photo for panel 1.")
            return
        }
        let prompt = PromptBuilder.buildPrompt(for: target,
                                               template: template,
                                               tokens: ["camper_name": player.playerName])
        let references: [ImageReference] = [
            ImageReference(data: photoData, mimeType: "image/jpeg"),
            ImageReference(data: BundledTemplates.heroCardData(forClassKey: template.classKey),
                           mimeType: "image/png")
        ]
        phase = .generatingPhase1
        candidate = nil
        lastError = nil
        pendingTask?.cancel()
        pendingTask = Task {
            do {
                let pngData = try await generator.generatePanel(prompt: prompt,
                                                                references: references)
                if Task.isCancelled { return }
                let saved = try store.savePendingCandidate(playerId: player.id,
                                                           target: target.id,
                                                           pngData: pngData)
                await MainActor.run {
                    candidate = saved
                    phase = .reviewingPhase1
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run {
                    phase = .failedPhase1(String(describing: error))
                }
            }
            await MainActor.run { pendingTask = nil }
        }
    }

    private func commitAcceptPanel1() {
        guard let candidate else { return }
        do {
            try store.acceptCandidate(playerId: player.id,
                                      target: .panel(1),
                                      candidateIndex: candidate.index)
            withAnimation(.easeOut(duration: 0.2)) {
                swipeOffset = CGSize(width: 600, height: 0)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                phase = .phase2Pending
                swipeOffset = .zero
                self.candidate = nil
            }
        } catch {
            lastError = String(describing: error)
            withAnimation(.spring) { swipeOffset = .zero }
        }
    }

    private func loadImage(_ url: URL) -> UIImage? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }
}

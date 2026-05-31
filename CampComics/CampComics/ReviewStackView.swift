import SwiftUI
import UIKit
import CampComicsCore

/// ADR-0009 Phase 1 + Phase 2 surface. Single-card stack scoped to panel 1
/// (the "panel 1 sets your style" beat) until acceptance flips into Phase 2,
/// where a story-ordered worker pool generates panels 2..N + cover in parallel
/// and the operator swipes through the head as each candidate lands on disk.
/// Auto-fires Phase 1 generation on mount (the Start CTA is the commitment).
/// Swipe-right on Phase 1's candidate writes `panel_01.png` and pushes into
/// Phase 2. Swipe-left, swipe-up/down, long-press are Slice E/F/G — wired as
/// no-ops here so the gesture surface exists for the next slices to extend.
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
    /// Set when Phase 1 Accept on a panel-1 candidate trips the cascade-warn
    /// predicate (slice J / #70). On a fresh comic this never fires — Phase 1
    /// is by definition first-time accept — but a mid-flight player re-entering
    /// the Phase 1 surface with downstream work already on disk could trigger
    /// it, and the gate keeps the rule uniform across surfaces.
    @State private var pendingPanel1AcceptIndex: Int?
    @State private var showingTutorial: Bool = false

    private let onboardingStore = OnboardingOverlayStore()

    private enum Phase: Equatable {
        case generatingPhase1
        case reviewingPhase1
        case runningPhase2
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
            switch phase {
            case .runningPhase2:
                Phase2StackView(player: player,
                                template: template,
                                store: store,
                                generator: generator)
            default:
                phase1Body
            }
        }
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(p.paper, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(theme.preferredColorScheme, for: .navigationBar)
        .onAppear {
            // Re-entering with panel 1 already accepted (e.g. mid-flight player
            // flipped flag on, navigated back) skips straight to Phase 2 rather
            // than re-firing panel 1 generation.
            if store.hasPanel(playerId: player.id, target: .panel(1)) {
                phase = .runningPhase2
            } else if pendingTask == nil, case .generatingPhase1 = phase {
                startPanel1Generation()
            }
            // First-launch tutorial. Same flag-gate semantics as the swipe
            // surface: if you're in `ReviewStackView` at all, you're new.
            if !onboardingStore.hasSeen {
                showingTutorial = true
            }
        }
        .onDisappear { pendingTask?.cancel() }
        .confirmationDialog(
            "Panel 1 anchors the continuity of every other panel. The new look won't auto-propagate. Re-roll downstream panels from the grid if anything looks off.",
            isPresented: Binding(get: { pendingPanel1AcceptIndex != nil },
                                 set: { if !$0 { pendingPanel1AcceptIndex = nil } }),
            titleVisibility: .visible
        ) {
            Button("Continue") {
                if let idx = pendingPanel1AcceptIndex {
                    pendingPanel1AcceptIndex = nil
                    finalizeAcceptPanel1(candidateIndex: idx)
                }
            }
            Button("Cancel", role: .cancel) {
                pendingPanel1AcceptIndex = nil
                withAnimation(.spring) { swipeOffset = .zero }
            }
        }
        .overlay {
            if showingTutorial {
                ReviewTutorialOverlay(hints: OverlayHint.allCases) {
                    onboardingStore.hasSeen = true
                    withAnimation(.easeOut(duration: 0.2)) { showingTutorial = false }
                }
                .transition(.opacity)
            }
        }
    }

    private var phase1Body: some View {
        let p = theme.palette
        return VStack(spacing: 18) {
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

    private var headerText: String {
        switch phase {
        case .generatingPhase1, .reviewingPhase1: return "Panel 1 — sets the style"
        case .runningPhase2: return ""
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
        case .runningPhase2:
            EmptyView()
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
                // Spend one panel 1 call against the per-comic budget so the
                // chip the Phase 2 surface reads on mount reflects reality.
                spendOne()
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
        if Panel1CascadeWarning.shouldWarn(playerId: player.id,
                                           acceptingCandidateIndex: candidate.index,
                                           store: store,
                                           panelCount: template.panels.count) {
            // Hold the swipe-released card in place (don't spring it back) so
            // the candidate stays visible behind the dialog.
            pendingPanel1AcceptIndex = candidate.index
            return
        }
        finalizeAcceptPanel1(candidateIndex: candidate.index)
    }

    /// Shared by the unguarded swipe path and the cascade-warn Continue button.
    private func finalizeAcceptPanel1(candidateIndex: Int) {
        do {
            try store.acceptCandidate(playerId: player.id,
                                      target: .panel(1),
                                      candidateIndex: candidateIndex)
            withAnimation(.easeOut(duration: 0.2)) {
                swipeOffset = CGSize(width: 600, height: 0)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                phase = .runningPhase2
                swipeOffset = .zero
                self.candidate = nil
            }
        } catch {
            lastError = String(describing: error)
            withAnimation(.spring) { swipeOffset = .zero }
        }
    }

    private func spendOne() {
        let current = store.generationBudget(playerId: player.id,
                                             panelCount: template.panels.count)
        try? store.setGenerationBudget(playerId: player.id, current.decremented())
    }

    private func loadImage(_ url: URL) -> UIImage? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }
}

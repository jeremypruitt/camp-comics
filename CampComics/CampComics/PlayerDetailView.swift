import SwiftUI
import UIKit
import CampComicsCore

/// Minimal intermediate screen (project_panel_loop_design.md #11): summary +
/// a single Start / Continue generation button that pushes into
/// `PanelReviewView`. Auto-start from the player list is deliberately gated so
/// the operator opts in to Vertex spend.
struct PlayerDetailView: View {
    @Environment(\.themeKind) private var theme
    let player: PlayerRecord
    let template: ClassTemplate
    let store: PlayerStore
    let generator: any PanelGenerator
    let trialBackend: any SponsoredTrialBackend

    @State private var showingReview = false
    @State private var showingStartCampaign = false
    @State private var previewItem: PreviewItem?
    @State private var isRendering = false
    @State private var renderError: String?
    /// Slice H (#68): set when "Generate PDF" is tapped while one or more
    /// panels are deferred. Surfaces the empty-cell confirm before the render
    /// kicks off so the operator doesn't accidentally finalize a hole.
    @State private var pendingDeferredFinalize: [String] = []

    init(player: PlayerRecord,
         template: ClassTemplate,
         store: PlayerStore,
         generator: any PanelGenerator = FirebaseAIPanelGenerator(billingMode: BillingModeStore().current),
         trialBackend: any SponsoredTrialBackend = FirestoreSponsoredTrialBackend()) {
        self.player = player
        self.template = template
        self.store = store
        self.generator = generator
        self.trialBackend = trialBackend
    }

    var body: some View {
        let p = theme.palette
        ZStack {
            ThemedBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    summary
                    progressCard
                    continueButton
                    if isDone {
                        generatePDFButton
                    }
                    if let renderError {
                        Text(renderError)
                            .font(theme.captionFont(12))
                            .foregroundStyle(p.danger)
                    }
                }
                .padding()
                .padding(.bottom, 120)
            }
        }
        .navigationTitle(player.playerName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(p.paper, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(theme.preferredColorScheme, for: .navigationBar)
        .navigationDestination(isPresented: $showingReview) {
            PanelReviewView(player: player,
                            template: template,
                            store: store,
                            generator: generator,
                            startAt: startTarget,
                            onRequestFinalize: { Task { await generatePDF() } })
        }
        .navigationDestination(isPresented: $showingStartCampaign) {
            StartCampaignView(player: player,
                              template: template,
                              store: store,
                              generator: generator,
                              trialBackend: trialBackend)
        }
        .sheet(item: $previewItem) { item in
            PDFPreview(url: item.url)
        }
        .confirmationDialog(
            deferredFinalizeMessage,
            isPresented: Binding(get: { !pendingDeferredFinalize.isEmpty },
                                 set: { if !$0 { pendingDeferredFinalize = [] } }),
            titleVisibility: .visible
        ) {
            Button("Generate anyway") {
                pendingDeferredFinalize = []
                Task { await generatePDF() }
            }
            Button("Cancel", role: .cancel) {
                pendingDeferredFinalize = []
            }
        }
    }

    /// Slice H (#68): copy mirrors the issue spec — singular shape when one
    /// panel is deferred, plural when multiple. Cover is named explicitly.
    private var deferredFinalizeMessage: String {
        let names = pendingDeferredFinalize
        if names.count == 1 {
            return "\(names[0]) has no image — your comic will have an empty cell. Generate anyway?"
        }
        let joined = names.joined(separator: ", ")
        return "\(joined) have no images — your comic will have empty cells. Generate anyway?"
    }

    // MARK: - Subviews

    private var summary: some View {
        let p = theme.palette
        return ThemedCard {
            VStack(alignment: .leading, spacing: 6) {
                Text(headline)
                    .font(theme.displayFont(28))
                    .foregroundStyle(p.inkPrimary)
                Text("\(template.name) · \(player.id)")
                    .font(theme.captionFont(13))
                    .tracking(2)
                    .foregroundStyle(p.accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var progressCard: some View {
        let p = theme.palette
        return ThemedCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(progressTitle)
                    .font(theme.headingFont(18))
                    .foregroundStyle(p.inkPrimary)
                Text("\(finalizedCount) of \(allTargets.count) artifacts finalized")
                    .font(theme.bodyFont(14))
                    .foregroundStyle(p.inkSecondary)
                ProgressView(value: Double(finalizedCount), total: Double(allTargets.count))
                    .tint(p.accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var continueButton: some View {
        ThemedPrimaryButton(continueLabel, systemImage: "sparkles") {
            // ADR-0009 flag-gated handoff. New players (no panel 1 yet) with
            // the swipe-surface flag on get the Start CTA → ReviewStackView
            // pipeline. Mid-flight players stay on `PanelReviewView` so the
            // partial Phase 1 surface doesn't collide with their gallery
            // state (the legacy review machine doesn't go away until slice L).
            if UseSwipeReviewSurfaceStore().isEnabled && finalizedCount == 0 {
                showingStartCampaign = true
            } else {
                showingReview = true
            }
        }
    }

    private var generatePDFButton: some View {
        ThemedPrimaryButton(
            isRendering ? "Generating…" : pdfButtonLabel,
            systemImage: isRendering ? nil : "doc.richtext",
            isLoading: isRendering,
            isEnabled: !isRendering
        ) {
            // Slice H (#68): if any panel is deferred, surface the empty-cell
            // confirm first. The confirm's "Generate anyway" runs the same
            // `generatePDF()` body below.
            let deferredNames = deferredTargetNames()
            if deferredNames.isEmpty {
                Task { await generatePDF() }
            } else {
                pendingDeferredFinalize = deferredNames
            }
        }
    }

    /// Slice H: human-readable names of every deferred target in story order
    /// ("Panel 7", "Cover"). Empty list = no deferred panels → no confirm.
    private func deferredTargetNames() -> [String] {
        var names: [String] = []
        for panel in template.panels where store.isDeferred(playerId: player.id, target: .panel(panel.n)) {
            names.append("Panel \(panel.n)")
        }
        if store.isDeferred(playerId: player.id, target: .cover) {
            names.append("Cover")
        }
        return names
    }

    private var progressTitle: String { "Campaign Log" }

    private var pdfButtonLabel: String { "Print the Quest" }

    private func generatePDF() async {
        renderError = nil
        isRendering = true
        defer { isRendering = false }
        do {
            let url = try await PDFRenderer.render(player: player,
                                                   template: template,
                                                   store: store)
            previewItem = PreviewItem(url: url)
            if BillingModeStore().current == .sponsored {
                let backend = trialBackend
                let playerId = player.id
                Task { try? await backend.recordFinalized(playerId: playerId) }
            }
        } catch {
            renderError = "PDF render failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Derived

    /// Ordered review surface: 12 panels + the cover sibling. Mirrors
    /// `PanelReviewView.allTargets` — both screens have to agree on what "N
    /// of 13" means and which slot Start/Continue jumps to.
    private var allTargets: [PanelTarget] {
        var out: [PanelTarget] = template.panels.map { .panel(n: $0.n, spec: $0) }
        out.append(.cover(spec: template.cover))
        return out
    }

    private var finalizedCount: Int {
        allTargets.filter { store.hasPanel(playerId: player.id, target: $0.id) }.count
    }

    private var isDone: Bool {
        PlayerStatus.derive(playerId: player.id, template: template, store: store) == .done
    }

    private var startTarget: PanelTarget {
        allTargets.first(where: { !store.hasPanel(playerId: player.id, target: $0.id) })
            ?? allTargets[0]
    }

    private var continueLabel: String {
        let total = allTargets.count
        if finalizedCount == 0 { return "Start generation" }
        if finalizedCount == total { return "Review panels" }
        switch startTarget {
        case .panel(let n, _):
            return "Continue generation — panel \(n) of \(total)"
        case .cover:
            return "Continue generation — cover"
        }
    }

    private var headline: String {
        if player.characterName.isEmpty {
            return player.playerName
        }
        return "\(player.characterName) (\(player.playerName))"
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

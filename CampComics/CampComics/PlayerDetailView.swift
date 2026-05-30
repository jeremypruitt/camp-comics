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

    @State private var showingReview = false
    @State private var previewItem: PreviewItem?
    @State private var isRendering = false
    @State private var renderError: String?

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
                            startAt: startTarget)
        }
        .sheet(item: $previewItem) { item in
            PDFPreview(url: item.url)
        }
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
            showingReview = true
        }
    }

    private var generatePDFButton: some View {
        ThemedPrimaryButton(
            isRendering ? "Generating…" : pdfButtonLabel,
            systemImage: isRendering ? nil : "doc.richtext",
            isLoading: isRendering,
            isEnabled: !isRendering
        ) {
            Task { await generatePDF() }
        }
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

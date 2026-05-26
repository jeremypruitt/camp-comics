import SwiftUI
import UIKit
import CampComicsCore

/// Minimal intermediate screen (project_panel_loop_design.md #11): summary +
/// a single Start / Continue generation button that pushes into
/// `PanelReviewView`. Auto-start from the player list is deliberately gated so
/// the operator opts in to Vertex spend.
struct PlayerDetailView: View {
    let player: PlayerRecord
    let template: ClassTemplate
    let store: PlayerStore
    let generator: any PanelGenerator

    @State private var showingReview = false

    init(player: PlayerRecord,
         template: ClassTemplate,
         store: PlayerStore,
         generator: any PanelGenerator = FirebaseAIPanelGenerator()) {
        self.player = player
        self.template = template
        self.store = store
        self.generator = generator
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                summary
                progressCard
                continueButton
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(player.playerName)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showingReview) {
            PanelReviewView(player: player,
                            template: template,
                            store: store,
                            generator: generator,
                            startAt: startPanel)
        }
    }

    // MARK: - Subviews

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

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Progress").font(.headline)
            Text("\(finalizedCount) of 12 panels finalized")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ProgressView(value: Double(finalizedCount), total: 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var continueButton: some View {
        Button {
            showingReview = true
        } label: {
            Text(continueLabel)
                .frame(maxWidth: .infinity)
                .fontWeight(.semibold)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    // MARK: - Derived

    private var finalizedCount: Int {
        (1...12).filter {
            store.hasPanel(playerId: player.id, n: $0)
                || store.isSkipped(playerId: player.id, n: $0)
        }.count
    }

    private var startPanel: Int {
        for n in 1...12 {
            if !store.hasPanel(playerId: player.id, n: n)
                && !store.isSkipped(playerId: player.id, n: n) {
                return n
            }
        }
        return 1
    }

    private var continueLabel: String {
        if finalizedCount == 0 { return "Start generation" }
        if finalizedCount == 12 { return "Review panels" }
        return "Continue generation — panel \(startPanel) of 12"
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

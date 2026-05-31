import SwiftUI
import CampComicsCore

/// ADR-0009 entry point for the swipe-review surface. Full-screen CTA between
/// the QA gate and the new `ReviewStackView`. Under `.sponsored` the Start tap
/// commits one trial unit via `SponsoredTrialBackend.spend(playerId:)` — the
/// "deliberate moment to commit" is load-bearing because finalize-time
/// decrement is gone in this surface. The two-phase explainer copy primes the
/// operator for the walk-away batch model that lands in Slice D (#64).
struct StartCampaignView: View {
    @Environment(\.themeKind) private var theme
    let player: PlayerRecord
    let template: ClassTemplate
    let store: PlayerStore
    let generator: any PanelGenerator
    let trialBackend: any SponsoredTrialBackend

    @State private var navigatingToStack = false
    @State private var isStarting = false
    @State private var startError: String?

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
                VStack(alignment: .leading, spacing: 22) {
                    headline
                    phaseCard(number: "1",
                              title: "Panel 1 sets your style",
                              body: "We generate the first panel together. Swipe right when you like it — that locks the look for the rest.")
                    phaseCard(number: "2",
                              title: "We batch-generate the rest while you wait",
                              body: "Panels 2–15 and the cover render in parallel. Swipe through the stack to accept, re-roll, or re-prompt.")
                    startButton
                    if let startError {
                        Text(startError)
                            .font(theme.captionFont(12))
                            .foregroundStyle(p.danger)
                    }
                }
                .padding()
                .padding(.bottom, 120)
            }
        }
        .navigationTitle("Start campaign")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(p.paper, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(theme.preferredColorScheme, for: .navigationBar)
        .navigationDestination(isPresented: $navigatingToStack) {
            ReviewStackView(player: player,
                            template: template,
                            store: store,
                            generator: generator)
                .environment(\.themeKind, theme)
        }
    }

    private var headline: some View {
        let p = theme.palette
        return ThemedCard {
            VStack(alignment: .leading, spacing: 6) {
                Text(player.playerName)
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

    private func phaseCard(number: String, title: String, body: String) -> some View {
        let p = theme.palette
        return ThemedCard {
            HStack(alignment: .top, spacing: 14) {
                Text(number)
                    .font(theme.displayFont(28))
                    .foregroundStyle(p.accent)
                    .frame(width: 36, alignment: .leading)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(theme.headingFont(18))
                        .foregroundStyle(p.inkPrimary)
                    Text(body)
                        .font(theme.bodyFont(14))
                        .foregroundStyle(p.inkSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var startButton: some View {
        ThemedPrimaryButton(
            isStarting ? "Starting…" : "Start campaign",
            systemImage: isStarting ? nil : "sparkles",
            isLoading: isStarting,
            isEnabled: !isStarting
        ) {
            Task { await startCampaign() }
        }
    }

    private func startCampaign() async {
        startError = nil
        isStarting = true
        defer { isStarting = false }
        if BillingModeStore().current == .sponsored {
            do {
                try await trialBackend.spend(playerId: player.id)
            } catch {
                startError = "Couldn't record sponsored trial spend: \(error.localizedDescription)"
                return
            }
        }
        navigatingToStack = true
    }
}

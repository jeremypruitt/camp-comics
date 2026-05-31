import SwiftUI
import UIKit
import CampComicsCore

struct ContentView: View {
    let store: PlayerStore
    @Environment(\.themeKind) private var theme
    @Environment(\.partyLayout) private var partyLayout

    @State private var players: [PlayerRecord] = []
    @State private var avatars: [String: UIImage] = [:]
    @State private var statuses: [String: PlayerStatus] = [:]
    @State private var activePlayer: PlayerRecord?
    @State private var showingIntake = false
    @State private var showingSettings = false
    @State private var trial: SponsoredTrial = .empty

    private let trialBackend: any SponsoredTrialBackend = FirestoreSponsoredTrialBackend()

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                ThemedBackground()
                ScrollView {
                    VStack(spacing: 0) {
                        QuestCardHeader(onAdd: { showingIntake = true },
                                        trialRemaining: trialChipValue,
                                        onSettings: { showingSettings = true })
                        rosterBody
                        Spacer(minLength: 140)
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingIntake) {
                NavigationStack {
                    IntakeFormView { playerName, characterName, classKey in
                        do {
                            let created = try store.create(playerName: playerName,
                                                           characterName: characterName,
                                                           classKey: classKey)
                            showingIntake = false
                            refresh()
                            activePlayer = created
                        } catch {
                            showingIntake = false
                        }
                    }
                    .environment(\.themeKind, theme)
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
                    .environment(\.themeKind, theme)
            }
            .navigationDestination(item: $activePlayer) { player in
                let template = BundledTemplates.template(forClassKey: player.classKey)
                Group {
                    if store.hasQAPanel(playerId: player.id) {
                        PlayerDetailView(player: player,
                                         template: template,
                                         store: store,
                                         trialBackend: trialBackend)
                    } else {
                        CaptureFlowView(player: player, template: template, store: store)
                    }
                }
                .environment(\.themeKind, theme)
            }
            .task { await refreshTrial() }
            .onAppear { refresh() }
            .onChange(of: activePlayer) { _, new in
                if new == nil {
                    refresh()
                    Task { await refreshTrial() }
                }
            }
        }
    }

    private var trialChipValue: Int? {
        BillingModeStore().current == .sponsored ? trial.remaining : nil
    }

    private func refreshTrial() async {
        if let next = try? await trialBackend.fetch() {
            trial = next
        }
    }

    @ViewBuilder
    private var rosterBody: some View {
        if players.isEmpty {
            EmptyRoster { showingIntake = true }
        } else {
            let entries = players.map { p in
                RosterEntry(player: p, avatar: avatars[p.id], status: statuses[p.id])
            }
            switch partyLayout {
            case .grid: QuestCardRoster(entries: entries)     { activePlayer = $0 }
            case .list: QuestCardListRoster(entries: entries) { activePlayer = $0 }
            }
        }
    }

    private func refresh() {
        let loaded = (try? store.list()) ?? []
        players = loaded
        var nextAvatars: [String: UIImage] = [:]
        var nextStatuses: [String: PlayerStatus] = [:]
        for player in loaded {
            if let data = store.loadQAPanel(playerId: player.id),
               let image = UIImage(data: data) {
                nextAvatars[player.id] = image
            }
            let template = BundledTemplates.template(forClassKey: player.classKey)
            nextStatuses[player.id] = PlayerStatus.derive(playerId: player.id,
                                                          template: template,
                                                          store: store)
        }
        avatars = nextAvatars
        statuses = nextStatuses
    }
}

#Preview {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("camp-comics-preview", isDirectory: true)
    let store = try! PlayerStore(root: tmp)
    return ContentView(store: store)
}

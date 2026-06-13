import SwiftUI
import CampComicsCore

/// Lightweight Settings sheet. Hosts the Slice K "re-summon" tutorial row and
/// a Debug section whose "Budget log" link surfaces the #90 per-comic spend
/// audit log on-device (no Mac tether).
struct SettingsView: View {
    let store: PlayerStore
    @Environment(\.themeKind) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var didReset: Bool = false

    private let onboardingStore = OnboardingOverlayStore()

    var body: some View {
        NavigationStack {
            ThemedBackground()
                .overlay {
                    List {
                        Section("Tutorial") {
                            Button(action: resetTutorial) {
                                HStack {
                                    Image(systemName: "hand.point.up.left")
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Show review tutorial")
                                            .font(theme.bodyFont(15))
                                        Text(didReset
                                             ? "Will show next time you open a review stack."
                                             : "Replay the swipe-to-review walkthrough.")
                                            .font(theme.captionFont(11))
                                            .foregroundStyle(theme.palette.inkSecondary)
                                    }
                                    Spacer()
                                    if didReset {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(theme.palette.positive)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }

                        Section("Debug") {
                            NavigationLink {
                                BudgetLogPlayerList(store: store)
                                    .environment(\.themeKind, theme)
                            } label: {
                                HStack {
                                    Image(systemName: "list.bullet.rectangle")
                                    Text("Budget log")
                                        .font(theme.bodyFont(15))
                                }
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }

    private func resetTutorial() {
        onboardingStore.hasSeen = false
        withAnimation { didReset = true }
    }
}

/// #90: player picker for the budget audit log. Each row drills into that
/// player's `_budget_log.json`.
private struct BudgetLogPlayerList: View {
    let store: PlayerStore
    @Environment(\.themeKind) private var theme

    private var players: [PlayerRecord] { (try? store.list()) ?? [] }

    var body: some View {
        ThemedBackground()
            .overlay {
                List {
                    if players.isEmpty {
                        Text("No players yet.")
                            .font(theme.bodyFont(15))
                            .foregroundStyle(theme.palette.inkSecondary)
                    }
                    ForEach(players, id: \.id) { player in
                        NavigationLink {
                            BudgetLogDetail(store: store, player: player)
                                .environment(\.themeKind, theme)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(player.playerName.isEmpty ? player.id : player.playerName)
                                    .font(theme.bodyFont(15))
                                Text("\(store.budgetLog(playerId: player.id).count) entries")
                                    .font(theme.captionFont(11))
                                    .foregroundStyle(theme.palette.inkSecondary)
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Budget log")
            .navigationBarTitleDisplayMode(.inline)
    }
}

/// #90: one player's spend/bounce/friction log, newest last, with a share
/// button that exports the raw `_budget_log.json`.
private struct BudgetLogDetail: View {
    let store: PlayerStore
    let player: PlayerRecord
    @Environment(\.themeKind) private var theme

    private var entries: [BudgetLogEntry] { store.budgetLog(playerId: player.id) }

    var body: some View {
        ThemedBackground()
            .overlay {
                List {
                    if entries.isEmpty {
                        Text("No budget events logged for this player.")
                            .font(theme.bodyFont(15))
                            .foregroundStyle(theme.palette.inkSecondary)
                    }
                    ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                        row(entry)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(player.playerName.isEmpty ? player.id : player.playerName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if FileManager.default.fileExists(atPath: store.budgetLogURL(playerId: player.id).path) {
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(item: store.budgetLogURL(playerId: player.id))
                    }
                }
            }
    }

    @ViewBuilder
    private func row(_ entry: BudgetLogEntry) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(entry.event.rawValue.uppercased())
                .font(theme.captionFont(11).monospaced())
                .foregroundStyle(color(for: entry.event))
                .frame(width: 70, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(entry.target) · \(entry.reason.rawValue) · cost \(entry.cost)")
                    .font(theme.bodyFont(14))
                Text("spent \(entry.spentAfter) · remaining \(entry.remainingAfter) · \(Self.timeFormatter.string(from: entry.timestamp))")
                    .font(theme.captionFont(11))
                    .foregroundStyle(theme.palette.inkSecondary)
            }
        }
    }

    private func color(for event: BudgetLogEntry.Event) -> Color {
        switch event {
        case .spend: return theme.palette.inkPrimary
        case .bounce: return theme.palette.danger
        case .friction: return theme.palette.accent
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d HH:mm:ss"
        return f
    }()
}

#Preview {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("settings-preview", isDirectory: true)
    return SettingsView(store: try! PlayerStore(root: tmp))
        .environment(\.themeKind, .questCard)
}

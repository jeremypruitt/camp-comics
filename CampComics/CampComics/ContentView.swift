import SwiftUI
import UIKit
import CampComicsCore

struct ContentView: View {
    let store: PlayerStore

    @State private var players: [PlayerRecord] = []
    @State private var avatars: [String: UIImage] = [:]
    @State private var statuses: [String: PlayerStatus] = [:]
    @State private var activePlayer: PlayerRecord?
    @State private var showingIntake = false

    var body: some View {
        NavigationStack {
            playersList
                .navigationTitle("Camp Comics")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showingIntake = true
                        } label: {
                            Label("New player", systemImage: "plus")
                        }
                    }
                }
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
                    }
                }
                .navigationDestination(item: $activePlayer) { player in
                    let template = BundledTemplates.template(forClassKey: player.classKey)
                    if store.hasQAPanel(playerId: player.id) {
                        PlayerDetailView(player: player, template: template, store: store)
                    } else {
                        CaptureFlowView(player: player, template: template, store: store)
                    }
                }
                .onAppear { refresh() }
                .onChange(of: activePlayer) { _, new in
                    if new == nil { refresh() }
                }
        }
    }

    @ViewBuilder
    private var playersList: some View {
        if players.isEmpty {
            ContentUnavailableView {
                Label("No players yet", systemImage: "person.crop.circle.badge.plus")
            } description: {
                Text("Tap the + button to start your first player.")
            }
        } else {
            List {
                ForEach(players, id: \.id) { player in
                    Button {
                        activePlayer = player
                    } label: {
                        PlayerRow(player: player,
                                  avatar: avatars[player.id],
                                  status: statuses[player.id])
                    }
                    .buttonStyle(.plain)
                }
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

private struct PlayerRow: View {
    let player: PlayerRecord
    let avatar: UIImage?
    let status: PlayerStatus?

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                if let avatar {
                    Image(uiImage: avatar)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                } else {
                    Circle().fill(Color.accentColor.opacity(0.18))
                    Text(initials).font(.headline).foregroundStyle(.tint)
                }
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(headline).font(.headline)
                HStack(spacing: 8) {
                    Text("\(player.classKey.capitalized) · \(player.id)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let status {
                        StatusPill(status: status)
                    }
                }
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    private var headline: String {
        if player.characterName.isEmpty {
            return player.playerName
        }
        return "\(player.characterName) (\(player.playerName))"
    }

    private var initials: String {
        let source = player.characterName.isEmpty ? player.playerName : player.characterName
        let first = source.split(separator: " ").first.map(String.init) ?? ""
        return String(first.prefix(1)).uppercased()
    }
}

private struct StatusPill: View {
    let status: PlayerStatus

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(tint.opacity(0.18), in: Capsule())
            .foregroundStyle(tint)
    }

    private var label: String {
        switch status {
        case .captured: return "captured"
        case .generating(let done, let total): return "generating \(done)/\(total)"
        case .done: return "done"
        case .needsPhoto: return "needs-photo"
        }
    }

    private var tint: Color {
        switch status {
        case .captured: return .secondary
        case .generating: return .blue
        case .done: return .green
        case .needsPhoto: return .orange
        }
    }
}

#Preview {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("camp-comics-preview", isDirectory: true)
    let store = try! PlayerStore(root: tmp)
    return ContentView(store: store)
}

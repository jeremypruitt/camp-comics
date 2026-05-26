import SwiftUI
import UIKit
import CampComicsCore

struct ContentView: View {
    let store: PlayerStore

    @State private var players: [PlayerRecord] = []
    @State private var avatars: [String: UIImage] = [:]
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
                        PlayerRow(player: player, avatar: avatars[player.id])
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func refresh() {
        let loaded = (try? store.list()) ?? []
        players = loaded
        var next: [String: UIImage] = [:]
        for player in loaded {
            if let data = store.loadQAPanel(playerId: player.id),
               let image = UIImage(data: data) {
                next[player.id] = image
            }
        }
        avatars = next
    }
}

private struct PlayerRow: View {
    let player: PlayerRecord
    let avatar: UIImage?

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

            VStack(alignment: .leading, spacing: 2) {
                Text(headline).font(.headline)
                Text("\(player.classKey.capitalized) · \(player.id)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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

#Preview {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("camp-comics-preview", isDirectory: true)
    let store = try! PlayerStore(root: tmp)
    return ContentView(store: store)
}

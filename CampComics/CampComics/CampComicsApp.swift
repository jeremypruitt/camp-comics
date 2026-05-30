import SwiftUI
import FirebaseCore
import CampComicsCore

@main
struct CampComicsApp: App {
    private let store: PlayerStore

    // Player-list layout preference (grid/list).
    @AppStorage("partyLayout") private var rawLayout: String = PartyLayout.grid.rawValue

    init() {
        FirebaseApp.configure()
        do {
            store = try PlayerStore(root: PlayerStore.documentsRoot())
        } catch {
            fatalError("Failed to initialize PlayerStore: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            let layout = PartyLayout(rawValue: rawLayout) ?? .grid
            ContentView(store: store)
                .environment(\.themeKind, .questCard)
                .environment(\.partyLayout, layout)
                .preferredColorScheme(.dark)
                .partyLayoutSwitcherOverlay(layoutBinding)
        }
    }

    private var layoutBinding: Binding<PartyLayout> {
        Binding(
            get: { PartyLayout(rawValue: rawLayout) ?? .grid },
            set: { rawLayout = $0.rawValue }
        )
    }
}

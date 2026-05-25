import SwiftUI
import FirebaseCore
import CampComicsCore

@main
struct CampComicsApp: App {
    private let store: PlayerStore

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
            ContentView(store: store)
        }
    }
}

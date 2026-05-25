import SwiftUI
import FirebaseCore

@main
struct CampComicsApp: App {
    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

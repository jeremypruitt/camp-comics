import SwiftUI

struct ContentView: View {
    @State private var activePlayer: PlayerProfile?

    var body: some View {
        NavigationStack {
            IntakeFormView { profile in
                activePlayer = profile
            }
            .navigationDestination(item: $activePlayer) { profile in
                CaptureFlowView(
                    player: profile,
                    template: BundledTemplates.template(forClassKey: profile.classKey)
                )
            }
        }
    }
}

#Preview {
    ContentView()
}

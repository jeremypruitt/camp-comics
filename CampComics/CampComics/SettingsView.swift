import SwiftUI
import CampComicsCore

/// Lightweight Settings sheet. Today it only hosts the Slice K "re-summon"
/// row for the swipe-review tutorial; future slices can add more rows
/// (BYO key paste, billing-mode picker, debug toggles).
struct SettingsView: View {
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

#Preview {
    SettingsView()
        .environment(\.themeKind, .questCard)
}

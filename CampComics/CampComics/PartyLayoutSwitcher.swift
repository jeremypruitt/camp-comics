import SwiftUI

// Floating segmented [Grid | List] pill that swaps the player-list layout.
// Persisted via `@AppStorage("partyLayout")`. Mounted at the app root in
// `CampComicsApp`. Visible in all build configurations.
//
// Long-term: move this into the player-list nav toolbar (more iOS-native)
// once the rest of the chrome work settles.

struct PartyLayoutSwitcher: View {
    @Binding var current: PartyLayout

    var body: some View {
        HStack(spacing: 0) {
            ForEach(PartyLayout.allCases) { layout in
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        current = layout
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: layout.systemImage)
                            .font(.system(size: 13, weight: .semibold))
                        Text(layout.displayName)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(current == layout ? Color(hex: 0x0E1822) : .white.opacity(0.7))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(
                        Capsule()
                            .fill(current == layout ? Color(hex: 0xD4A744) : .clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Capsule().fill(Color.black.opacity(0.82)))
        .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 6)
        .padding(.bottom, 18)
    }
}

/// View modifier that mounts the switcher above all content. Use at the app
/// root.
struct PartyLayoutSwitcherOverlay: ViewModifier {
    @Binding var current: PartyLayout

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                PartyLayoutSwitcher(current: $current)
            }
    }
}

extension View {
    func partyLayoutSwitcherOverlay(_ current: Binding<PartyLayout>) -> some View {
        modifier(PartyLayoutSwitcherOverlay(current: current))
    }
}

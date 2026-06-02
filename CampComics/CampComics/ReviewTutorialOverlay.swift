import SwiftUI
import CampComicsCore

/// First-launch tutorial overlay over `ReviewDeckView` that teaches the
/// ADR-0010 inverted swipe vocabulary. Demonstrates each `OverlayHint` with a
/// SwiftUI-only ghost-finger animation — no GIFs, no Lottie. Dismissable via
/// tap, swipe, or the "Got it" button; persists via `OnboardingOverlayStore`.
struct ReviewTutorialOverlay: View {
    let hints: [OverlayHint]
    let onDismiss: () -> Void

    @Environment(\.themeKind) private var theme
    @State private var fingerOffset: CGSize = .zero
    @State private var fingerOpacity: Double = 0
    @State private var hintIndex: Int = 0

    var body: some View {
        ZStack {
            // Dim backdrop — tap or drag anywhere outside the "Got it" button
            // dismisses. Drag dismissal must not block the underlying swipe
            // surface; we only listen for the gesture-end.
            Color.black.opacity(0.72)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }
                .gesture(
                    DragGesture(minimumDistance: 10).onEnded { _ in onDismiss() }
                )

            // Foreground is hard-coded white because the backdrop is always a
            // dark scrim — using the theme's `paper` color would render dark
            // text on dark backdrop in dark mode (invisible).
            VStack(spacing: 24) {
                Spacer()

                Text("Swipe to review")
                    .font(theme.displayFont(28))
                    .foregroundStyle(Color.white)

                if let hint = currentHint {
                    Text(hint.title)
                        .font(theme.headingFont(18))
                        .foregroundStyle(Color.white.opacity(0.95))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    Text(hint.detail)
                        .font(theme.captionFont(14))
                        .foregroundStyle(Color.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 48)
                }

                ghostFinger
                    .frame(width: 240, height: 180)

                Spacer()

                Button(action: onDismiss) {
                    Text("Got it")
                        .font(theme.headingFont(16))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 12)
                        .background(
                            Capsule().stroke(Color.white, lineWidth: 1.4)
                        )
                }
                .buttonStyle(.plain)
                .padding(.bottom, 48)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { startAnimating() }
    }

    private var currentHint: OverlayHint? {
        guard !hints.isEmpty else { return nil }
        return hints[hintIndex % hints.count]
    }

    private var ghostFinger: some View {
        Image(systemName: "hand.point.up.left.fill")
            .font(.system(size: 56))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.4), radius: 6, x: 0, y: 2)
            .offset(fingerOffset)
            .opacity(fingerOpacity)
    }

    private func startAnimating() {
        guard let hint = currentHint else { return }
        animate(hint: hint)
    }

    private func animate(hint: OverlayHint) {
        fingerOffset = hint.startOffset
        fingerOpacity = 0
        withAnimation(.easeIn(duration: 0.2)) {
            fingerOpacity = 1
        }
        withAnimation(.easeInOut(duration: 1.1).delay(0.2)) {
            fingerOffset = hint.endOffset
        }
        withAnimation(.easeOut(duration: 0.25).delay(1.4)) {
            fingerOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.9) {
            hintIndex += 1
            if let next = currentHint {
                animate(hint: next)
            }
        }
    }
}

/// One animation beat in the tutorial. ADR-0010 collapsed the gesture set to
/// LEFT-accept / RIGHT-reroll / UP-DOWN-cycle; long-press Re-prompt was dropped
/// from the active surface so its hint is gone.
enum OverlayHint: CaseIterable, Hashable {
    case acceptSwipeLeft
    case rerollSwipeRight

    var title: String {
        switch self {
        case .acceptSwipeLeft: return "Swipe left to accept"
        case .rerollSwipeRight: return "Swipe right to re-roll"
        }
    }

    var detail: String {
        switch self {
        case .acceptSwipeLeft:
            return "Like a panel? Flick it to the left. The next card in the deck slides up."
        case .rerollSwipeRight:
            return "Want a different take? Flick it to the right. The model rolls a fresh candidate."
        }
    }

    var startOffset: CGSize {
        switch self {
        case .acceptSwipeLeft: return CGSize(width: 80, height: 0)
        case .rerollSwipeRight: return CGSize(width: -80, height: 0)
        }
    }

    var endOffset: CGSize {
        switch self {
        case .acceptSwipeLeft: return CGSize(width: -80, height: 0)
        case .rerollSwipeRight: return CGSize(width: 80, height: 0)
        }
    }
}

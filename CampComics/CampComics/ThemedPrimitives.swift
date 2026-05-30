import SwiftUI

// Themed primitives — backgrounds, cards, buttons, pills. Locked to the
// Quest Card palette + Optima typography (see Theme.swift).

// MARK: - Background

struct ThemedBackground: View {
    var body: some View {
        let p = ThemePalette.questCard
        ZStack {
            p.paper
            RadialGradient(
                colors: [p.accent.opacity(0.18), .clear],
                center: .topLeading, startRadius: 60, endRadius: 360
            )
            RadialGradient(
                colors: [p.accent.opacity(0.12), .clear],
                center: .bottomTrailing, startRadius: 60, endRadius: 400
            )
            Canvas { ctx, size in
                let g = p.accent.opacity(0.07)
                let stepX: CGFloat = 36
                let stepY: CGFloat = 44
                var y: CGFloat = 0
                while y < size.height {
                    let xOff: CGFloat = (Int(y / stepY) % 2 == 0) ? 0 : stepX / 2
                    var x: CGFloat = xOff
                    while x < size.width {
                        var path = Path()
                        path.move(to: CGPoint(x: x, y: y - 3))
                        path.addLine(to: CGPoint(x: x + 3, y: y))
                        path.addLine(to: CGPoint(x: x, y: y + 3))
                        path.addLine(to: CGPoint(x: x - 3, y: y))
                        path.closeSubpath()
                        ctx.stroke(path, with: .color(g), lineWidth: 0.6)
                        x += stepX
                    }
                    y += stepY
                }
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Card

struct ThemedCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        let p = ThemePalette.questCard
        content()
            .padding(16)
            .background(
                ZStack {
                    p.surface
                    LinearGradient(
                        colors: [p.accent.opacity(0.10), .clear],
                        startPoint: .top, endPoint: .bottom
                    )
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(p.accent, lineWidth: 1)
                    .padding(3)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(p.accent.opacity(0.55), lineWidth: 0.6)
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .shadow(color: .black.opacity(0.45), radius: 10, x: 0, y: 6)
            .foregroundStyle(p.inkPrimary)
    }
}

// MARK: - Primary button

struct ThemedPrimaryButton: View {
    let title: String
    let systemImage: String?
    let isLoading: Bool
    let isEnabled: Bool
    let action: () -> Void

    init(_ title: String,
         systemImage: String? = nil,
         isLoading: Bool = false,
         isEnabled: Bool = true,
         action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isLoading = isLoading
        self.isEnabled = isEnabled
        self.action = action
    }

    var body: some View {
        let p = ThemePalette.questCard
        let fg = Color(hex: 0x1A1206)
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView().tint(fg)
                } else if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
                    .font(ThemeKind.questCard.headingFont(17))
                    .tracking(2)
                    .textCase(.uppercase)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                LinearGradient(
                    colors: [Color(hex: 0xE2B454), p.accent, Color(hex: 0xB7892E)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color(hex: 0x261A07), lineWidth: 1.4)
                    .padding(2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(p.accent.opacity(0.7), lineWidth: 0.7)
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .foregroundStyle(fg)
            .shadow(color: Color(hex: 0xD4A744).opacity(0.45), radius: 12, x: 0, y: 4)
            .scaleEffect(isEnabled ? 1 : 0.98)
            .opacity(isEnabled ? 1 : 0.55)
        }
        .disabled(!isEnabled)
        .buttonStyle(.plain)
    }
}

// MARK: - Status pill

struct ThemedPill: View {
    let label: String
    let tint: Color

    var body: some View {
        Text(label.uppercased())
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .tracking(2)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 2)
                    .fill(tint.opacity(0.16))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(tint, lineWidth: 0.8)
            )
            .foregroundStyle(tint)
    }
}

// MARK: - AnyShape compatibility shim

struct AnyShape: Shape {
    private let pathBuilder: (CGRect) -> Path
    init<S: Shape>(_ shape: S) {
        self.pathBuilder = { rect in shape.path(in: rect) }
    }
    func path(in rect: CGRect) -> Path { pathBuilder(rect) }
}

import SwiftUI

// Camp Comics visual system — "Quest Card" treatment.
//
// Modern tabletop / Critical Role / D&D Beyond aesthetic. Deep navy slate
// background, burnished gold accents, bone-white text, Optima typography.
//
// Single theme by design. The player list has two layouts (`.grid` for the
// 2-col Quest Cards, `.list` for the compact initiative-tracker rows in the
// same chrome). Other screens are theme-locked.
//
// `ThemeKind` and the `themeKind` env value are kept (single-case) so the
// callsites are easy to extend if a second theme is ever introduced.

enum ThemeKind: String, CaseIterable, Identifiable {
    case questCard

    var id: String { rawValue }

    var displayName: String { "Quest Card" }

    var preferredColorScheme: ColorScheme { .dark }
}

enum PartyLayout: String, CaseIterable, Identifiable {
    case grid, list

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .grid: return "Grid"
        case .list: return "List"
        }
    }

    var systemImage: String {
        switch self {
        case .grid: return "square.grid.2x2.fill"
        case .list: return "list.bullet"
        }
    }

    func toggled() -> PartyLayout { self == .grid ? .list : .grid }
}

// MARK: - Environment

private struct ThemeKindKey: EnvironmentKey {
    static let defaultValue: ThemeKind = .questCard
}

private struct PartyLayoutKey: EnvironmentKey {
    static let defaultValue: PartyLayout = .grid
}

extension EnvironmentValues {
    var themeKind: ThemeKind {
        get { self[ThemeKindKey.self] }
        set { self[ThemeKindKey.self] = newValue }
    }

    var partyLayout: PartyLayout {
        get { self[PartyLayoutKey.self] }
        set { self[PartyLayoutKey.self] = newValue }
    }
}

// MARK: - Palette

struct ThemePalette {
    let paper: Color
    let surface: Color
    let surfaceRaised: Color
    let inkPrimary: Color
    let inkSecondary: Color
    let accent: Color
    let accentSoft: Color
    let positive: Color
    let warning: Color
    let danger: Color
    let divider: Color

    // Quest Card — modern tabletop / Critical Role / D&D Beyond aesthetic.
    // Deep navy slate background, burnished gold accents, bone-white text.
    static let questCard = ThemePalette(
        paper:         Color(hex: 0x0E1822),
        surface:       Color(hex: 0x16243A),
        surfaceRaised: Color(hex: 0x1D2E47),
        inkPrimary:    Color(hex: 0xF4ECD6),
        inkSecondary:  Color(hex: 0xA89B7A),
        accent:        Color(hex: 0xD4A744),
        accentSoft:    Color(hex: 0x8FA4C5),
        positive:      Color(hex: 0x88C66E),
        warning:       Color(hex: 0xE6A23C),
        danger:        Color(hex: 0xD46A6A),
        divider:       Color(hex: 0xD4A744).opacity(0.45)
    )
}

extension ThemeKind {
    var palette: ThemePalette { .questCard }
}

// MARK: - Typography (Optima family — Quest Card spec)

extension ThemeKind {
    func displayFont(_ size: CGFloat) -> Font {
        .custom("Optima-ExtraBlack", size: size)
    }

    func headingFont(_ size: CGFloat) -> Font {
        .custom("Optima-Bold", size: size)
    }

    func bodyFont(_ size: CGFloat) -> Font {
        .custom("Optima-Regular", size: size)
    }

    func captionFont(_ size: CGFloat) -> Font {
        .system(size: size, weight: .medium, design: .monospaced)
    }
}

// MARK: - Color hex helper

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(red: r, green: g, blue: b, opacity: alpha)
    }
}

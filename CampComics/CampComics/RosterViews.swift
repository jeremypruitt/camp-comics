import SwiftUI
import UIKit
import CampComicsCore

// Player-list views. Two layouts under the Quest Card visual system:
//   `.grid` → QuestCardRoster     (2-col cards with sealed banner + heraldic
//                                  shield portrait + stat-line footer)
//   `.list` → QuestCardListRoster (compact rows: initiative roundel, circle
//                                  portrait, name, class abbr, status)
// Both share the same palette + Optima typography. Layout toggle persists
// in `PartyLayout` AppStorage; switcher lives at the root in CampComicsApp.

// MARK: - Shared row data (read-only)

struct RosterEntry: Identifiable {
    let player: PlayerRecord
    let avatar: UIImage?
    let status: PlayerStatus?
    var id: String { player.id }

    var headline: String {
        if player.characterName.isEmpty { return player.playerName }
        return "\(player.characterName) (\(player.playerName))"
    }

    var characterOnly: String {
        player.characterName.isEmpty ? player.playerName : player.characterName
    }

    var initial: String {
        let source = characterOnly
        let first = source.split(separator: " ").first.map(String.init) ?? ""
        return String(first.prefix(1)).uppercased()
    }
}

// MARK: - Status colour resolver

extension PlayerStatus {
    func tint(in theme: ThemeKind) -> Color {
        let p = theme.palette
        switch self {
        case .captured:   return p.inkSecondary
        case .generating: return p.accentSoft == .clear ? p.accent : p.accentSoft
        case .done:       return p.positive
        case .needsPhoto: return p.warning
        }
    }

    var label: String {
        switch self {
        case .captured: return "captured"
        case .generating(let done, let total): return "generating \(done)/\(total)"
        case .done: return "done"
        case .needsPhoto: return "needs photo"
        }
    }
}

// MARK: - Empty roster

struct EmptyRoster: View {
    @Environment(\.themeKind) private var theme
    let onAdd: () -> Void

    var body: some View {
        let p = theme.palette
        VStack(spacing: 16) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 56, weight: .semibold))
                .foregroundStyle(p.inkSecondary)
            Text("Party Not Yet Formed")
                .font(theme.headingFont(22))
                .foregroundStyle(p.inkPrimary)
            Text("Roll for initiative — add your first hero to the party.")
                .font(theme.bodyFont(15))
                .foregroundStyle(p.inkSecondary)
                .multilineTextAlignment(.center)
            ThemedPrimaryButton("Add your first hero", systemImage: "plus.circle.fill", action: onAdd)
                .padding(.horizontal, 40)
                .padding(.top, 8)
        }
        .padding(.horizontal, 32)
        .padding(.top, 40)
    }
}

// MARK: - Header  (shared across grid and list modes)

struct QuestCardHeader: View {
    let onAdd: () -> Void
    var trialRemaining: Int? = nil
    private let p = ThemePalette.questCard
    private let theme: ThemeKind = .questCard

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 0) {
                Text("ADV. PARTY · VOL. I")
                    .font(theme.captionFont(10))
                    .tracking(4)
                    .foregroundStyle(p.accent)
                Spacer()
                Button(action: onAdd) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                        Text("Recruit").tracking(1.5)
                    }
                    .font(theme.headingFont(13))
                    .foregroundStyle(p.accent)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(p.accent, lineWidth: 0.9)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(p.accent.opacity(0.55), lineWidth: 0.6)
                            .padding(-3)
                    )
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: 6) {
                Text("The Party")
                    .font(theme.displayFont(48))
                    .foregroundStyle(p.inkPrimary)
                Text("Active members of the campaign.")
                    .font(theme.captionFont(12))
                    .italic()
                    .foregroundStyle(p.inkSecondary)
                if let remaining = trialRemaining {
                    Text(trialChipCopy(remaining: remaining))
                        .font(theme.captionFont(10))
                        .tracking(2)
                        .foregroundStyle(p.accent.opacity(0.85))
                        .padding(.top, 2)
                }
            }

            QuestCardRule(color: p.accent)
        }
        .padding(.horizontal, 22)
        .padding(.top, 56)
        .padding(.bottom, 8)
    }

    private func trialChipCopy(remaining: Int) -> String {
        let noun = remaining == 1 ? "COMIC" : "COMICS"
        return "\(remaining) FREE \(noun) REMAINING"
    }
}

private struct QuestCardRule: View {
    let color: Color
    var body: some View {
        HStack(spacing: 8) {
            Rectangle().fill(color.opacity(0.55)).frame(height: 0.8)
            ZStack {
                RegularPolygon(sides: 6).fill(color.opacity(0.18))
                RegularPolygon(sides: 6).stroke(color, lineWidth: 0.8)
            }
            .frame(width: 14, height: 14)
            Rectangle().fill(color.opacity(0.55)).frame(height: 0.8)
        }
        .padding(.horizontal, 6)
    }
}

// MARK: - GRID layout (current Quest Card)

struct QuestCardRoster: View {
    let entries: [RosterEntry]
    let onSelect: (PlayerRecord) -> Void
    private let p = ThemePalette.questCard
    private let theme: ThemeKind = .questCard

    private let cols = [GridItem(.flexible(), spacing: 14),
                        GridItem(.flexible(), spacing: 14)]

    var body: some View {
        LazyVGrid(columns: cols, spacing: 16) {
            ForEach(entries) { entry in
                Button { onSelect(entry.player) } label: { card(entry: entry) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 6)
        .padding(.bottom, 24)
    }

    private func card(entry: RosterEntry) -> some View {
        let level = String(format: "%02d", abs(entry.id.hashValue) % 9 + 1)
        return VStack(spacing: 0) {
            HStack {
                Text(entry.player.classKey.uppercased())
                    .font(theme.headingFont(11))
                    .tracking(3)
                Spacer()
                Text("LV \(level)")
                    .font(theme.captionFont(10))
                    .tracking(1.5)
            }
            .foregroundStyle(p.paper)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(p.accent)

            ZStack {
                LinearGradient(colors: [p.surfaceRaised, p.surface],
                               startPoint: .top, endPoint: .bottom)
                ShieldFrame()
                    .stroke(p.accent, lineWidth: 1.4)
                    .frame(width: 84, height: 100)
                portrait(entry: entry)
                    .frame(width: 72, height: 86)
                    .clipShape(ShieldFrame())
                    .overlay(ShieldFrame().stroke(p.accent.opacity(0.6), lineWidth: 0.6))
            }
            .frame(height: 130)

            VStack(spacing: 6) {
                Text(entry.characterOnly)
                    .font(theme.displayFont(17))
                    .foregroundStyle(p.inkPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.center)
                if let status = entry.status {
                    ThemedPill(label: status.label, tint: status.tint(in: theme))
                } else {
                    Text(entry.player.id)
                        .font(theme.captionFont(10))
                        .foregroundStyle(p.inkSecondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(p.surface)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(p.accent, lineWidth: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(p.accent.opacity(0.55), lineWidth: 0.6)
                .padding(-3)
        )
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .shadow(color: .black.opacity(0.45), radius: 10, x: 0, y: 6)
    }

    @ViewBuilder
    private func portrait(entry: RosterEntry) -> some View {
        if let avatar = entry.avatar {
            Image(uiImage: avatar).resizable().scaledToFill()
        } else {
            ZStack {
                p.surfaceRaised
                Text(entry.initial)
                    .font(theme.displayFont(36))
                    .foregroundStyle(p.accent)
            }
        }
    }
}

// MARK: - LIST layout (initiative-tracker compact rows, Quest Card chrome)

struct QuestCardListRoster: View {
    let entries: [RosterEntry]
    let onSelect: (PlayerRecord) -> Void
    private let p = ThemePalette.questCard
    private let theme: ThemeKind = .questCard

    var body: some View {
        VStack(spacing: 8) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { idx, entry in
                Button { onSelect(entry.player) } label: { row(idx: idx, entry: entry) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 24)
    }

    private func row(idx: Int, entry: RosterEntry) -> some View {
        HStack(spacing: 12) {
            // Initiative number roundel.
            ZStack {
                Circle().fill(p.surfaceRaised)
                Circle().stroke(p.accent, lineWidth: 0.9)
                Text(String(format: "%02d", idx + 1))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(p.accent)
            }
            .frame(width: 34, height: 34)

            // Portrait — circle. Same height as the init roundel + a touch
            // wider; gold ring keeps the Quest Card DNA without the shield's
            // height mismatch.
            portrait(entry: entry)
                .frame(width: 42, height: 42)

            // Name + class abbr stat line.
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.characterOnly)
                    .font(theme.headingFont(17))
                    .foregroundStyle(p.inkPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: 6) {
                    Text(classAbbr(entry.player.classKey))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .tracking(1.4)
                        .foregroundStyle(p.accent)
                    Text("·").foregroundStyle(p.inkSecondary)
                    Text(entry.player.id.replacingOccurrences(of: "player_", with: "#"))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(p.inkSecondary)
                }
            }
            .layoutPriority(0)

            Spacer(minLength: 10)

            if let status = entry.status {
                ThemedPill(label: status.label, tint: status.tint(in: theme))
                    .layoutPriority(1)
                    .fixedSize()
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(p.accent.opacity(0.7))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(p.surface)
                .overlay(
                    LinearGradient(colors: [p.accent.opacity(0.08), .clear],
                                   startPoint: .top, endPoint: .bottom)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(p.accent.opacity(0.55), lineWidth: 0.7)
        )
        .shadow(color: .black.opacity(0.35), radius: 4, x: 0, y: 2)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func portrait(entry: RosterEntry) -> some View {
        ZStack {
            Circle().fill(p.surfaceRaised)
            if let avatar = entry.avatar {
                Image(uiImage: avatar)
                    .resizable().scaledToFill()
                    .clipShape(Circle())
            } else {
                Text(entry.initial)
                    .font(theme.displayFont(18))
                    .foregroundStyle(p.accent)
            }
            Circle().stroke(p.accent, lineWidth: 1)
        }
    }

    private func classAbbr(_ key: String) -> String {
        switch key {
        case "druid":     return "DRU"
        case "warrior":   return "WAR"
        case "wizard":    return "WIZ"
        case "bard":      return "BRD"
        case "healer":    return "HLR"
        case "trickster": return "TRI"
        default:          return key.uppercased().prefix(3).description
        }
    }
}

// MARK: - Shared shapes

/// Heraldic shield silhouette — wide top, tapered bottom.
struct ShieldFrame: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r: CGFloat = rect.width * 0.18
        p.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + r),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY + rect.height * 0.1))
        p.addQuadCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY - rect.height * 0.15)
        )
        p.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.1),
            control: CGPoint(x: rect.minX, y: rect.maxY - rect.height * 0.15)
        )
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        p.addQuadCurve(
            to: CGPoint(x: rect.minX + r, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        p.closeSubpath()
        return p
    }
}

struct RegularPolygon: Shape {
    let sides: Int
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        for i in 0..<sides {
            let angle = (Double(i) / Double(sides)) * 2 * .pi - .pi / 2
            let point = CGPoint(x: center.x + CGFloat(cos(angle)) * radius,
                                y: center.y + CGFloat(sin(angle)) * radius)
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

import SwiftUI
import UIKit
import CampComicsCore

/// Slice-11d grid overlay. A *snapshot* of every target's disk state — panels
/// 1..12 in an adaptive `LazyVGrid`, cover in its own row below to honour the
/// "sibling, not panel 13" stance from CONTEXT.md. Read-only and stateless:
/// no observation of in-flight generation, no live refresh. Operator dismisses
/// + reopens to see new state.
struct PanelGridView: View {
    @Environment(\.themeKind) private var theme
    let player: PlayerRecord
    let template: ClassTemplate
    let store: PlayerStore
    let onSelect: (PanelTargetID) -> Void

    private var panelTargets: [PanelTarget] {
        template.panels.map { .panel(n: $0.n, spec: $0) }
    }

    private var coverTarget: PanelTarget { .cover(spec: template.cover) }

    var body: some View {
        let p = theme.palette
        ZStack {
            ThemedBackground()
            ScrollView {
                VStack(spacing: 22) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)],
                              spacing: 14) {
                        ForEach(panelTargets, id: \.id) { target in
                            Button {
                                onSelect(target.id)
                            } label: {
                                Cell(target: target,
                                     playerId: player.id,
                                     store: store,
                                     width: 100,
                                     height: 100)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    VStack(spacing: 10) {
                        Text(coverLabel)
                            .font(theme.captionFont(11))
                            .tracking(3)
                            .foregroundStyle(p.accent)
                        Button {
                            onSelect(coverTarget.id)
                        } label: {
                            Cell(target: coverTarget,
                                 playerId: player.id,
                                 store: store,
                                 width: 220,
                                 height: coverHeight(width: 220))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
                .padding(.bottom, 120)
            }
        }
    }

    private var coverLabel: String { "·  COVER  ·" }

    private func coverHeight(width: CGFloat) -> CGFloat {
        let parts = template.cover.aspect.split(separator: ":")
        guard parts.count == 2,
              let w = Double(parts[0]),
              let h = Double(parts[1]),
              w > 0 else {
            return width * 4 / 3
        }
        return width * CGFloat(h / w)
    }
}

private struct Cell: View {
    @Environment(\.themeKind) private var theme
    let target: PanelTarget
    let playerId: String
    let store: PlayerStore
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        let p = theme.palette
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: cellCorner, style: .continuous)
                    .fill(p.surface)
                if let image = thumbnail() {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: cellCorner, style: .continuous))
                }
            }
            .frame(width: width, height: height)
            .overlay(
                RoundedRectangle(cornerRadius: cellCorner, style: .continuous)
                    .stroke(p.divider.opacity(0.7), lineWidth: theme == .questCard ? 2 : 0.8)
            )
            .shadow(color: shadowColor, radius: shadowRadius, x: shadowOffsetX, y: shadowOffsetY)
            VStack(spacing: 4) {
                Text(label)
                    .font(theme.headingFont(13))
                    .foregroundStyle(p.inkPrimary)
                ThemedPill(label: pillLabel, tint: pillTint)
            }
        }
        .contentShape(Rectangle())
    }

    private var cellCorner: CGFloat { 4 }

    private var shadowColor: Color { Color.black.opacity(0.45) }

    private var shadowRadius: CGFloat { 6 }
    private var shadowOffsetX: CGFloat { 0 }
    private var shadowOffsetY: CGFloat { 3 }

    private var pillLabel: String {
        switch status {
        case .accepted: return "accepted"
        case .reviewing: return "reviewing"
        case .missingPhoto: return "needs photo"
        case .unstarted: return "unstarted"
        }
    }

    private var pillTint: Color {
        let p = theme.palette
        switch status {
        case .accepted: return p.positive
        case .reviewing: return p.accent
        case .missingPhoto: return p.warning
        case .unstarted: return p.inkSecondary
        }
    }

    private var label: String {
        switch target {
        case .panel(let n, _): return "\(n)"
        case .cover: return "Cover"
        }
    }

    private var status: PanelGridCellStatus {
        PanelGridCellStatus.derive(target: target, playerId: playerId, store: store)
    }

    /// Match what `PanelReviewView.reloadCurrentTarget` shows on entry:
    /// accepted PNG if present, else the last (highest-indexed) candidate.
    /// Either could be absent in `.missingPhoto` / `.unstarted` — those render
    /// the empty rounded rect placeholder.
    private func thumbnail() -> UIImage? {
        if let data = store.loadPanel(playerId: playerId, target: target.id),
           let image = UIImage(data: data) {
            return image
        }
        if let last = store.listCandidates(playerId: playerId, target: target.id).last,
           let data = try? Data(contentsOf: last.url),
           let image = UIImage(data: data) {
            return image
        }
        return nil
    }
}


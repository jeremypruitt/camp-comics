import SwiftUI
import UIKit
import CampComicsCore

/// Slice-11d grid overlay. A *snapshot* of every target's disk state — panels
/// 1..12 in an adaptive `LazyVGrid`, cover in its own row below to honour the
/// "sibling, not panel 13" stance from CONTEXT.md. Read-only and stateless:
/// no observation of in-flight generation, no live refresh. Operator dismisses
/// + reopens to see new state.
struct PanelGridView: View {
    let player: PlayerRecord
    let template: ClassTemplate
    let store: PlayerStore
    let onSelect: (PanelTargetID) -> Void

    private var panelTargets: [PanelTarget] {
        template.panels.map { .panel(n: $0.n, spec: $0) }
    }

    private var coverTarget: PanelTarget { .cover(spec: template.cover) }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)],
                          spacing: 12) {
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
                VStack(spacing: 8) {
                    Text("Cover")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
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
        }
        .background(Color(.systemGroupedBackground))
    }

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
    let target: PanelTarget
    let playerId: String
    let store: PlayerStore
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(.tertiarySystemGroupedBackground))
                if let image = thumbnail() {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .frame(width: width, height: height)
            VStack(spacing: 4) {
                Text(label).font(.caption.weight(.semibold))
                Pill(status: status)
            }
        }
        .contentShape(Rectangle())
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

private struct Pill: View {
    let status: PanelGridCellStatus

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(tint.opacity(0.18), in: Capsule())
            .foregroundStyle(tint)
    }

    private var label: String {
        switch status {
        case .accepted: return "accepted"
        case .reviewing: return "reviewing"
        case .missingPhoto: return "needs-photo"
        case .unstarted: return "unstarted"
        }
    }

    private var tint: Color {
        switch status {
        case .accepted: return .green
        case .reviewing: return .blue
        case .missingPhoto: return .orange
        case .unstarted: return .secondary
        }
    }
}

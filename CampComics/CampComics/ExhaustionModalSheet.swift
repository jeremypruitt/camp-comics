import SwiftUI
import CampComicsCore

/// Slice-23 exhaustion modal: surfaces when the per-comic generation budget
/// hits zero in `BillingMode.sponsored` and offers the two escape hatches
/// from ADR-0008 — accept any pending candidates and finalize, or flip to
/// bring-your-own-key mode so the operator can keep generating against their
/// own Gemini Developer API key.
///
/// "Accept current candidates" walks every panel + cover slot; any unaccepted
/// slot with at least one candidate in `_candidates/{stem}/` gets the most
/// recent candidate promoted to `panel_NN.png` / `cover.png`. If every slot
/// is then filled, the parent's `onFinalize` closure fires (which pops back
/// to `PlayerDetailView` and kicks PDF render). Otherwise the modal stays
/// open and surfaces the still-missing slots as tappable rows that navigate
/// back to that target.
struct ExhaustionModalSheet: View {
    let player: PlayerRecord
    let template: ClassTemplate
    let store: PlayerStore
    @Binding var isPresented: Bool
    let onFinalize: () -> Void
    let onSwitchToBYO: () -> Void
    let onSelectMissing: (PanelTarget) -> Void

    @State private var stillMissing: [PanelTarget] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("This comic has used all \(GenerationBudget.limit) sponsored generation calls. Pick how to keep going.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 10) {
                        Button {
                            attemptFinalize()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Accept current candidates and finalize")
                                    .font(.body.weight(.semibold))
                                Text("Lock in the most recent candidate for every slot, then build the PDF.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Color.accentColor.opacity(0.15),
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        Button {
                            onSwitchToBYO()
                            isPresented = false
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Switch to bring-your-own-key mode")
                                    .font(.body.weight(.semibold))
                                Text("Continue generating against your own Gemini API key. Uncapped.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Color(.secondarySystemGroupedBackground),
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }

                    if !stillMissing.isEmpty {
                        stillMissingSection
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Out of budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { isPresented = false }
                }
            }
        }
    }

    private var stillMissingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Still missing — tap to jump to that slot")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.orange)
            ForEach(stillMissing, id: \.id) { target in
                Button {
                    isPresented = false
                    onSelectMissing(target)
                } label: {
                    HStack {
                        Text(label(for: target))
                            .font(.body)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(Color(.secondarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func attemptFinalize() {
        for target in allTargets where !store.hasPanel(playerId: player.id, target: target.id) {
            let candidates = store.listCandidates(playerId: player.id, target: target.id)
            if let last = candidates.last {
                try? store.acceptCandidate(playerId: player.id,
                                           target: target.id,
                                           candidateIndex: last.index)
            }
        }
        let missing = allTargets.filter { !store.hasPanel(playerId: player.id, target: $0.id) }
        if missing.isEmpty {
            isPresented = false
            onFinalize()
        } else {
            stillMissing = missing
        }
    }

    private var allTargets: [PanelTarget] {
        var out: [PanelTarget] = template.panels.map { .panel(n: $0.n, spec: $0) }
        out.append(.cover(spec: template.cover))
        return out
    }

    private func label(for target: PanelTarget) -> String {
        switch target {
        case .panel(let n, _): return "Panel \(n)"
        case .cover: return "Cover"
        }
    }
}

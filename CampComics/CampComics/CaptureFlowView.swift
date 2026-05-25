import SwiftUI
import CampComicsCore

struct CaptureFlowView: View {
    let player: PlayerProfile
    let template: ClassTemplate

    @State private var captureState: CaptureState
    @State private var reviewing: PanelRequirement?
    @State private var submitted: Bool = false

    init(player: PlayerProfile, template: ClassTemplate) {
        self.player = player
        self.template = template
        let plan = CapturePlanner.plan(for: template)
        _captureState = State(initialValue: CaptureState(plan: plan))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                summary
                VStack(spacing: 12) {
                    ForEach(captureState.plan) { requirement in
                        ChecklistRow(
                            requirement: requirement,
                            isCaptured: captureState.isCaptured(requirement),
                            onTap: { handleTap(requirement) }
                        )
                    }
                }
                submitButton
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("\(template.name) capture")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $reviewing) { requirement in
            ReviewSheet(
                requirement: requirement,
                onRetake: {
                    captureState.retake(requirement)
                    reviewing = nil
                },
                onConfirm: { reviewing = nil }
            )
        }
        .alert("Submitted (mock)", isPresented: $submitted) {
            Button("OK") { submitted = false }
        } message: {
            Text("In a later slice this triggers Gemini test-generation. Right now it just acknowledges the captured set.")
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(playerHeadline)
                .font(.title2.weight(.semibold))
            Text("\(captureState.capturedCount) of \(captureState.plan.count) photos · tap any row.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ProgressSegments(total: captureState.plan.count, captured: captureState.capturedCount)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var submitButton: some View {
        Button {
            submitted = true
        } label: {
            Text(captureState.isReadyToSubmit
                 ? "All set — submit"
                 : "\(captureState.remainingCount) more to go")
                .frame(maxWidth: .infinity)
                .fontWeight(.semibold)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!captureState.isReadyToSubmit)
        .padding(.top, 8)
    }

    private var playerHeadline: String {
        if player.characterName.isEmpty {
            return "\(player.playerName) — \(template.name)"
        }
        return "\(player.characterName) (\(player.playerName)) — \(template.name)"
    }

    private func handleTap(_ requirement: PanelRequirement) {
        if captureState.isCaptured(requirement) {
            reviewing = requirement
        } else {
            // No camera yet — record a mock CapturedPhoto so the state machine
            // and UI bindings can be exercised end-to-end.
            captureState.record(CapturedPhoto(), for: requirement)
        }
    }
}

private struct ChecklistRow: View {
    let requirement: PanelRequirement
    let isCaptured: Bool
    let onTap: () -> Void

    var body: some View {
        let copy = PromptCopyBook.copy(for: requirement)
        Button(action: onTap) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isCaptured ? Color.accentColor.opacity(0.18) : Color(.tertiarySystemFill))
                    if isCaptured {
                        Image(systemName: "checkmark")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.tint)
                    } else {
                        Text(copy.emoji).font(.title)
                    }
                }
                .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 2) {
                    Text(copy.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("\(requirement.emotion.rawValue) · \(requirement.position.rawValue)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isCaptured ? "checkmark.circle.fill" : "chevron.right")
                    .foregroundStyle(isCaptured ? Color.accentColor : Color.secondary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isCaptured ? Color.accentColor.opacity(0.08) : Color(.secondarySystemGroupedBackground))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ProgressSegments: View {
    let total: Int
    let captured: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<total, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(i < captured ? Color.accentColor : Color(.tertiarySystemFill))
                    .frame(height: 6)
            }
        }
    }
}

private struct ReviewSheet: View {
    let requirement: PanelRequirement
    let onRetake: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        let copy = PromptCopyBook.copy(for: requirement)
        VStack(spacing: 20) {
            Text(copy.emoji).font(.system(size: 96))
            VStack(spacing: 6) {
                Text(copy.title).font(.title2.weight(.semibold))
                Text(copy.subtitle).font(.subheadline).foregroundStyle(.secondary)
                Text("Mock capture — actual photo lives in a later slice.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
            }
            .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button("Retake", role: .destructive, action: onRetake)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                Button("Looks good", action: onConfirm)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
        .padding()
        .presentationDetents([.medium])
    }
}

#Preview {
    NavigationStack {
        CaptureFlowView(
            player: PlayerProfile(playerName: "Alex", characterName: "", classKey: "druid"),
            template: BundledTemplates.druid
        )
    }
}

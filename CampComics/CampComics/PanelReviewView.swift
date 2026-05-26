import SwiftUI
import UIKit
import CampComicsCore

/// The slice-9 review surface. Drives one panel at a time and auto-advances
/// the cursor to the next unfinished slot when the operator Accepts or Skips.
/// Renders the candidate gallery as a filmstrip, exposes Generate / Accept /
/// Skip / Re-roll / Cancel, and shows the out-of-order chip when an earlier
/// panel hasn't been finalized yet.
struct PanelReviewView: View {
    let player: PlayerRecord
    let template: ClassTemplate
    let store: PlayerStore
    let generator: any PanelGenerator

    @State private var currentN: Int
    @State private var review: PanelReviewState
    @State private var candidates: [PanelCandidate] = []
    @State private var selectedCandidate: PanelCandidate?
    @State private var pendingTask: Task<Void, Never>?
    @State private var lastPrompt: String = ""
    @State private var lastReferences: [ReferenceSlot] = []
    @State private var lastError: String?
    @State private var showPromptDetail: Bool = false

    init(player: PlayerRecord,
         template: ClassTemplate,
         store: PlayerStore,
         generator: any PanelGenerator = FirebaseAIPanelGenerator(),
         startAt: Int) {
        self.player = player
        self.template = template
        self.store = store
        self.generator = generator
        _currentN = State(initialValue: startAt)
        _review = State(initialValue: PanelReviewState.hydrate(playerId: player.id, n: startAt, store: store))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if allFinalized { allDoneBanner }
                if let chip = outOfOrderChip { chip }
                mainImage
                filmstrip
                if !lastPrompt.isEmpty || !lastReferences.isEmpty {
                    debugChip
                }
                actionRow
                navRow
                if let lastError {
                    Text(lastError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Panel \(currentN) of 12")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reloadCurrentPanel)
        .onDisappear { pendingTask?.cancel() }
    }

    private var allFinalized: Bool {
        (1...12).allSatisfy {
            store.hasPanel(playerId: player.id, n: $0)
                || store.isSkipped(playerId: player.id, n: $0)
        }
    }

    private var allDoneBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("All 12 panels reviewed").font(.headline)
            Text("Cover comes next (slice 11). Tap ‹ back to return to the player.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.accentColor.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !currentSpec.beat.isEmpty {
                Text(currentSpec.beat)
                    .font(.footnote.italic())
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text(stateLabel).font(.headline)
                Spacer()
                Text(player.classKey.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var outOfOrderChip: Text? {
        let plan = PhotoReferenceResolver.plan(forPanel: currentN,
                                               spec: currentSpec,
                                               playerId: player.id,
                                               store: store)
        guard plan.outOfOrder else { return nil }
        return Text("Continuity reference: none — earlier panels not yet approved")
            .font(.caption)
            .foregroundStyle(.orange)
    }

    @ViewBuilder
    private var mainImage: some View {
        if case .accepted = review.phase,
           let data = store.loadPanel(playerId: player.id, n: currentN),
           let image = UIImage(data: data) {
            ZoomableImage(image: image)
                .aspectRatio(image.size, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else if case .skipped = review.phase {
            placeholder("Skipped — tap Re-generate below to undo.")
        } else if let candidate = selectedCandidate,
                  let data = try? Data(contentsOf: candidate.url),
                  let image = UIImage(data: data) {
            ZoomableImage(image: image)
                .aspectRatio(image.size, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else if case .generating = review.phase {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("Generating candidate…").font(.footnote).foregroundStyle(.secondary)
                    }
                }
        } else if case .throttled = review.phase {
            placeholder("Throttled — Vertex per-minute quota exceeded. Wait a moment and tap Retry.")
        } else {
            placeholder("No candidate yet — tap Generate.")
        }
    }

    private func placeholder(_ text: String) -> some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground))
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding()
                    .multilineTextAlignment(.center)
            }
    }

    @ViewBuilder
    private var filmstrip: some View {
        if !candidates.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(candidates, id: \.index) { candidate in
                        Button {
                            selectedCandidate = candidate
                        } label: {
                            thumbnail(for: candidate)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func thumbnail(for candidate: PanelCandidate) -> some View {
        let isSelected = candidate.index == selectedCandidate?.index
        return Group {
            if let data = try? Data(contentsOf: candidate.url),
               let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color(.tertiarySystemGroupedBackground)
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
        }
    }

    @ViewBuilder
    private var actionRow: some View {
        switch review.phase {
        case .unstarted, .missingPhoto:
            HStack {
                Button("Generate") { startGenerate() }
                    .buttonStyle(.borderedProminent)
                Button("Skip") { commitSkip() }
                    .buttonStyle(.bordered)
                    .tint(.secondary)
            }
        case .generating:
            HStack {
                Button("Cancel") { cancelGenerate() }
                    .buttonStyle(.bordered)
                    .tint(.secondary)
            }
        case .reviewing:
            HStack {
                Button("Accept") { commitAccept() }
                    .buttonStyle(.borderedProminent)
                Button("Re-roll") { startGenerate() }
                    .buttonStyle(.bordered)
                Button("Skip") { commitSkip() }
                    .buttonStyle(.bordered)
                    .tint(.secondary)
            }
        case .accepted:
            Button("Re-roll") { rerollAccepted() }
                .buttonStyle(.bordered)
        case .skipped:
            Button("Re-generate") { startGenerate() }
                .buttonStyle(.bordered)
        case .throttled:
            Button("Retry") { startGenerate() }
                .buttonStyle(.borderedProminent)
        case .failed(let msg):
            VStack(alignment: .leading, spacing: 6) {
                Text(msg).font(.footnote).foregroundStyle(.red)
                Button("Retry") { startGenerate() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    /// Always-visible navigation row so the operator can step through 1..12
    /// regardless of slot phase. Hidden while a generation is in flight.
    @ViewBuilder
    private var navRow: some View {
        if case .generating = review.phase {
            EmptyView()
        } else {
            HStack {
                Button("Previous") { goTo(currentN - 1) }
                    .disabled(currentN <= 1)
                Spacer()
                Button("Next") { goTo(currentN + 1) }
                    .disabled(currentN >= 12)
            }
            .buttonStyle(.bordered)
        }
    }

    /// Expandable diagnostic block — confirms exactly what prompt + reference
    /// slots were sent on the most recent generation for this panel. Lets the
    /// operator sanity-check whether reference_panel overrides are actually
    /// flowing through when model output drifts.
    private var debugChip: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                showPromptDetail.toggle()
            } label: {
                HStack {
                    Image(systemName: showPromptDetail ? "chevron.down" : "chevron.right")
                    Text("Prompt + references")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Text(referencesSummary).font(.caption2).foregroundStyle(.secondary)
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            if showPromptDetail {
                Text(specDiagnostic)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Divider()
                Text(lastPrompt)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var referencesSummary: String {
        guard !lastReferences.isEmpty else { return "" }
        return lastReferences.map { slot -> String in
            switch slot {
            case .photo: return "photo"
            case .hero: return "hero"
            case .panel(let n): return "panel \(String(format: "%02d", n))"
            }
        }.joined(separator: " + ")
    }

    /// Slice-9 diagnostic: surface the raw spec fields so we can tell whether a
    /// surprising chip summary is a loader bug (`spec.referencePanel == nil`
    /// where YAML had an override) or a resolver bug (`spec.referencePanel == X`
    /// but `lastReferences` ignored it).
    private var specDiagnostic: String {
        let ref = currentSpec.referencePanel.map(String.init) ?? "nil"
        let cost = currentSpec.costumeOverride.map { "yes (\($0.prefix(40))…)" } ?? "no"
        let style = currentSpec.styleOverride.map { "yes (\($0.prefix(40))…)" } ?? "no"
        return "spec.referencePanel = \(ref) · costume_override = \(cost) · style_override = \(style)"
    }

    // MARK: - Actions

    private func startGenerate() {
        lastError = nil
        let spec = currentSpec
        guard let photoData = store.loadPhoto(playerId: player.id,
                                              requirement: spec.requirement) else {
            review.markMissingPhoto()
            return
        }
        // Re-generate from a skipped panel: drop the marker before firing so
        // hydrate doesn't snap back to `.skipped` after navigation (issue #12).
        if case .skipped = review.phase {
            try? store.unmarkSkipped(playerId: player.id, n: currentN)
        }
        let plan = PhotoReferenceResolver.plan(forPanel: currentN,
                                               spec: spec,
                                               playerId: player.id,
                                               store: store)
        guard let references = materialize(plan: plan,
                                           photoData: photoData,
                                           spec: spec) else {
            lastError = "Couldn't load all reference images for this panel."
            return
        }
        let prompt = PromptBuilder.buildPanelPrompt(
            spec: spec,
            template: template,
            tokens: ["camper_name": player.playerName]
        )
        lastPrompt = prompt
        lastReferences = plan.slots
        review.startGeneration()

        pendingTask = Task {
            do {
                let pngData = try await generator.generatePanel(prompt: prompt,
                                                                references: references)
                if Task.isCancelled { return }
                let saved = try store.savePendingCandidate(playerId: player.id,
                                                           n: currentN,
                                                           pngData: pngData)
                appendAttempt(prompt: prompt, candidate: saved)
                await MainActor.run {
                    candidates = store.listCandidates(playerId: player.id, n: currentN)
                    selectedCandidate = saved
                    review.candidateReceived()
                }
            } catch is CancellationError {
                // Cancel path: cancelGenerate() already moved state.
            } catch PanelGeneratorError.throttled {
                await MainActor.run { review.markThrottled() }
            } catch let err as PanelGeneratorError {
                await MainActor.run {
                    review.markFailed(message: message(for: err))
                }
            } catch {
                await MainActor.run {
                    review.markFailed(message: String(describing: error))
                }
            }
            await MainActor.run { pendingTask = nil }
        }
    }

    private func cancelGenerate() {
        pendingTask?.cancel()
        pendingTask = nil
        review.cancelGeneration()
    }

    private func commitAccept() {
        guard let candidate = selectedCandidate else { return }
        do {
            try store.acceptCandidate(playerId: player.id,
                                      n: currentN,
                                      candidateIndex: candidate.index)
            advance()
        } catch {
            lastError = String(describing: error)
        }
    }

    private func commitSkip() {
        do {
            try store.markSkipped(playerId: player.id, n: currentN)
            advance()
        } catch {
            lastError = String(describing: error)
        }
    }

    /// After Accept or Skip, jump to the next unfinished panel (auto-advance
    /// per design memo #5). If everything is finalized, just refresh in place
    /// so the filmstrip clears and the accepted image displays correctly.
    private func advance() {
        if let next = nextUnfinished(after: currentN) {
            currentN = next
        }
        reloadCurrentPanel()
    }

    private func goTo(_ n: Int) {
        guard (1...12).contains(n) else { return }
        currentN = n
        reloadCurrentPanel()
    }

    /// Re-roll-after-accept (design memo #3): demote the prior accepted image
    /// back into the candidate gallery so it's still visible while a new
    /// candidate is generated. Operator can Accept either one when reviewing.
    private func rerollAccepted() {
        do {
            try store.demoteAcceptedToCandidate(playerId: player.id, n: currentN)
            review = PanelReviewState(phase: .reviewing)
            candidates = store.listCandidates(playerId: player.id, n: currentN)
            selectedCandidate = candidates.first
            startGenerate()
        } catch {
            lastError = String(describing: error)
        }
    }

    private func reloadCurrentPanel() {
        review = PanelReviewState.hydrate(playerId: player.id, n: currentN, store: store)
        candidates = store.listCandidates(playerId: player.id, n: currentN)
        selectedCandidate = candidates.last
        lastError = nil
        lastPrompt = store.attemptsState(playerId: player.id)
            .last(where: { $0.n == currentN })?
            .prompt ?? ""
        let plan = PhotoReferenceResolver.plan(forPanel: currentN,
                                               spec: currentSpec,
                                               playerId: player.id,
                                               store: store)
        lastReferences = plan.slots
        showPromptDetail = false
    }

    // MARK: - Helpers

    private var currentSpec: PanelSpec {
        template.panels.first(where: { $0.n == currentN }) ?? template.panels[0]
    }

    private var stateLabel: String {
        switch review.phase {
        case .unstarted: return "Unstarted"
        case .generating: return "Generating…"
        case .reviewing:
            let idx = (selectedCandidate?.index ?? -1) + 1
            return "Candidate \(idx) of \(candidates.count) · Reviewing"
        case .accepted: return "Accepted"
        case .skipped: return "Skipped"
        case .throttled: return "Throttled"
        case .failed: return "Failed"
        case .missingPhoto: return "Missing reference photo"
        }
    }

    private func nextUnfinished(after n: Int) -> Int? {
        // "Next" = lowest unfinished panel ≠ n. Wraps back to earlier slots
        // if the operator jumped ahead, so out-of-order acceptance still
        // converges on all 12.
        for m in 1...12 where m != n {
            if !store.hasPanel(playerId: player.id, n: m)
                && !store.isSkipped(playerId: player.id, n: m) {
                return m
            }
        }
        return nil
    }

    private func materialize(plan: ReferencePlan,
                             photoData: Data,
                             spec: PanelSpec) -> [ImageReference]? {
        var refs: [ImageReference] = []
        for slot in plan.slots {
            switch slot {
            case .photo:
                refs.append(ImageReference(data: photoData, mimeType: "image/jpeg"))
            case .hero:
                let hero = BundledTemplates.heroCardData(forClassKey: template.classKey)
                refs.append(ImageReference(data: hero, mimeType: "image/png"))
            case .panel(let m):
                guard let data = store.loadPanel(playerId: player.id, n: m) else { return nil }
                refs.append(ImageReference(data: data, mimeType: "image/png"))
            }
        }
        return refs
    }

    private func appendAttempt(prompt: String, candidate: PanelCandidate) {
        var existing = store.attemptsState(playerId: player.id)
        existing.append(PanelAttempt(n: currentN,
                                     attempt: candidate.index,
                                     prompt: prompt,
                                     candidateFile: candidate.url.lastPathComponent,
                                     generatedAt: Date()))
        try? store.setAttemptsState(playerId: player.id, attempts: existing)
    }

    private func message(for error: PanelGeneratorError) -> String {
        switch error {
        case .noImageReturned: return "Gemini returned no image."
        case .throttled: return "Vertex per-minute quota exceeded."
        case .underlying(let msg): return msg
        }
    }

}

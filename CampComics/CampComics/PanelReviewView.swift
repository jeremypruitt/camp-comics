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
    @State private var lastError: String?
    @State private var allDone: Bool = false

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
        _review = State(initialValue: Self.hydrate(playerId: player.id, n: startAt, store: store))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if allDone {
                    doneCard
                } else {
                    header
                    if let chip = outOfOrderChip { chip }
                    selectedCandidateView
                    filmstrip
                    actionRow
                    if let lastError {
                        Text(lastError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(allDone ? "Done" : "Panel \(currentN) of 12")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reloadCurrentPanel)
        .onDisappear { pendingTask?.cancel() }
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
    private var selectedCandidateView: some View {
        if let candidate = selectedCandidate,
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
        } else {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    Text("No candidate yet — tap Generate.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
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
        case .accepted, .skipped:
            // Slot 9: auto-advance, so we shouldn't normally land here. If we
            // do (e.g. nothing left to advance to), show a Next button.
            Button("Next") { advance() }
                .buttonStyle(.borderedProminent)
        case .throttled:
            Text("Throttled — retry pending (slice 13).").font(.footnote).foregroundStyle(.secondary)
        case .failed(let msg):
            VStack(alignment: .leading, spacing: 6) {
                Text(msg).font(.footnote).foregroundStyle(.red)
                Button("Retry") { startGenerate() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private var doneCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("All 12 panels reviewed").font(.headline)
            Text("Cover + Re-prompt UX land in slice 11.").font(.footnote).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
            review.accept()
            advance()
        } catch {
            lastError = String(describing: error)
        }
    }

    private func commitSkip() {
        do {
            try store.markSkipped(playerId: player.id, n: currentN)
            review.skip()
            advance()
        } catch {
            lastError = String(describing: error)
        }
    }

    private func advance() {
        if let next = nextUnfinished(after: currentN) {
            currentN = next
            reloadCurrentPanel()
        } else {
            allDone = true
        }
    }

    private func reloadCurrentPanel() {
        review = Self.hydrate(playerId: player.id, n: currentN, store: store)
        candidates = store.listCandidates(playerId: player.id, n: currentN)
        selectedCandidate = candidates.last
        lastError = nil
        lastPrompt = ""
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
        case .underlying(let msg): return msg
        }
    }

    private static func hydrate(playerId: String, n: Int, store: PlayerStore) -> PanelReviewState {
        if store.hasPanel(playerId: playerId, n: n) {
            return PanelReviewState(phase: .accepted)
        }
        if store.isSkipped(playerId: playerId, n: n) {
            return PanelReviewState(phase: .skipped)
        }
        if !store.listCandidates(playerId: playerId, n: n).isEmpty {
            return PanelReviewState(phase: .reviewing)
        }
        return PanelReviewState(phase: .unstarted)
    }
}

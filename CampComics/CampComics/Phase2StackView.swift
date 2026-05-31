import SwiftUI
import UIKit
import CampComicsCore

/// ADR-0009 Phase 2 surface (slice D / #64). Hosts a `GenerationQueue` worker
/// pool that pulls panels 2..N + cover in story order and generates them under
/// adaptive K. Renders the strictly story-ordered head — never panel 7 before
/// panel 3 even if 7 lands on disk first — with a spinner placeholder while the
/// head's underlying generation is in flight. Mid-stack in-flight panels are
/// invisible (no thumbnails behind the head, by ADR-0009 design).
///
/// Single-candidate-per-panel in this slice. Swipe-right Accept advances the
/// stack; swipe-left, swipe-up/down, long-press are Slice E/F/G — gestures
/// stubbed as no-ops so the surface area exists for those slices to extend.
struct Phase2StackView: View {
    @Environment(\.themeKind) private var theme
    let player: PlayerRecord
    let template: ClassTemplate
    let store: PlayerStore
    let generator: any PanelGenerator

    @State private var headIndex: Int = 0
    @State private var candidate: PanelCandidate?
    @State private var swipeOffset: CGSize = .zero
    @State private var queueTask: Task<Void, Never>?
    @State private var headTick: Int = 0   // bumps to force head re-resolve on completion
    @State private var budget: GenerationBudget
    @State private var lastError: String?

    init(player: PlayerRecord,
         template: ClassTemplate,
         store: PlayerStore,
         generator: any PanelGenerator) {
        self.player = player
        self.template = template
        self.store = store
        self.generator = generator
        _budget = State(initialValue: store.generationBudget(playerId: player.id,
                                                             panelCount: template.panels.count))
    }

    var body: some View {
        let p = theme.palette
        VStack(spacing: 18) {
            header
            cardBody
            if let lastError {
                Text(lastError)
                    .font(theme.captionFont(12))
                    .foregroundStyle(p.danger)
                    .padding(.horizontal)
            }
            Spacer()
        }
        .padding(.vertical)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { budgetChip }
        }
        .onAppear { startQueueIfNeeded() }
        .onDisappear { queueTask?.cancel() }
    }

    // MARK: - Subviews

    private var header: some View {
        let p = theme.palette
        return Text(headerText)
            .font(theme.headingFont(18))
            .foregroundStyle(p.inkPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
    }

    private var budgetChip: some View {
        let p = theme.palette
        return Text("\(budget.remaining) / \(budget.limit)")
            .font(theme.captionFont(12))
            .foregroundStyle(budget.isExhausted ? p.danger : p.inkSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(p.surfaceRaised, in: Capsule())
    }

    @ViewBuilder
    private var cardBody: some View {
        if isAllDone {
            doneCard
        } else if let candidate, let image = loadImage(candidate.url) {
            candidateCard(image: image)
        } else {
            placeholderCard
        }
    }

    private var placeholderCard: some View {
        let p = theme.palette
        return RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(p.surfaceRaised)
            .overlay {
                VStack(spacing: 14) {
                    ProgressView()
                    Text("Generating…")
                        .font(theme.captionFont(13))
                        .foregroundStyle(p.inkSecondary)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .padding(.horizontal)
            .id(headTick)
    }

    private func candidateCard(image: UIImage) -> some View {
        let p = theme.palette
        return Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal)
            .offset(swipeOffset)
            .rotationEffect(.degrees(Double(swipeOffset.width / 20)))
            .overlay(alignment: .topTrailing) {
                if swipeOffset.width > 40 {
                    Text("ACCEPT")
                        .font(theme.headingFont(20))
                        .foregroundStyle(p.accent)
                        .padding(8)
                        .background(p.paper, in: RoundedRectangle(cornerRadius: 8))
                        .padding(24)
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { swipeOffset = $0.translation }
                    .onEnded { value in
                        if value.translation.width > 120 {
                            commitAcceptHead()
                        } else {
                            withAnimation(.spring) { swipeOffset = .zero }
                        }
                    }
            )
    }

    private var doneCard: some View {
        let p = theme.palette
        return ThemedCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Stack complete.")
                    .font(theme.headingFont(18))
                    .foregroundStyle(p.inkPrimary)
                Text("Every panel and the cover are accepted. Tap back to finalize the PDF.")
                    .font(theme.bodyFont(14))
                    .foregroundStyle(p.inkSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal)
    }

    // MARK: - Header text

    private var headerText: String {
        guard !isAllDone else { return "Phase 2 — complete" }
        switch headTarget {
        case .panel(let n, _): return "Panel \(n) of \(targets.count + 1)"
        case .cover: return "Cover"
        }
    }

    // MARK: - Queue lifecycle

    private func startQueueIfNeeded() {
        // Refresh candidate / budget on (re-)appear so navigating back into the
        // surface picks up anything the queue advanced in the background.
        refreshHead()
        guard queueTask == nil else { return }
        let targetsSnapshot = targets
        let playerId = player.id
        let store = store
        let generator = generator
        let template = template
        let panelCount = template.panels.count
        let queue = GenerationQueue(
            targets: targetsSnapshot,
            isExhausted: {
                store.generationBudget(playerId: playerId, panelCount: panelCount).isExhausted
            },
            work: { target in
                try await Self.runOne(target: target,
                                      playerId: playerId,
                                      template: template,
                                      store: store,
                                      generator: generator)
            }
        )
        queueTask = Task {
            let stream = await queue.events
            async let drain: Void = {
                for await event in stream {
                    await MainActor.run {
                        switch event {
                        case .completed(let id):
                            if id == headTarget.id { refreshHead() }
                            else { headTick &+= 1 }
                            refreshBudget()
                        case .throttled, .failed:
                            refreshBudget()
                        }
                    }
                }
            }()
            await queue.run()
            await drain
        }
    }

    // MARK: - Single-target worker (called from inside the queue's actor)

    static func runOne(target: PanelTarget,
                       playerId: String,
                       template: ClassTemplate,
                       store: PlayerStore,
                       generator: any PanelGenerator) async throws {
        if store.hasPanel(playerId: playerId, target: target.id) { return }
        guard let photoData = store.loadPhoto(playerId: playerId,
                                              requirement: target.requirement) else {
            throw PanelGeneratorError.underlying("Missing reference photo for \(target.diskName).")
        }
        let plan = PhotoReferenceResolver.references(for: target,
                                                     playerId: playerId,
                                                     store: store)
        guard let references = materialize(plan: plan,
                                           photoData: photoData,
                                           classKey: template.classKey,
                                           playerId: playerId,
                                           store: store) else {
            throw PanelGeneratorError.underlying("Couldn't materialise references for \(target.diskName).")
        }
        let prompt = PromptBuilder.buildPrompt(for: target,
                                               template: template,
                                               tokens: ["camper_name": playerNameLookup(playerId: playerId, store: store)])
        let pngData = try await generator.generatePanel(prompt: prompt, references: references)
        // Single-candidate-per-panel for slice D — save then auto-accept onto
        // disk so the head card and `hasPanel` agree. Re-roll / gallery cycling
        // land in Slices E/F.
        let saved = try store.savePendingCandidate(playerId: playerId,
                                                   target: target.id,
                                                   pngData: pngData)
        appendAttempt(playerId: playerId, store: store, target: target.id,
                      prompt: prompt, candidate: saved)
        // Spend the budget atomically with the completion event so the chip
        // updates regardless of whether the head is this panel.
        let current = store.generationBudget(playerId: playerId,
                                             panelCount: template.panels.count)
        try? store.setGenerationBudget(playerId: playerId, current.decremented())
    }

    private static func materialize(plan: ReferencePlan, photoData: Data,
                                    classKey: String, playerId: String,
                                    store: PlayerStore) -> [ImageReference]? {
        var refs: [ImageReference] = []
        for slot in plan.slots {
            switch slot {
            case .photo:
                refs.append(ImageReference(data: photoData, mimeType: "image/jpeg"))
            case .hero:
                refs.append(ImageReference(data: BundledTemplates.heroCardData(forClassKey: classKey),
                                           mimeType: "image/png"))
            case .panel(let m):
                guard let data = store.loadPanel(playerId: playerId, target: .panel(m)) else { return nil }
                refs.append(ImageReference(data: data, mimeType: "image/png"))
            }
        }
        return refs
    }

    private static func playerNameLookup(playerId: String, store: PlayerStore) -> String {
        (try? store.load(id: playerId).playerName) ?? ""
    }

    private static func appendAttempt(playerId: String, store: PlayerStore,
                                      target: PanelTargetID, prompt: String,
                                      candidate: PanelCandidate) {
        var existing = store.attemptsState(playerId: playerId)
        existing.append(PanelAttempt(target: target,
                                     attempt: candidate.index,
                                     prompt: prompt,
                                     candidateFile: candidate.url.lastPathComponent,
                                     generatedAt: Date()))
        try? store.setAttemptsState(playerId: playerId, attempts: existing)
    }

    // MARK: - Head + budget refresh

    private func refreshHead() {
        if isAllDone {
            candidate = nil
            return
        }
        let head = headTarget
        candidate = store.listCandidates(playerId: player.id, target: head.id).last
        headTick &+= 1
    }

    private func refreshBudget() {
        budget = store.generationBudget(playerId: player.id,
                                        panelCount: template.panels.count)
    }

    private func commitAcceptHead() {
        let head = headTarget
        // If the head already has an accepted panel on disk (race: queue and
        // operator both completed) we just advance without re-accepting.
        if !store.hasPanel(playerId: player.id, target: head.id) {
            guard let candidate else { return }
            do {
                try store.acceptCandidate(playerId: player.id,
                                          target: head.id,
                                          candidateIndex: candidate.index)
            } catch {
                lastError = String(describing: error)
                withAnimation(.spring) { swipeOffset = .zero }
                return
            }
        }
        withAnimation(.easeOut(duration: 0.2)) {
            swipeOffset = CGSize(width: 600, height: 0)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            swipeOffset = .zero
            headIndex += 1
            refreshHead()
            refreshBudget()
        }
    }

    // MARK: - Targets

    /// Story-ordered targets for Phase 2: panels 2..N then the cover. Panel 1
    /// is excluded because Phase 1 already finalized it.
    private var targets: [PanelTarget] {
        var out: [PanelTarget] = template.panels
            .filter { $0.n != 1 }
            .sorted { $0.n < $1.n }
            .map { .panel(n: $0.n, spec: $0) }
        out.append(.cover(spec: template.cover))
        return out
    }

    private var headTarget: PanelTarget {
        targets[min(headIndex, targets.count - 1)]
    }

    private var isAllDone: Bool {
        headIndex >= targets.count
    }

    private func loadImage(_ url: URL) -> UIImage? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }
}

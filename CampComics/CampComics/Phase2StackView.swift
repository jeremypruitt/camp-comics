import SwiftUI
import UIKit
import CampComicsCore

/// ADR-0009 Phase 2 surface. Hosts a `GenerationQueue` worker pool that pulls
/// panels 2..N + cover in story order and generates them under adaptive K, and
/// layers slice-E's per-panel review gallery on top: every head panel can have
/// 1..n candidates that the operator cycles through with swipe-up/down (zero
/// API calls), re-rolls with swipe-left (one call → append to gallery, jump to
/// newest), and accepts with swipe-right (promotes the *currently visible*
/// candidate and wipes the rest of the gallery from disk).
///
/// The head is rendered strictly in story order — never panel 7 before panel 3
/// even if 7 lands on disk first. Mid-stack in-flight panels are invisible (no
/// thumbnails behind the head, by ADR-0009 design).
///
/// Re-roll runs through a standalone ad-hoc `Task` calling the same `runOne`
/// worker the queue uses. It does NOT enqueue into the FIFO actor (which is
/// fixed-shape and story-ordered); it bypasses the actor only for the purpose
/// of "spawn one extra generation for the head", and the worker still spends
/// budget the same way the queue does. The exhausted-budget gate is enforced
/// at the call site so swipe-left bounces back instead of starting work.
struct Phase2StackView: View {
    @Environment(\.themeKind) private var theme
    let player: PlayerRecord
    let template: ClassTemplate
    let store: PlayerStore
    let generator: any PanelGenerator

    @State private var headIndex: Int = 0
    @State private var gallery: [PanelCandidate] = []
    @State private var cursor: GalleryCursor = .forNewHead(count: 0)
    @State private var swipeOffset: CGSize = .zero
    @State private var queueTask: Task<Void, Never>?
    @State private var rerollTask: Task<Void, Never>?
    @State private var headTick: Int = 0
    @State private var budget: GenerationBudget
    @State private var lastError: String?
    @State private var showExhaustionModal: Bool = false
    @State private var showRepromptSheet: Bool = false

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
        .onDisappear {
            queueTask?.cancel()
            rerollTask?.cancel()
        }
        .sheet(isPresented: $showExhaustionModal) {
            exhaustionModal
        }
        .sheet(isPresented: $showRepromptSheet) {
            RepromptAddendumSheet(
                assembledPrompt: assembledPromptForHead,
                onApply: { addendum in
                    showRepromptSheet = false
                    commitRepromptHead(addendum: addendum)
                },
                onCancel: { showRepromptSheet = false }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
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
        } else if let visible, let image = loadImage(visible.url) {
            candidateCard(candidate: visible, image: image)
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
                    Text(isRerolling ? "Re-rolling…" : "Generating…")
                        .font(theme.captionFont(13))
                        .foregroundStyle(p.inkSecondary)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .padding(.horizontal)
            .id(headTick)
    }

    private func candidateCard(candidate: PanelCandidate, image: UIImage) -> some View {
        let p = theme.palette
        return VStack(spacing: 10) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .offset(swipeOffset)
                .rotationEffect(.degrees(Double(swipeOffset.width / 20)))
                .overlay(alignment: .topTrailing) { acceptBadge }
                .overlay(alignment: .topLeading) { rerollBadge }
                .gesture(stackGesture)
                // Slice F: long-press → Re-prompt sheet. `.simultaneousGesture`
                // so the LongPress arms in parallel with the drag — a drag
                // wins because it changes translation first; a still hold
                // wins by elapsing the 0.5s minimumDuration. Exhausted
                // budget no-ops (see commitRepromptHead).
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.5)
                        .onEnded { _ in openRepromptSheet() }
                )
            galleryFooter(candidate: candidate)
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var acceptBadge: some View {
        let p = theme.palette
        if swipeOffset.width > 40 {
            Text("ACCEPT")
                .font(theme.headingFont(20))
                .foregroundStyle(p.accent)
                .padding(8)
                .background(p.paper, in: RoundedRectangle(cornerRadius: 8))
                .padding(24)
        }
    }

    @ViewBuilder
    private var rerollBadge: some View {
        let p = theme.palette
        if swipeOffset.width < -40 {
            Text(budget.isExhausted ? "OUT OF BUDGET" : "RE-ROLL")
                .font(theme.headingFont(20))
                .foregroundStyle(budget.isExhausted ? p.danger : p.accent)
                .padding(8)
                .background(p.paper, in: RoundedRectangle(cornerRadius: 8))
                .padding(24)
        }
    }

    @ViewBuilder
    private func galleryFooter(candidate: PanelCandidate) -> some View {
        let p = theme.palette
        HStack(spacing: 10) {
            DotIndicatorView(cursor: cursor)
            Spacer()
            Text(cursor.positionLabel)
                .font(theme.captionFont(12))
                .foregroundStyle(p.inkSecondary)
            if let stamped = candidate.generatedAt {
                Text(Self.timestampFormatter.string(from: stamped))
                    .font(theme.captionFont(12))
                    .foregroundStyle(p.inkSecondary)
            }
        }
        .padding(.top, 4)
    }

    private var stackGesture: some Gesture {
        DragGesture()
            .onChanged { swipeOffset = $0.translation }
            .onEnded { value in
                let t = value.translation
                let absX = abs(t.width)
                let absY = abs(t.height)
                // Horizontal beats vertical when |dx| > |dy|; otherwise vertical.
                if absX > absY {
                    if t.width > 120 {
                        commitAcceptVisible()
                    } else if t.width < -120 {
                        commitRerollHead()
                    } else {
                        withAnimation(.spring) { swipeOffset = .zero }
                    }
                } else {
                    if t.height < -80 {
                        cycleGallery(forward: true)
                    } else if t.height > 80 {
                        cycleGallery(forward: false)
                    }
                    withAnimation(.spring) { swipeOffset = .zero }
                }
            }
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

    private var exhaustionModal: some View {
        // Mirrors slice 23's existing modal copy/affordances — kept inline here
        // because the surface owner (Phase2StackView) is its only call site for
        // now. If a second caller surfaces, lift it into a reusable view.
        let p = theme.palette
        return VStack(alignment: .leading, spacing: 16) {
            Text("Out of generations for this comic")
                .font(theme.headingFont(20))
                .foregroundStyle(p.inkPrimary)
            Text("Accept the candidates you already have to finalize, or paste a personal API key in Settings to keep re-rolling.")
                .font(theme.bodyFont(14))
                .foregroundStyle(p.inkSecondary)
            ThemedPrimaryButton("Accept current and finalize",
                                systemImage: "checkmark.circle.fill") {
                showExhaustionModal = false
            }
            ThemedPrimaryButton("Paste BYO key in Settings",
                                systemImage: "key.fill") {
                showExhaustionModal = false
            }
            Spacer()
        }
        .padding()
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
        // Refresh head + budget on (re-)appear so navigating back in picks up
        // anything the queue advanced in the background.
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

    // MARK: - Single-target worker (shared by queue + ad-hoc re-roll)

    static func runOne(target: PanelTarget,
                       playerId: String,
                       template: ClassTemplate,
                       store: PlayerStore,
                       generator: any PanelGenerator) async throws {
        if store.hasPanel(playerId: playerId, target: target.id) { return }
        try await runOneAppendingCandidate(target: target,
                                           playerId: playerId,
                                           template: template,
                                           store: store,
                                           generator: generator)
    }

    /// Slice E: explicit "always generate + append" path used by Re-roll. The
    /// `hasPanel` guard is skipped because the head panel is by definition not
    /// yet accepted (Accept advances the stack). Decrements budget on success
    /// the same way the queue's worker does.
    ///
    /// Slice F (#66): `addendum` threads through to `PromptBuilder.buildPrompt`
    /// for Re-prompt (long-press). Re-roll still passes nil — the addendum is
    /// per-press, not persisted.
    static func runOneAppendingCandidate(target: PanelTarget,
                                         playerId: String,
                                         template: ClassTemplate,
                                         store: PlayerStore,
                                         generator: any PanelGenerator,
                                         addendum: String? = nil) async throws {
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
                                               tokens: ["camper_name": playerNameLookup(playerId: playerId, store: store)],
                                               addendum: addendum)
        let pngData = try await generator.generatePanel(prompt: prompt, references: references)
        let saved = try store.savePendingCandidate(playerId: playerId,
                                                   target: target.id,
                                                   pngData: pngData)
        appendAttempt(playerId: playerId, store: store, target: target.id,
                      prompt: prompt, candidate: saved)
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
            gallery = []
            cursor = .forNewHead(count: 0)
            return
        }
        let head = headTarget
        let newGallery = store.listCandidates(playerId: player.id, target: head.id)
        let wasEmpty = gallery.isEmpty
        let grew = newGallery.count > gallery.count
        gallery = newGallery
        // Cursor rules:
        // - empty → empty (placeholder card renders)
        // - just-appeared first candidate → start at 0
        // - re-roll appended a new candidate → jump to newest (slice E)
        // - regular tick with same count → keep operator's cursor where it is
        if newGallery.isEmpty {
            cursor = .forNewHead(count: 0)
        } else if wasEmpty {
            cursor = .forNewHead(count: newGallery.count)
        } else if grew {
            cursor = .afterAppend(count: newGallery.count)
        } else {
            cursor = GalleryCursor(index: cursor.index, count: newGallery.count)
        }
        headTick &+= 1
    }

    private func refreshBudget() {
        budget = store.generationBudget(playerId: player.id,
                                        panelCount: template.panels.count)
    }

    // MARK: - Gesture commits

    private func commitAcceptVisible() {
        let head = headTarget
        // Race: queue and operator both completed. `hasPanel` says we already
        // accepted something for this head — advance without re-accepting.
        if !store.hasPanel(playerId: player.id, target: head.id) {
            guard let visible else { return }
            do {
                try store.acceptCandidate(playerId: player.id,
                                          target: head.id,
                                          candidateIndex: visible.index)
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

    private func commitRerollHead() {
        guard !budget.isExhausted else {
            // Budget exhausted: bounce back + surface the slice-23 modal. The
            // operator can still cycle (up/down) or accept (right) — no further
            // gate needed because those don't spend budget.
            withAnimation(.spring) { swipeOffset = .zero }
            showExhaustionModal = true
            return
        }
        guard rerollTask == nil else {
            withAnimation(.spring) { swipeOffset = .zero }
            return
        }
        let head = headTarget
        let playerId = player.id
        let template = template
        let store = store
        let generator = generator
        withAnimation(.easeOut(duration: 0.2)) {
            swipeOffset = CGSize(width: -600, height: 0)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            swipeOffset = .zero
            // Optimistically clear the visible candidate so the placeholder
            // ("Re-rolling…") shows while the call is in flight. Gallery state
            // is the on-disk listing — we'll re-list when the task finishes.
            gallery = []
            cursor = .forNewHead(count: 0)
            headTick &+= 1
        }
        rerollTask = Task {
            defer { rerollTask = nil }
            do {
                try await Self.runOneAppendingCandidate(target: head,
                                                        playerId: playerId,
                                                        template: template,
                                                        store: store,
                                                        generator: generator)
                await MainActor.run {
                    refreshHead()
                    refreshBudget()
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run {
                    lastError = String(describing: error)
                    refreshHead()
                    refreshBudget()
                }
            }
        }
    }

    private func cycleGallery(forward: Bool) {
        guard gallery.count > 1 else { return }
        cursor = forward ? cursor.advanced() : cursor.retreated()
    }

    /// Slice F: long-press on the head card. Exhausted budget bounces to the
    /// same exhaustion modal as swipe-left Re-roll (per AC). Rolling Re-roll
    /// task in flight blocks new Re-prompts the same way.
    private func openRepromptSheet() {
        guard !budget.isExhausted else {
            showExhaustionModal = true
            return
        }
        guard rerollTask == nil else { return }
        showRepromptSheet = true
    }

    /// Slice F: Apply from the sheet. Spends 1 budget, fires the same
    /// `runOneAppendingCandidate` worker Re-roll uses (with the addendum
    /// threaded through to PromptBuilder), lands the new candidate in the
    /// gallery as newest. Empty addendum is treated as a no-op by the Apply
    /// button's `.disabled`, but we defend in depth here too.
    private func commitRepromptHead(addendum: String) {
        let trimmed = addendum.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !budget.isExhausted else {
            showExhaustionModal = true
            return
        }
        guard rerollTask == nil else { return }
        let head = headTarget
        let playerId = player.id
        let template = template
        let store = store
        let generator = generator
        // Clear visible so placeholder ("Re-rolling…") shows while in flight.
        // Re-uses the Re-roll spinner copy because the UX is identical from
        // the operator's perspective — one extra candidate is being generated.
        gallery = []
        cursor = .forNewHead(count: 0)
        headTick &+= 1
        rerollTask = Task {
            defer { rerollTask = nil }
            do {
                try await Self.runOneAppendingCandidate(target: head,
                                                        playerId: playerId,
                                                        template: template,
                                                        store: store,
                                                        generator: generator,
                                                        addendum: trimmed)
                await MainActor.run {
                    refreshHead()
                    refreshBudget()
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run {
                    lastError = String(describing: error)
                    refreshHead()
                    refreshBudget()
                }
            }
        }
    }

    /// Read-only context shown at the top of the Re-prompt sheet so the
    /// operator can see what they're appending to. Built fresh each open;
    /// not stored.
    private var assembledPromptForHead: String {
        PromptBuilder.buildPrompt(for: headTarget,
                                  template: template,
                                  tokens: ["camper_name": player.playerName])
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

    private var visible: PanelCandidate? {
        guard !gallery.isEmpty, cursor.index < gallery.count else { return nil }
        return gallery[cursor.index]
    }

    private var isRerolling: Bool {
        rerollTask != nil
    }

    private func loadImage(_ url: URL) -> UIImage? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()
}

/// Slice F (#66): long-press Re-prompt editor. Shows the fully assembled
/// prompt (read-only context) above a writable Addendum `TextEditor`. Apply
/// returns the addendum to the caller; the caller appends it after the
/// assembled prompt with a blank-line separator and fires generation. The
/// addendum is per-press — the field starts empty on every open (no
/// `@AppStorage`, no caller-held draft) because in practice corrective
/// addenda ("less smoke", "the prop should be visible") are one-shot and
/// persisting them would silently bias every Re-roll on the panel.
///
/// This sheet is distinct from `RepromptSheet` in `PanelReviewView.swift`,
/// which edits the preamble in place (slice 11c, panel-loop UX). The new
/// swipe-review surface deliberately leaves the assembled prompt locked and
/// only appends the addendum, per ADR-0009 (and the slice F issue spec).
private struct RepromptAddendumSheet: View {
    @Environment(\.themeKind) private var theme
    let assembledPrompt: String
    let onApply: (String) -> Void
    let onCancel: () -> Void

    @State private var addendum: String = ""

    private var trimmedIsEmpty: Bool {
        addendum.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        let p = theme.palette
        return NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("Assembled prompt")
                    .font(theme.captionFont(12))
                    .foregroundStyle(p.inkSecondary)
                ScrollView {
                    Text(assembledPrompt)
                        .font(.callout.monospaced())
                        .foregroundStyle(p.inkSecondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(maxHeight: 200)
                .background(Color(.secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                Text("Addendum")
                    .font(theme.captionFont(12))
                    .foregroundStyle(p.inkSecondary)
                TextEditor(text: $addendum)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color(.secondarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .frame(minHeight: 140)
                Text("Appended after the assembled prompt. Spends 1 generation.")
                    .font(theme.captionFont(12))
                    .foregroundStyle(p.inkSecondary)
                Spacer(minLength: 0)
            }
            .padding()
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Re-prompt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") { onApply(addendum) }
                        .disabled(trimmedIsEmpty)
                }
            }
        }
    }
}

/// Slice E: row of dots beneath the head card, one per candidate, filled at
/// the cursor's index. Caps at six visible dots — beyond that the gallery is
/// either a rendering nightmare or a sign the operator is in a re-roll
/// runaway loop; either way "1 of 9" in the label still tells them where
/// they are. Color uses the accent palette so it visually rhymes with the
/// ACCEPT / RE-ROLL badges.
struct DotIndicatorView: View {
    @Environment(\.themeKind) private var theme
    let cursor: GalleryCursor

    private static let maxVisibleDots = 6

    var body: some View {
        let p = theme.palette
        let visibleCount = min(cursor.count, Self.maxVisibleDots)
        HStack(spacing: 6) {
            ForEach(0..<visibleCount, id: \.self) { i in
                Circle()
                    .fill(i == cursor.index ? p.accent : p.inkSecondary.opacity(0.3))
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityLabel(Text("Candidate \(cursor.positionLabel)"))
    }
}

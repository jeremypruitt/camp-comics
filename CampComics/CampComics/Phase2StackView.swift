import SwiftUI
import UIKit
import CampComicsCore

/// Translate a generation error into a one-line operator-friendly message.
/// The raw `String(describing: error)` for a wrapped Firebase/URL error is
/// developer ergonomics — operators get "network glitch" or "rate limited",
/// not `internalError(underlying: NSURLErrorDomain Code=-1005...)`.
private func friendlyErrorMessage(_ error: Error) -> String {
    if let g = error as? PanelGeneratorError {
        switch g {
        case .noImageReturned:
            return "The model returned no image. Try Re-prompt with different wording, or Defer."
        case .throttled:
            return "Rate limited. Wait a few seconds and Retry."
        case .underlying(let inner):
            return humanizeRawErrorString(inner)
        }
    }
    let nsErr = error as NSError
    if nsErr.domain == NSURLErrorDomain {
        return urlErrorMessage(code: nsErr.code)
    }
    return humanizeRawErrorString(String(describing: error))
}

private func humanizeRawErrorString(_ raw: String) -> String {
    if raw.contains("NSURLErrorDomain") {
        for code in [-1005, -1009, -1001, -1003, -1004, -1011] where raw.contains("Code=\(code)") {
            return urlErrorMessage(code: code)
        }
        return "Network glitch. Tap Retry."
    }
    if raw.lowercased().contains("safety") || raw.lowercased().contains("blocked") {
        return "The model refused this prompt. Try Re-prompt with different wording."
    }
    return "Generation failed. Tap Retry, or Defer to come back later."
}

private func urlErrorMessage(code: Int) -> String {
    switch code {
    case -1005, -1009: return "Network connection lost. Tap Retry."
    case -1001:        return "Request timed out. Tap Retry."
    case -1003, -1004: return "Couldn't reach the server. Tap Retry."
    case -1011:        return "Server returned an error. Tap Retry."
    default:           return "Network glitch. Tap Retry."
    }
}

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
    /// Slice G (#67): set during an in-flight atomic triptych Re-roll /
    /// Re-prompt — three concurrent sub-panel generations under one parent.
    /// Bound to `triptychRerollTask` rather than `rerollTask` so the per-panel
    /// gating logic stays a clean "single in-flight" check for single units.
    @State private var triptychRerollTask: Task<Void, Never>?
    @State private var headTick: Int = 0
    @State private var budget: GenerationBudget
    @State private var lastError: String?
    @State private var showExhaustionModal: Bool = false
    @State private var showRepromptSheet: Bool = false
    /// Slice H (#68): failure message for the current head. Set when the queue
    /// emits `.failed(headTargetID, message)` or when an ad-hoc Re-roll /
    /// Re-prompt task throws. Drives the failed-card render; cleared on
    /// Retry, Defer, and head advance. Behind-head failures persist via the
    /// on-disk `.failed` marker and resurface as a failed card when the
    /// stack reaches them (with no message).
    @State private var failedHeadMessage: String?
    /// Slice I (#69): grid sheet visibility. Tapped via the toolbar grid icon
    /// (mid-flight escape hatch) or auto-presented when every Phase-2 unit
    /// reaches a terminal disk state (accepted or deferred).
    @State private var showingGrid: Bool = false
    /// Slice I (#69): one-shot guard so the grid auto-presents only once per
    /// session. The operator can dismiss it (e.g. to re-roll a panel) and
    /// re-summon it from the toolbar without it re-springing every headTick.
    @State private var autoPresentedGrid: Bool = false
    /// Slice I (#69): set when an Accepted cell is tapped from the grid —
    /// surfaces a confirm before demoting the accepted PNG back into the
    /// candidate gallery.
    @State private var pendingAcceptedDemoteID: PanelTargetID?
    /// Slice I (#69): set when a Deferred (Failed) cell is tapped — surfaces
    /// a Retry confirm before unmarking the sentinel and re-enqueueing.
    @State private var pendingDeferredRetryID: PanelTargetID?
    /// Slice I (#69): ad-hoc target re-generation task (Retry-from-grid).
    /// Distinct from `rerollTask` because the target may not be the current
    /// head — the operator could trigger a re-generation for a panel they
    /// jumped to but haven't reviewed yet.
    @State private var gridRetryTask: Task<Void, Never>?
    /// Slice I (#69): PDF preview presented after the grid's Generate-PDF CTA
    /// finishes rendering. Uses the same `PreviewItem` + `PDFPreview` pair as
    /// `PlayerDetailView`.
    @State private var pdfPreviewItem: PreviewItem?
    @State private var isRenderingPDF: Bool = false
    @State private var pendingDeferredFinalize: [String] = []
    let trialBackend: any SponsoredTrialBackend

    init(player: PlayerRecord,
         template: ClassTemplate,
         store: PlayerStore,
         generator: any PanelGenerator,
         trialBackend: any SponsoredTrialBackend = FirestoreSponsoredTrialBackend()) {
        self.player = player
        self.template = template
        self.store = store
        self.generator = generator
        self.trialBackend = trialBackend
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
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showingGrid = true
                } label: {
                    Image(systemName: "square.grid.3x3")
                }
                .accessibilityLabel("Open panel grid")
            }
        }
        .onAppear { startQueueIfNeeded() }
        .onDisappear {
            queueTask?.cancel()
            rerollTask?.cancel()
            triptychRerollTask?.cancel()
            gridRetryTask?.cancel()
        }
        .onChange(of: headTick) { _, _ in maybeAutoPresentGrid() }
        .sheet(isPresented: $showExhaustionModal) {
            exhaustionModal
        }
        .sheet(isPresented: $showingGrid) {
            gridSheet
        }
        .sheet(item: $pdfPreviewItem) { item in
            PDFPreview(url: item.url)
        }
        .confirmationDialog(
            acceptedDemoteMessage,
            isPresented: Binding(get: { pendingAcceptedDemoteID != nil },
                                 set: { if !$0 { pendingAcceptedDemoteID = nil } }),
            titleVisibility: .visible
        ) {
            Button("Re-roll") {
                if let id = pendingAcceptedDemoteID {
                    pendingAcceptedDemoteID = nil
                    performAcceptedDemote(id: id)
                }
            }
            Button("Cancel", role: .cancel) { pendingAcceptedDemoteID = nil }
        }
        .confirmationDialog(
            deferredRetryMessage,
            isPresented: Binding(get: { pendingDeferredRetryID != nil },
                                 set: { if !$0 { pendingDeferredRetryID = nil } }),
            titleVisibility: .visible
        ) {
            Button("Retry") {
                if let id = pendingDeferredRetryID {
                    pendingDeferredRetryID = nil
                    performDeferredRetry(id: id)
                }
            }
            Button("Cancel", role: .cancel) { pendingDeferredRetryID = nil }
        }
        .confirmationDialog(
            deferredFinalizeMessage,
            isPresented: Binding(get: { !pendingDeferredFinalize.isEmpty },
                                 set: { if !$0 { pendingDeferredFinalize = [] } }),
            titleVisibility: .visible
        ) {
            Button("Generate anyway") {
                pendingDeferredFinalize = []
                Task { await generatePDF() }
            }
            Button("Cancel", role: .cancel) { pendingDeferredFinalize = [] }
        }
        .sheet(isPresented: $showRepromptSheet) {
            RepromptAddendumSheet(
                assembledPrompt: assembledPromptForHead,
                onApply: { addendum in
                    showRepromptSheet = false
                    // Slice G: triptych Re-prompt fans the shared addendum
                    // out to all 3 sub-panels; single-unit Re-prompt stays
                    // on the slice-F single-target path.
                    switch headUnit {
                    case .triptych: commitRepromptTriptych(addendum: addendum)
                    case .single: commitRepromptHead(addendum: addendum)
                    }
                },
                onCancel: { showRepromptSheet = false }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Slice I (#69) — grid sheet + auto-present + cell-tap routing

    private var gridSheet: some View {
        NavigationStack {
            PanelGridView(
                player: player,
                template: template,
                store: store,
                onSelect: handleGridSelect,
                onGeneratePDF: { onGeneratePDFTapped() },
                generatePDFLabel: "Generate PDF",
                isGeneratingPDF: isRenderingPDF
            )
            .navigationTitle("Grid")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showingGrid = false }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func maybeAutoPresentGrid() {
        guard !autoPresentedGrid else { return }
        guard !showingGrid else { return }
        guard ReviewUnit.allTerminal(units: units, playerId: player.id, store: store) else {
            return
        }
        autoPresentedGrid = true
        showingGrid = true
    }

    /// Slice I (#69): route a grid cell tap by the cell's disk-derived status.
    /// Accepted → demote-confirm; deferred → retry-confirm; unstarted/reviewing
    /// → jump head silently (the operator just wants to see that panel in the
    /// stack). `.missingPhoto` is unreachable on the swipe surface because
    /// every panel has its photo by the time Phase 2 starts, but we treat it
    /// the same as unstarted (silent jump) defensively.
    private func handleGridSelect(targetID: PanelTargetID) {
        guard let target = lookupTarget(id: targetID) else { return }
        let status = PanelGridCellStatus.derive(target: target,
                                                playerId: player.id,
                                                store: store)
        switch status {
        case .accepted:
            pendingAcceptedDemoteID = targetID
        case .failed:
            pendingDeferredRetryID = targetID
        case .reviewing, .unstarted, .missingPhoto:
            jumpHead(to: targetID)
            showingGrid = false
        }
    }

    private var acceptedDemoteMessage: String {
        guard let id = pendingAcceptedDemoteID else { return "" }
        return "Re-roll \(humanLabel(for: id))? The current accepted image will return to the gallery as candidate #1."
    }

    private var deferredRetryMessage: String {
        guard let id = pendingDeferredRetryID else { return "" }
        return "Retry \(humanLabel(for: id))? The previous failure marker will be cleared and the panel will re-generate."
    }

    private func humanLabel(for id: PanelTargetID) -> String {
        switch id {
        case .panel(let n): return "panel \(n)"
        case .cover: return "the cover"
        }
    }

    /// Demote-then-jump: writes the accepted PNG back into the candidate dir
    /// as index 0 (operator's prior choice stays visible) and re-positions the
    /// head. The operator can swipe-left to spend a new Re-roll or swipe-right
    /// to re-accept the demoted image; we don't auto-fire a generation because
    /// the issue spec routes that decision through the existing swipe gesture.
    private func performAcceptedDemote(id: PanelTargetID) {
        do {
            try store.demoteAcceptedToCandidate(playerId: player.id, target: id)
        } catch {
            lastError = friendlyErrorMessage(error)
            return
        }
        jumpHead(to: id)
        showingGrid = false
    }

    /// Retry-from-grid: clears the `.failed` sentinel, jumps the head to the
    /// containing unit, and fires a single ad-hoc generation for that target.
    /// For triptych sub-panels, only the tapped sub-panel re-generates — the
    /// other two sub-panels (which might already be accepted or deferred) are
    /// untouched. Once the new candidate lands, the triptych super-card
    /// re-renders automatically per slice G.
    private func performDeferredRetry(id: PanelTargetID) {
        try? store.unmarkDeferred(playerId: player.id, target: id)
        jumpHead(to: id)
        showingGrid = false
        guard !budget.isExhausted else {
            showExhaustionModal = true
            return
        }
        guard let target = lookupTarget(id: id) else { return }
        gridRetryTask?.cancel()
        let playerId = player.id
        let template = template
        let store = store
        let generator = generator
        gridRetryTask = Task {
            defer {
                Task { @MainActor in
                    gridRetryTask = nil
                    refreshHead()
                    refreshBudget()
                }
            }
            do {
                try await Self.runOneAppendingCandidate(target: target,
                                                        playerId: playerId,
                                                        template: template,
                                                        store: store,
                                                        generator: generator)
                await MainActor.run {
                    failedHeadMessage = nil
                    refreshHead()
                    refreshBudget()
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run {
                    // Surface the failure on the head card if this id is the
                    // current head; otherwise persist the deferred marker so
                    // the grid stays in `.failed` for next time.
                    if headTarget.id == id || headUnitContains(id: id) {
                        failedHeadMessage = friendlyErrorMessage(error)
                    } else {
                        try? store.markDeferred(playerId: player.id, target: id)
                    }
                    refreshHead()
                    refreshBudget()
                }
            }
        }
    }

    private func jumpHead(to id: PanelTargetID) {
        guard let idx = ReviewUnit.unitIndex(for: id, in: units) else { return }
        headIndex = idx
        failedHeadMessage = nil
        refreshHead()
    }

    /// Looks up the full `PanelTarget` (with spec payload) for a `PanelTargetID`
    /// by scanning the template. Needed for `PanelGridCellStatus.derive` and
    /// for the ad-hoc retry task's `runOneAppendingCandidate` call.
    private func lookupTarget(id: PanelTargetID) -> PanelTarget? {
        switch id {
        case .panel(let n):
            guard let spec = template.panels.first(where: { $0.n == n }) else { return nil }
            return .panel(n: n, spec: spec)
        case .cover:
            return .cover(spec: template.cover)
        }
    }

    // MARK: - Slice I (#69) — Generate PDF from the grid sheet

    private func onGeneratePDFTapped() {
        let deferredNames = deferredTargetNames()
        if deferredNames.isEmpty {
            Task { await generatePDF() }
        } else {
            pendingDeferredFinalize = deferredNames
        }
    }

    /// Story-ordered human labels for every deferred target — fed into the
    /// empty-cells confirm copy mirrored from `PlayerDetailView`'s slice-H
    /// implementation so the operator gets the same warning whether they
    /// finalize from player detail or from the grid sheet.
    private func deferredTargetNames() -> [String] {
        var names: [String] = []
        for panel in template.panels where store.isDeferred(playerId: player.id, target: .panel(panel.n)) {
            names.append("Panel \(panel.n)")
        }
        if store.isDeferred(playerId: player.id, target: .cover) {
            names.append("Cover")
        }
        return names
    }

    private var deferredFinalizeMessage: String {
        let names = pendingDeferredFinalize
        if names.count == 1 {
            return "\(names[0]) has no image — your comic will have an empty cell. Generate anyway?"
        }
        let joined = names.joined(separator: ", ")
        return "\(joined) have no images — your comic will have empty cells. Generate anyway?"
    }

    private func generatePDF() async {
        isRenderingPDF = true
        defer { isRenderingPDF = false }
        do {
            let url = try await PDFRenderer.render(player: player,
                                                   template: template,
                                                   store: store)
            // Dismiss the grid sheet before presenting the PDF preview —
            // SwiftUI won't stack two sheets from the same host view, and
            // the preview is the natural endpoint once render succeeds.
            showingGrid = false
            // Small delay so the grid's dismissal animation completes before
            // the preview sheet animates in; without it the second sheet
            // either drops the presentation or stutters.
            try? await Task.sleep(nanoseconds: 350_000_000)
            pdfPreviewItem = PreviewItem(url: url)
            if BillingModeStore().current == .sponsored {
                let backend = trialBackend
                let playerId = player.id
                Task { try? await backend.recordFinalized(playerId: playerId) }
            }
        } catch {
            lastError = "PDF render failed: \(error.localizedDescription)"
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
        // Camp Comics invariant (feedback-failures-never-penalize-user): no
        // failed-card branch here. The queue auto-retries transparently, so
        // an in-flight panel just stays as the placeholder card until a
        // candidate lands. True terminal failures (extremely rare after 7
        // queue retries) leave the panel uncreated; the operator can re-
        // trigger from the grid if they care.
        if isAllDone {
            doneCard
        } else {
            switch headUnit {
            case .single:
                if let visible, let image = loadImage(visible.url) {
                    candidateCard(candidate: visible, image: image)
                } else {
                    placeholderCard
                }
            case .triptych(let trip):
                triptychCardBody(trip: trip)
            }
        }
    }

    @ViewBuilder
    private func triptychCardBody(trip: PanelTriptych) -> some View {
        // Slice G (#67) AC: super-card waits for all 3 sub-panels to have a
        // candidate before rendering. While any is in flight or queued, the
        // card stays in placeholder state.
        if let images = triptychImages(trip: trip) {
            triptychCard(trip: trip, images: images)
        } else {
            placeholderCard
        }
    }

    /// Loads the latest candidate for each of the triptych's three sub-panels.
    /// Returns nil if any sub-panel has no candidate yet (placeholder shows).
    private func triptychImages(trip: PanelTriptych) -> [UIImage]? {
        var out: [UIImage] = []
        for id in trip.subTargetIDs {
            let candidates = store.listCandidates(playerId: player.id, target: id)
            // Prefer the newest candidate as the "currently visible" frame.
            // If the sub-panel was already accepted in a prior session (we
            // jumped back into the stack), fall back to the accepted PNG.
            if let newest = candidates.max(by: { $0.index < $1.index }),
               let img = loadImage(newest.url) {
                out.append(img)
            } else if let bytes = store.loadPanel(playerId: player.id, target: id),
                      let img = UIImage(data: bytes) {
                out.append(img)
            } else {
                return nil
            }
        }
        return out
    }

    /// Slice H: a head shows the failed card when either (a) we got a runtime
    /// failure for this exact head, or (b) the head has a persisted `.failed`
    /// marker on disk (a behind-head failure that survived to its turn, or a
    /// prior session's deferred panel returned to).
    private var isHeadFailed: Bool {
        if failedHeadMessage != nil { return true }
        return store.isDeferred(playerId: player.id, target: headTarget.id)
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
        VStack(spacing: 10) {
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

    /// Slice G (#67): one composited super-card for a P-in or H-out triptych.
    /// Renders the three sub-panel images through `TriptychCardView`'s
    /// clip-path shapes (a SwiftUI rendition of the ADR-0007 print layout) and
    /// hooks the same swipe + long-press gestures as the single-panel card —
    /// but the commits route to the atomic triptych helpers below.
    private func triptychCard(trip: PanelTriptych, images: [UIImage]) -> some View {
        VStack(spacing: 10) {
            TriptychCardView(kind: trip.kind, images: images)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .offset(swipeOffset)
                .rotationEffect(.degrees(Double(swipeOffset.width / 20)))
                .overlay(alignment: .topTrailing) { acceptBadge }
                .overlay(alignment: .topLeading) { rerollBadge }
                .gesture(triptychStackGesture)
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.5)
                        .onEnded { _ in openRepromptSheet() }
                )
            triptychFooter(trip: trip)
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private func triptychFooter(trip: PanelTriptych) -> some View {
        let p = theme.palette
        let label = trip.kind == .pIn ? "Triptych — panels 3, 4, 5"
                                       : "Triptych — panels 12, 13, 14"
        HStack(spacing: 10) {
            Text(label)
                .font(theme.captionFont(12))
                .foregroundStyle(p.inkSecondary)
            Spacer()
            Text("Re-roll spends 3")
                .font(theme.captionFont(12))
                .foregroundStyle(p.inkSecondary)
        }
        .padding(.top, 4)
    }

    /// Triptych gestures: only swipe-left / swipe-right / long-press are
    /// meaningful — gallery cycling (swipe-up/down) is intentionally disabled
    /// because the ADR-0007 design treats the three sub-panels as one
    /// composition, so "cycle this one sub-panel" doesn't have a coherent UX.
    private var triptychStackGesture: some Gesture {
        DragGesture()
            .onChanged { swipeOffset = $0.translation }
            .onEnded { value in
                let t = value.translation
                let absX = abs(t.width)
                let absY = abs(t.height)
                if absX > absY {
                    if t.width > 120 {
                        commitAcceptTriptych()
                    } else if t.width < -120 {
                        commitRerollTriptych()
                    } else {
                        withAnimation(.spring) { swipeOffset = .zero }
                    }
                } else {
                    withAnimation(.spring) { swipeOffset = .zero }
                }
            }
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

    /// Slice H (#68): Failed-card surface for a head whose generation threw
    /// (queue-side or ad-hoc Re-roll/Re-prompt). Retry kicks off another
    /// generation against the head (spends a budget call on success, same as
    /// any other generation); Defer writes the `.failed` marker and advances
    /// the stack so the operator can come back later from the grid (slice I).
    /// Long-press anywhere on the card opens the Re-prompt sheet — the
    /// documented content-policy-bounce recovery path. Defer is intentionally
    /// styled as a less-prominent secondary button so the operator's reflex
    /// stays "try again" first.
    private var failedCard: some View {
        let p = theme.palette
        return ThemedCard {
            VStack(alignment: .leading, spacing: 14) {
                Text(failedCardTitle)
                    .font(theme.headingFont(18))
                    .foregroundStyle(p.inkPrimary)
                if let failedHeadMessage {
                    Text(failedHeadMessage)
                        .font(theme.captionFont(12))
                        .foregroundStyle(p.danger)
                        .lineLimit(4)
                } else {
                    Text("This panel didn't generate. Retry, long-press to add an addendum, or defer to come back later from the grid.")
                        .font(theme.captionFont(12))
                        .foregroundStyle(p.inkSecondary)
                }
                ThemedPrimaryButton("Retry", systemImage: "arrow.clockwise") {
                    commitRetryHead()
                }
                Button(action: commitDeferHead) {
                    Text("Defer for now")
                        .font(theme.captionFont(12))
                        .tracking(2)
                        .textCase(.uppercase)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .foregroundStyle(p.inkSecondary)
                        .overlay(
                            Capsule().stroke(p.inkSecondary.opacity(0.4), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in openRepromptSheet() }
        )
    }

    private var failedCardTitle: String {
        switch headTarget {
        case .panel(let n, _): return "Panel \(n) didn't generate"
        case .cover: return "Cover didn't generate"
        }
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
        let totalPanels = targets.count // panels 2..N + cover
        switch headUnit {
        case .single(let target):
            switch target {
            case .panel(let n, _): return "Panel \(n) of \(totalPanels)"
            case .cover: return "Cover"
            }
        case .triptych(let trip):
            let nums = trip.kind.subPanelNumbers
            return "Panels \(nums[0])–\(nums[2]) (triptych)"
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
                            // Triptych head: any of its three sub-panels
                            // landing on disk is "head moved" because the
                            // composited card re-renders when all three have
                            // candidates. The single-unit branch matches on
                            // exact head target id.
                            if headUnitContains(id: id) {
                                refreshHead()
                            } else {
                                headTick &+= 1
                            }
                            refreshBudget()
                        case .throttled:
                            refreshBudget()
                        case .failed(let id, let message):
                            // Camp Comics invariant (feedback-failures-never-
                            // penalize-user): background failures don't reach
                            // the user as actionable. The queue already
                            // auto-retried 7× with exponential backoff before
                            // emitting `.failed`. We log + nudge the view to
                            // re-render, but the panel sits as not-yet-
                            // generated and the operator can re-trigger from
                            // the grid if they care.
                            NSLog("Camp Comics: terminal panel failure after queue retries — id=%@ message=%@", String(describing: id), message)
                            headTick &+= 1
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
        // Slice H (#68): a deferred panel must not auto-regenerate on session
        // start — the operator chose to skip it; auto-retrying would burn
        // budget silently. The explicit Retry button on the failed card is
        // the only way back in (or slice I's grid escape hatch).
        if store.isDeferred(playerId: playerId, target: target.id) { return }
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
        // Auto-advance past any review unit whose work is fully accepted on
        // disk (re-entry path: triptych accepted in a prior session, or single
        // panel accepted by another surface). Bounded by `units.count`.
        while headIndex < units.count, isUnitFullyAccepted(units[headIndex]) {
            headIndex += 1
        }
        if isAllDone {
            gallery = []
            cursor = .forNewHead(count: 0)
            return
        }
        switch headUnit {
        case .single(let head):
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
        case .triptych:
            // Triptychs don't use the single-unit `gallery` / `cursor` state —
            // `triptychImages` reads from disk on every render. Clear the
            // single-unit state so a stale tail from a prior unit doesn't
            // bleed through if the operator navigates back.
            gallery = []
            cursor = .forNewHead(count: 0)
        }
        headTick &+= 1
    }

    private func isUnitFullyAccepted(_ unit: ReviewUnit) -> Bool {
        switch unit {
        case .single(let target):
            return store.hasPanel(playerId: player.id, target: target.id)
        case .triptych(let trip):
            return trip.allSubPanelsAccepted(playerId: player.id, store: store)
        }
    }

    private func headUnitContains(id: PanelTargetID) -> Bool {
        switch headUnit {
        case .single(let target): return target.id == id
        case .triptych(let trip): return trip.subTargetIDs.contains(id)
        }
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
                lastError = friendlyErrorMessage(error)
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
            failedHeadMessage = nil
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
                    failedHeadMessage = nil
                    refreshHead()
                    refreshBudget()
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run {
                    // Slice H: surface a failed card (with Retry/Defer) for
                    // this head instead of the tiny "lastError" banner.
                    failedHeadMessage = friendlyErrorMessage(error)
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

    // MARK: - Slice G (#67) — atomic triptych commits

    /// Atomic Accept: writes all three `panel_NN.png` files in one transaction.
    /// On success, the stack advances past the whole triptych in one step.
    private func commitAcceptTriptych() {
        guard case .triptych(let trip) = headUnit else { return }
        if !trip.allSubPanelsAccepted(playerId: player.id, store: store) {
            // Build choices: newest candidate index per sub-panel (the one
            // currently displayed in the super-card).
            var choices: [PanelTargetID: Int] = [:]
            for id in trip.subTargetIDs {
                let candidates = store.listCandidates(playerId: player.id, target: id)
                guard let newest = candidates.max(by: { $0.index < $1.index }) else {
                    // Should be unreachable — the super-card only renders once
                    // every sub-panel has a candidate. Bounce defensively.
                    withAnimation(.spring) { swipeOffset = .zero }
                    return
                }
                choices[id] = newest.index
            }
            do {
                try trip.acceptAtomically(playerId: player.id,
                                          store: store,
                                          choices: choices)
            } catch {
                lastError = friendlyErrorMessage(error)
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

    /// Atomic Re-roll: spawns three concurrent `runOneAppendingCandidate`
    /// tasks (one per sub-panel) under one parent. Spends 3 budget calls
    /// (each sub-panel debits 1 when its task completes). The super-card
    /// re-renders with the newest-of-three composition once all three tasks
    /// finish. Bounces if budget is exhausted or any roll task is in flight.
    private func commitRerollTriptych() {
        guard case .triptych(let trip) = headUnit else { return }
        guard budget.remaining >= PanelTriptych.budgetCost else {
            withAnimation(.spring) { swipeOffset = .zero }
            showExhaustionModal = true
            return
        }
        guard triptychRerollTask == nil, rerollTask == nil else {
            withAnimation(.spring) { swipeOffset = .zero }
            return
        }
        withAnimation(.easeOut(duration: 0.2)) {
            swipeOffset = CGSize(width: -600, height: 0)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            swipeOffset = .zero
            // Force the super-card into placeholder state until every
            // sub-panel has a new candidate (atomic "all-3-or-spinner" rule).
            // We don't have a separate "in-flight" flag for triptychs because
            // the placeholder check is naturally driven by
            // `triptychImages` returning nil while sub-galleries refresh.
            headTick &+= 1
        }
        triptychRerollTask = launchTriptychRoll(trip: trip, addendum: nil)
    }

    /// Atomic Re-prompt: same as Re-roll but threads a shared addendum into
    /// each sub-panel's prompt builder. Per ADR-0009 the addendum applies
    /// uniformly to all three sub-panels.
    private func commitRepromptTriptych(addendum: String) {
        let trimmed = addendum.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard case .triptych(let trip) = headUnit else { return }
        guard budget.remaining >= PanelTriptych.budgetCost else {
            showExhaustionModal = true
            return
        }
        guard triptychRerollTask == nil, rerollTask == nil else { return }
        headTick &+= 1
        triptychRerollTask = launchTriptychRoll(trip: trip, addendum: trimmed)
    }

    /// Shared launcher for Re-roll + Re-prompt. Runs three sub-panel
    /// generations concurrently under one parent task; budget is debited
    /// per-sub-panel inside `runOneAppendingCandidate` (so 3 sub-panels
    /// completing = 3 debits = `PanelTriptych.budgetCost`).
    private func launchTriptychRoll(trip: PanelTriptych,
                                    addendum: String?) -> Task<Void, Never> {
        let playerId = player.id
        let template = template
        let store = store
        let generator = generator
        return Task {
            defer {
                Task { @MainActor in
                    triptychRerollTask = nil
                    refreshHead()
                    refreshBudget()
                }
            }
            await withTaskGroup(of: Result<Void, Error>.self) { group in
                for sub in trip.subTargets {
                    group.addTask {
                        do {
                            try await Self.runOneAppendingCandidate(target: sub,
                                                                    playerId: playerId,
                                                                    template: template,
                                                                    store: store,
                                                                    generator: generator,
                                                                    addendum: addendum)
                            return .success(())
                        } catch is CancellationError {
                            return .success(())
                        } catch {
                            return .failure(error)
                        }
                    }
                }
                var firstError: Error?
                for await result in group {
                    if case .failure(let err) = result, firstError == nil {
                        firstError = err
                    }
                }
                if let firstError {
                    await MainActor.run {
                        lastError = String(describing: firstError)
                    }
                }
            }
        }
    }

    /// Slice F: long-press on the head card. Exhausted budget bounces to the
    /// same exhaustion modal as swipe-left Re-roll (per AC). Rolling Re-roll
    /// task in flight blocks new Re-prompts the same way. Slice G: triptych
    /// heads need 3 budget calls available (not just 1) and also gate on the
    /// triptych roll task.
    private func openRepromptSheet() {
        let neededBudget: Int
        switch headUnit {
        case .triptych: neededBudget = PanelTriptych.budgetCost
        case .single: neededBudget = 1
        }
        guard budget.remaining >= neededBudget else {
            showExhaustionModal = true
            return
        }
        guard rerollTask == nil, triptychRerollTask == nil else { return }
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
                    failedHeadMessage = nil
                    refreshHead()
                    refreshBudget()
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run {
                    // Slice H: same failed-card surface as Re-roll. Re-prompt
                    // is the documented content-policy bounce recovery — a
                    // failed Re-prompt drops back to the same Retry/Defer
                    // affordances, with Defer being the final out.
                    failedHeadMessage = friendlyErrorMessage(error)
                    refreshHead()
                    refreshBudget()
                }
            }
        }
    }

    // MARK: - Slice H (#68) — failed-card actions

    /// Retry: re-fire the same `runOneAppendingCandidate` worker Re-roll uses.
    /// Spends one budget call on success (failures don't decrement, same
    /// semantics as Re-roll). On success the new candidate lands in the
    /// gallery and the failed card is replaced with the regular review card.
    private func commitRetryHead() {
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
        failedHeadMessage = nil
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
                                                        generator: generator)
                await MainActor.run {
                    failedHeadMessage = nil
                    refreshHead()
                    refreshBudget()
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run {
                    failedHeadMessage = friendlyErrorMessage(error)
                    refreshHead()
                    refreshBudget()
                }
            }
        }
    }

    /// Defer: write the `.failed` sentinel for this head (so the grid pill
    /// reads "deferred" and `PlayerStatus` counts it as resolved), then
    /// advance the stack. Per ADR-0009 the operator can come back from the
    /// grid (slice I — #69) to retry later, but for now we just move on.
    private func commitDeferHead() {
        let head = headTarget
        try? store.markDeferred(playerId: player.id, target: head.id)
        withAnimation(.easeOut(duration: 0.2)) {
            swipeOffset = CGSize(width: 600, height: 0)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            swipeOffset = .zero
            headIndex += 1
            failedHeadMessage = nil
            refreshHead()
            refreshBudget()
        }
    }

    /// Read-only context shown at the top of the Re-prompt sheet so the
    /// operator can see what they're appending to. Built fresh each open;
    /// not stored. Triptych heads concatenate all three sub-panel prompts
    /// with a separator so the addendum's "applies to all 3" semantic is
    /// visible.
    private var assembledPromptForHead: String {
        switch headUnit {
        case .single(let target):
            return PromptBuilder.buildPrompt(for: target,
                                             template: template,
                                             tokens: ["camper_name": player.playerName])
        case .triptych(let trip):
            return trip.subTargets.enumerated().map { (i, sub) -> String in
                let body = PromptBuilder.buildPrompt(for: sub,
                                                     template: template,
                                                     tokens: ["camper_name": player.playerName])
                return "— Sub-panel \(i + 1) of 3 —\n\(body)"
            }.joined(separator: "\n\n")
        }
    }

    // MARK: - Targets

    /// Flat story-ordered targets for Phase 2: panels 2..N then the cover.
    /// Panel 1 is excluded because Phase 1 already finalized it. The queue
    /// generator pulls from this list — it's intentionally NOT grouped into
    /// triptychs because each sub-panel is still an independent API call.
    private var targets: [PanelTarget] {
        var out: [PanelTarget] = template.panels
            .filter { $0.n != 1 }
            .sorted { $0.n < $1.n }
            .map { .panel(n: $0.n, spec: $0) }
        out.append(.cover(spec: template.cover))
        return out
    }

    /// Slice G (#67) review units — same panels as `targets`, but with the
    /// P-in (panels 3–5) and H-out (panels 12–14) sub-panels collapsed into
    /// `.triptych` super-units. The head walks these units one at a time.
    private var units: [ReviewUnit] {
        ReviewUnit.phase2Units(from: template)
    }

    /// `.single` head's underlying target (used by single-unit code paths).
    /// Falls back to the last target's id when out of range so prompt-builder
    /// helpers that read `headTarget` after all-done don't crash; the
    /// `isAllDone` gate keeps them from rendering anyway.
    private var headTarget: PanelTarget {
        if case .single(let target) = headUnit { return target }
        // For triptych heads, code paths that genuinely need a `PanelTarget`
        // (assembled-prompt context display) shouldn't reach here — the
        // triptych branches have their own helpers. Return the first sub-target
        // as a defensive default.
        if case .triptych(let trip) = headUnit, let first = trip.subTargets.first {
            return first
        }
        return targets[max(0, min(headIndex, targets.count - 1))]
    }

    private var headUnit: ReviewUnit {
        units[min(headIndex, units.count - 1)]
    }

    private var isAllDone: Bool {
        headIndex >= units.count
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
/// The swipe-review surface deliberately leaves the assembled prompt locked
/// and only appends the addendum, per ADR-0009 (and the slice F issue spec).
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

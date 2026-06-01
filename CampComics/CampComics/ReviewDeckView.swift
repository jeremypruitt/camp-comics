import SwiftUI
import UIKit
import CampComicsCore

/// ADR-0010 review surface. Card-deck replacement for `Phase2StackView`: all
/// twelve review units are mounted from t=0 as a single deck, with panel 1 on
/// top. Panel 1 serializes sequentially; the moment a candidate lands, the
/// remaining targets (panels 2–15 + cover) fan out through `GenerationQueue`.
///
/// Gesture vocabulary is **inverted** from `Phase2StackView`:
/// - swipe LEFT  = Accept
/// - swipe RIGHT = Re-roll
/// - swipe UP/DOWN = cycle gallery candidates (single-panel only)
///
/// Per ADR-0010 long-press Re-prompt is dropped from the active surface; the
/// failed-card UI, grid jump-back, and persistent Finalize toolbar arrive in
/// Slices Q / R / P. This slice is the tracer-bullet that gates the fan-out.
struct ReviewDeckView: View {
    @Environment(\.themeKind) private var theme
    let player: PlayerRecord
    let template: ClassTemplate
    let store: PlayerStore
    let generator: any PanelGenerator
    let trialBackend: any SponsoredTrialBackend

    @State private var headIndex: Int = 0
    @State private var gallery: [PanelCandidate] = []
    @State private var cursor: GalleryCursor = .forNewHead(count: 0)
    @State private var swipeOffset: CGSize = .zero
    @State private var panel1Task: Task<Void, Never>?
    @State private var queueTask: Task<Void, Never>?
    @State private var rerollTask: Task<Void, Never>?
    @State private var triptychRerollTask: Task<Void, Never>?
    @State private var headTick: Int = 0
    @State private var budget: GenerationBudget
    @State private var startError: String?
    @State private var lastError: String?
    /// Slice R (#99): grid sheet visibility — the deck surface's only undo
    /// path. Operator opens via the toolbar grid icon, taps any cell, and the
    /// tapped unit re-pops to deck top with no confirm dialog (the slice-I
    /// dialog complex is gone; see ADR-0010 "the grid is the only undo path").
    @State private var showingGrid: Bool = false
    @State private var rerollCounter = RerollCounter()
    @State private var pendingFriction: PendingFrictionConfirm?
    /// Slice P (#97): persistent Finalize toolbar state. The button is
    /// available from t=0; tapping renders the PDF with whatever is accepted
    /// at that moment. Un-accepted panels render as empty cells per slice H's
    /// existing `PDFRenderer` path. No confirm dialog — ADR-0010 is explicit.
    @State private var pdfPreviewItem: PreviewItem?
    @State private var isRenderingPDF: Bool = false
    @State private var pdfRenderError: String?

    init(player: PlayerRecord,
         template: ClassTemplate,
         store: PlayerStore,
         generator: any PanelGenerator = FirebaseAIPanelGenerator(billingMode: BillingModeStore().current),
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
        ZStack {
            ThemedBackground()
            VStack(spacing: 16) {
                header
                deckArea
                if let lastError {
                    Text(lastError)
                        .font(theme.captionFont(12))
                        .foregroundStyle(p.danger)
                        .padding(.horizontal)
                }
                if let startError {
                    Text(startError)
                        .font(theme.captionFont(12))
                        .foregroundStyle(p.danger)
                        .padding(.horizontal)
                }
                if let pdfRenderError {
                    Text(pdfRenderError)
                        .font(theme.captionFont(12))
                        .foregroundStyle(p.danger)
                        .padding(.horizontal)
                }
                Spacer()
            }
            .padding(.vertical)
        }
        .navigationTitle(player.playerName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(p.paper, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(theme.preferredColorScheme, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { budgetChip }
            ToolbarItem(placement: .topBarLeading) { finalizeButton }
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showingGrid = true
                } label: {
                    Image(systemName: "square.grid.3x3")
                }
                .accessibilityLabel("Open panel grid")
            }
        }
        .onAppear { onFirstAppear() }
        .onDisappear {
            panel1Task?.cancel()
            queueTask?.cancel()
            rerollTask?.cancel()
            triptychRerollTask?.cancel()
        }
        .alert("Re-roll this panel again?",
               isPresented: Binding(get: { pendingFriction != nil },
                                    set: { if !$0 { pendingFriction = nil } })) {
            Button("Re-roll", role: .destructive) {
                if let pending = pendingFriction {
                    pendingFriction = nil
                    fireConfirmedReroll(pending)
                }
            }
            Button("Cancel", role: .cancel) {
                pendingFriction = nil
            }
        } message: {
            if let pending = pendingFriction {
                Text("This is re-roll #\(pending.priorCount + 1) on this card. Sure?")
            }
        }
        .sheet(isPresented: $showingGrid) {
            gridSheet
        }
        .sheet(item: $pdfPreviewItem) { item in
            PDFPreview(url: item.url)
        }
    }

    // MARK: - Slice P (#97) — persistent Finalize toolbar

    /// Always-available Finalize button. Renders the PDF against whatever is
    /// accepted right now; empty cells are handled by slice H's `PDFRenderer`
    /// (cream background + figcaption, no `<img>`). Per ADR-0010 there is no
    /// confirm dialog before render — the operator decides when done.
    private var finalizeButton: some View {
        let p = theme.palette
        return Button {
            Task { await runPDFRender() }
        } label: {
            if isRenderingPDF {
                ProgressView()
            } else {
                Image(systemName: "doc.richtext")
            }
        }
        .disabled(isRenderingPDF)
        .tint(p.accent)
        .accessibilityLabel("Finalize comic")
    }

    private func runPDFRender() async {
        pdfRenderError = nil
        isRenderingPDF = true
        defer { isRenderingPDF = false }
        do {
            let url = try await PDFRenderer.render(player: player,
                                                   template: template,
                                                   store: store)
            pdfPreviewItem = PreviewItem(url: url)
            if BillingModeStore().current == .sponsored {
                let backend = trialBackend
                let playerId = player.id
                Task { try? await backend.recordFinalized(playerId: playerId) }
            }
        } catch {
            pdfRenderError = "PDF render failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Slice R (#99) — grid sheet + cell tap → demote + pop to deck top

    private var gridSheet: some View {
        NavigationStack {
            PanelGridView(
                player: player,
                template: template,
                store: store,
                onSelect: handleGridSelect
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

    /// ADR-0010 "the grid is the only undo path". For an accepted target the
    /// PNG demotes back to `_candidates/0/`; for any non-accepted target the
    /// disk is left alone. Either way the deck head jumps to the unit owning
    /// that target and the sheet dismisses, so the operator can immediately
    /// swipe-left to re-accept, swipe-right to re-roll, or swipe-up/down to
    /// cycle candidates. Triptych sub-cells demote every accepted sub-panel
    /// in the triptych (atomic-triptych rule from slice G) so the whole card
    /// returns to candidate review.
    private func handleGridSelect(targetID: PanelTargetID) {
        guard let unitIdx = ReviewUnit.unitIndex(for: targetID, in: units) else {
            showingGrid = false
            return
        }
        let unit = units[unitIdx]
        do {
            switch unit {
            case .single(let target):
                try store.demoteAndPopToDeckTop(playerId: player.id, target: target.id)
            case .triptych(let trip):
                for id in trip.subTargetIDs {
                    try store.demoteAndPopToDeckTop(playerId: player.id, target: id)
                }
            }
        } catch {
            lastError = "Couldn't pull card back: \(error.localizedDescription)"
            showingGrid = false
            return
        }
        headIndex = unitIdx
        showingGrid = false
        refreshHead()
        refreshBudget()
    }

    // MARK: - Header + chrome

    private var header: some View {
        let p = theme.palette
        return HStack(spacing: 10) {
            Text(headerText)
                .font(theme.headingFont(18))
                .foregroundStyle(p.inkPrimary)
            Spacer()
        }
        .padding(.horizontal)
    }

    private var headerText: String {
        if isAllDone { return "Stack complete" }
        return "\(headIndex + 1) of \(units.count)"
    }

    private var budgetChip: some View {
        // Slice O (#96): at remaining==0 the chip flips to a calm "accept-only"
        // indicator instead of a red exhausted count. The soft-block itself is
        // the entire exhaustion UX — no modal, no warning shape.
        let p = theme.palette
        let text = budget.isExhausted ? "0 — accept-only" : "\(budget.remaining) / \(budget.limit)"
        return Text(text)
            .font(theme.captionFont(12))
            .foregroundStyle(budget.isExhausted ? p.inkSecondary : p.inkSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(p.surfaceRaised, in: Capsule())
    }

    // MARK: - Deck visualization

    @ViewBuilder
    private var deckArea: some View {
        if isAllDone {
            doneCard
        } else {
            ZStack {
                ForEach(visiblePeekIndices, id: \.self) { idx in
                    peekCard(at: idx)
                }
                topCard
            }
            .padding(.horizontal)
        }
    }

    /// Indices of the next 1–2 units behind the head, rendered as peeking
    /// cards. Drawn back-to-front so the closest one to the head sits in front.
    private var visiblePeekIndices: [Int] {
        let nextOne = headIndex + 1
        let nextTwo = headIndex + 2
        var out: [Int] = []
        if nextTwo < units.count { out.append(nextTwo) }
        if nextOne < units.count { out.append(nextOne) }
        return out
    }

    @ViewBuilder
    private func peekCard(at index: Int) -> some View {
        let depth = index - headIndex
        // depth=1 → just behind head; depth=2 → two cards behind.
        let scale = depth == 1 ? 0.94 : 0.88
        let yOffset: CGFloat = depth == 1 ? 18 : 36
        let opacity = depth == 1 ? 0.92 : 0.78
        unitCard(for: units[index], isTop: false)
            .scaleEffect(scale)
            .offset(y: yOffset)
            .opacity(opacity)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private var topCard: some View {
        unitCard(for: units[headIndex], isTop: true)
            .offset(swipeOffset)
            .rotationEffect(.degrees(Double(swipeOffset.width / 20)))
            .overlay(alignment: .topLeading) { acceptBadge }
            .overlay(alignment: .topTrailing) { rerollBadge }
            .gesture(topCardGesture)
            .id(headTick)
    }

    /// Either a single-panel placeholder/filled card or a composed triptych
    /// card. Slot states reflect on-disk candidate presence. For the top card
    /// we honour the operator's cursor (gallery cycling); peeking cards always
    /// show the newest candidate.
    @ViewBuilder
    private func unitCard(for unit: ReviewUnit, isTop: Bool) -> some View {
        switch unit {
        case .single(let target):
            let slot = slotState(for: target, isTop: isTop)
            switch target {
            case .panel(_, let spec):
                PlaceholderPanelCard(spec: spec,
                                     playerName: player.playerName,
                                     slot: slot)
            case .cover:
                CoverDeckCard(spec: target.coverSpec,
                              playerName: player.playerName,
                              characterName: player.characterName,
                              className: template.name,
                              slot: slot)
            }
        case .triptych(let trip):
            PlaceholderTriptychCard(kind: trip.kind,
                                    slots: trip.subTargets.map { sub in
                                        slotState(for: sub, isTop: isTop)
                                    })
        }
    }

    /// Newest candidate (or accepted PNG) → `.filled`. Empty → `.spinning`.
    /// The top card may override with the cursor-selected candidate index so
    /// swipe-up/down cycling works.
    private func slotState(for target: PanelTarget, isTop: Bool) -> PlaceholderSlotState {
        // Accepted artifact wins (operator may have re-entered the deck after
        // accepting in a prior session — unlikely now that the deck mounts
        // everything from t=0, but cheap to honour).
        if let bytes = store.loadPanel(playerId: player.id, target: target.id),
           let img = UIImage(data: bytes) {
            return .filled(img)
        }
        let candidates = store.listCandidates(playerId: player.id, target: target.id)
        if isTop, isHeadSingle(target: target),
           !gallery.isEmpty, cursor.index < gallery.count,
           let img = loadImage(gallery[cursor.index].url) {
            return .filled(img)
        }
        if let newest = candidates.max(by: { $0.index < $1.index }),
           let img = loadImage(newest.url) {
            return .filled(img)
        }
        return .spinning
    }

    private func isHeadSingle(target: PanelTarget) -> Bool {
        if case .single(let head) = units[headIndex], head.id == target.id { return true }
        return false
    }

    // MARK: - Gesture

    private var topCardGesture: some Gesture {
        DragGesture()
            .onChanged { swipeOffset = $0.translation }
            .onEnded { value in
                let t = value.translation
                let absX = abs(t.width)
                let absY = abs(t.height)
                if absX > absY {
                    // Inverted vocabulary per ADR-0010: LEFT=Accept, RIGHT=Re-roll.
                    if t.width < -120 {
                        commitAcceptTop()
                    } else if t.width > 120 {
                        commitRerollTop()
                    } else {
                        withAnimation(.spring) { swipeOffset = .zero }
                    }
                } else {
                    if case .single = units[headIndex] {
                        if t.height < -80 {
                            cycleGallery(forward: true)
                        } else if t.height > 80 {
                            cycleGallery(forward: false)
                        }
                    }
                    withAnimation(.spring) { swipeOffset = .zero }
                }
            }
    }

    @ViewBuilder
    private var acceptBadge: some View {
        let p = theme.palette
        if swipeOffset.width < -40 {
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
        // Slice O (#96): at exhaustion the swipe-right is a soft bounce — no
        // alarmist "OUT OF BUDGET" overlay. The dim accent communicates "this
        // gesture won't fire" without escalating the surface.
        let p = theme.palette
        if swipeOffset.width > 40 {
            Text(rerollBadgeText)
                .font(theme.headingFont(20))
                .foregroundStyle(budget.isExhausted ? p.inkSecondary.opacity(0.5) : p.accent)
                .padding(8)
                .background(p.paper, in: RoundedRectangle(cornerRadius: 8))
                .padding(24)
        }
    }

    private var rerollBadgeText: String {
        if case .triptych = units[headIndex] { return "RE-ROLL ×3" }
        return "RE-ROLL"
    }

    // MARK: - Lifecycle

    private func onFirstAppear() {
        refreshHead()
        Task { await spendSponsoredTrialIfFirstMount() }
        startPanel1IfNeeded()
        startQueueIfPanel1HasCandidate()
    }

    /// ADR-0010: sponsored-trial spend fires at first deck mount per player,
    /// idempotent across launches via `.deck_mounted`. Mirrors the call
    /// previously made from `StartCampaignView`.
    private func spendSponsoredTrialIfFirstMount() async {
        guard BillingModeStore().current == .sponsored else { return }
        if store.hasDeckBeenMounted(playerId: player.id) { return }
        do {
            try await trialBackend.spend(playerId: player.id)
            try? store.markDeckMounted(playerId: player.id)
        } catch {
            await MainActor.run {
                startError = "Couldn't record sponsored trial spend: \(error.localizedDescription)"
            }
        }
    }

    /// Panel 1 generates sequentially before the fan-out. Skips if a candidate
    /// is already on disk (re-entry after the operator backed out before
    /// accepting).
    private func startPanel1IfNeeded() {
        guard panel1Task == nil else { return }
        guard let panel1Spec = template.panels.first(where: { $0.n == 1 }) else { return }
        let target: PanelTarget = .panel(n: 1, spec: panel1Spec)
        if store.hasPanel(playerId: player.id, target: target.id) { return }
        if !store.listCandidates(playerId: player.id, target: target.id).isEmpty { return }
        let playerId = player.id
        let template = template
        let store = store
        let generator = generator
        panel1Task = Task {
            defer { Task { @MainActor in panel1Task = nil } }
            do {
                try await Phase2StackView.runOneAppendingCandidate(target: target,
                                                                   playerId: playerId,
                                                                   template: template,
                                                                   store: store,
                                                                   generator: generator)
                await MainActor.run {
                    refreshHead()
                    refreshBudget()
                    startQueueIfPanel1HasCandidate()
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run {
                    lastError = "Panel 1 didn't generate. Pull down to retry."
                    refreshBudget()
                }
            }
        }
    }

    /// Fan-out trigger: once panel 1 has any candidate (accepted or pending),
    /// enqueue panels 2–15 + cover. Idempotent: we only spawn one queue worker.
    private func startQueueIfPanel1HasCandidate() {
        guard queueTask == nil else { return }
        guard let panel1Spec = template.panels.first(where: { $0.n == 1 }) else { return }
        let target1: PanelTarget = .panel(n: 1, spec: panel1Spec)
        let hasPanel1Artifact = store.hasPanel(playerId: player.id, target: target1.id)
            || !store.listCandidates(playerId: player.id, target: target1.id).isEmpty
        guard hasPanel1Artifact else { return }
        let targetsSnapshot = fanOutTargets
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
                try await Phase2StackView.runOne(target: target,
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
                        case .completed:
                            headTick &+= 1
                            refreshHead()
                            refreshBudget()
                        case .throttled:
                            refreshBudget()
                        case .failed(let id, let message):
                            // Camp Comics invariant: terminal failures don't
                            // penalize the operator. Log + tick; Slice Q will
                            // surface the stuck-card UX.
                            NSLog("Camp Comics: terminal panel failure — id=%@ msg=%@",
                                  String(describing: id), message)
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

    // MARK: - Gesture commits

    private func commitAcceptTop() {
        switch units[headIndex] {
        case .single(let target): commitAcceptSingle(target: target)
        case .triptych(let trip): commitAcceptTriptych(trip: trip)
        }
    }

    private func commitAcceptSingle(target: PanelTarget) {
        // Race: queue/operator both completed — already-accepted heads advance
        // without re-accepting.
        if !store.hasPanel(playerId: player.id, target: target.id) {
            guard let visible else {
                withAnimation(.spring) { swipeOffset = .zero }
                return
            }
            do {
                try store.acceptCandidate(playerId: player.id,
                                          target: target.id,
                                          candidateIndex: visible.index)
            } catch {
                lastError = "Accept failed: \(error.localizedDescription)"
                withAnimation(.spring) { swipeOffset = .zero }
                return
            }
        }
        withAnimation(.easeOut(duration: 0.2)) {
            swipeOffset = CGSize(width: -600, height: 0)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            swipeOffset = .zero
            headIndex += 1
            refreshHead()
            refreshBudget()
        }
    }

    private func commitAcceptTriptych(trip: PanelTriptych) {
        if !trip.allSubPanelsAccepted(playerId: player.id, store: store) {
            var choices: [PanelTargetID: Int] = [:]
            for id in trip.subTargetIDs {
                let candidates = store.listCandidates(playerId: player.id, target: id)
                guard let newest = candidates.max(by: { $0.index < $1.index }) else {
                    withAnimation(.spring) { swipeOffset = .zero }
                    return
                }
                choices[id] = newest.index
            }
            do {
                try trip.acceptAtomically(playerId: player.id, store: store, choices: choices)
            } catch {
                lastError = "Accept failed: \(error.localizedDescription)"
                withAnimation(.spring) { swipeOffset = .zero }
                return
            }
        }
        withAnimation(.easeOut(duration: 0.2)) {
            swipeOffset = CGSize(width: -600, height: 0)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            swipeOffset = .zero
            headIndex += 1
            refreshHead()
            refreshBudget()
        }
    }

    private func commitRerollTop() {
        switch units[headIndex] {
        case .single(let target): commitRerollSingle(target: target)
        case .triptych(let trip): commitRerollTriptych(trip: trip)
        }
    }

    private func commitRerollSingle(target: PanelTarget) {
        let unit = units[headIndex]
        let key = unit.frictionKey
        let prior = rerollCounter.count(unitId: key)
        switch RerollDecider.decide(remaining: budget.remaining,
                                    cost: 1,
                                    priorRerolls: prior) {
        case .bounce:
            softBounce()
            return
        case .requireConfirm:
            withAnimation(.spring) { swipeOffset = .zero }
            pendingFriction = .single(target: target, priorCount: prior)
            return
        case .fire:
            break
        }
        guard rerollTask == nil else {
            withAnimation(.spring) { swipeOffset = .zero }
            return
        }
        rerollCounter.increment(unitId: key)
        performRerollSingle(target: target)
    }

    private func performRerollSingle(target: PanelTarget) {
        let playerId = player.id
        let template = template
        let store = store
        let generator = generator
        withAnimation(.easeOut(duration: 0.2)) {
            swipeOffset = CGSize(width: 600, height: 0)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            swipeOffset = .zero
            headTick &+= 1
        }
        rerollTask = Task {
            defer { Task { @MainActor in rerollTask = nil } }
            do {
                try await Phase2StackView.runOneAppendingCandidate(target: target,
                                                                   playerId: playerId,
                                                                   template: template,
                                                                   store: store,
                                                                   generator: generator)
                await MainActor.run { refreshHead(); refreshBudget() }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run {
                    lastError = "Re-roll failed: \(error.localizedDescription)"
                    refreshHead()
                    refreshBudget()
                }
            }
        }
    }

    private func commitRerollTriptych(trip: PanelTriptych) {
        let key = ReviewUnit.triptych(trip).frictionKey
        let prior = rerollCounter.count(unitId: key)
        switch RerollDecider.decide(remaining: budget.remaining,
                                    cost: PanelTriptych.budgetCost,
                                    priorRerolls: prior) {
        case .bounce:
            softBounce()
            return
        case .requireConfirm:
            withAnimation(.spring) { swipeOffset = .zero }
            pendingFriction = .triptych(trip: trip, priorCount: prior)
            return
        case .fire:
            break
        }
        guard triptychRerollTask == nil, rerollTask == nil else {
            withAnimation(.spring) { swipeOffset = .zero }
            return
        }
        rerollCounter.increment(unitId: key)
        performRerollTriptych(trip: trip)
    }

    private func performRerollTriptych(trip: PanelTriptych) {
        withAnimation(.easeOut(duration: 0.2)) {
            swipeOffset = CGSize(width: 600, height: 0)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            swipeOffset = .zero
            headTick &+= 1
        }
        let playerId = player.id
        let template = template
        let store = store
        let generator = generator
        triptychRerollTask = Task {
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
                            try await Phase2StackView.runOneAppendingCandidate(target: sub,
                                                                               playerId: playerId,
                                                                               template: template,
                                                                               store: store,
                                                                               generator: generator)
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
                        lastError = "Re-roll failed: \(String(describing: firstError))"
                    }
                }
            }
        }
    }

    private func cycleGallery(forward: Bool) {
        guard gallery.count > 1 else { return }
        cursor = forward ? cursor.advanced() : cursor.retreated()
        headTick &+= 1
    }

    // MARK: - Head + budget refresh

    private func refreshHead() {
        while headIndex < units.count, isUnitFullyAccepted(units[headIndex]) {
            headIndex += 1
        }
        if isAllDone {
            gallery = []
            cursor = .forNewHead(count: 0)
            return
        }
        switch units[headIndex] {
        case .single(let head):
            let newGallery = store.listCandidates(playerId: player.id, target: head.id)
            let wasEmpty = gallery.isEmpty
            let grew = newGallery.count > gallery.count
            gallery = newGallery
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

    private func refreshBudget() {
        budget = store.generationBudget(playerId: player.id,
                                        panelCount: template.panels.count)
    }

    // MARK: - Done state

    /// Slice P (#97): quiet empty-deck state. ADR-0010 "The Finalize button is
    /// persistent": no celebratory modal, no auto-finalize. The toolbar
    /// Finalize button remains the action — this message just points there.
    private var doneCard: some View {
        let p = theme.palette
        return ThemedCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(ReviewUnit.emptyDeckQuietMessage)
                    .font(theme.bodyFont(14))
                    .foregroundStyle(p.inkSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal)
    }

    // Slice O (#96): bounce a swipe-right when budget can't cover the re-roll.
    // No modal — the snap-back animation + light haptic IS the new exhaustion
    // UX. The chip's "0 — accept-only" text carries the explanation.
    private func softBounce() {
        withAnimation(.spring) { swipeOffset = .zero }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // Friction confirm landed and the operator chose to proceed. Spends budget
    // by way of the regular re-roll path.
    private func fireConfirmedReroll(_ pending: PendingFrictionConfirm) {
        switch pending {
        case .single(let target, _):
            rerollCounter.increment(unitId: ReviewUnit.single(target).frictionKey)
            performRerollSingle(target: target)
        case .triptych(let trip, _):
            rerollCounter.increment(unitId: ReviewUnit.triptych(trip).frictionKey)
            performRerollTriptych(trip: trip)
        }
    }

    // MARK: - Derived

    private var units: [ReviewUnit] {
        ReviewUnit.deckUnits(from: template)
    }

    /// Targets to fan out *after* panel 1 lands: panels 2..N + cover. Mirrors
    /// `Phase2StackView.targets` so the queue stays story-ordered.
    private var fanOutTargets: [PanelTarget] {
        var out: [PanelTarget] = template.panels
            .filter { $0.n != 1 }
            .sorted { $0.n < $1.n }
            .map { .panel(n: $0.n, spec: $0) }
        out.append(.cover(spec: template.cover))
        return out
    }

    private var visible: PanelCandidate? {
        guard !gallery.isEmpty, cursor.index < gallery.count else { return nil }
        return gallery[cursor.index]
    }

    private var isAllDone: Bool { headIndex >= units.count }

    private func loadImage(_ url: URL) -> UIImage? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }
}

// MARK: - Friction confirm payload

/// Slice O (#96): a re-roll that hit the per-card friction threshold and is
/// waiting on the operator's confirm. Carries the prior count purely for the
/// alert's message text — the decider has already authorized it.
private enum PendingFrictionConfirm: Equatable {
    case single(target: PanelTarget, priorCount: Int)
    case triptych(trip: PanelTriptych, priorCount: Int)

    var priorCount: Int {
        switch self {
        case .single(_, let n), .triptych(_, let n): return n
        }
    }
}

// MARK: - PanelTarget helper (cover spec extraction)

private extension PanelTarget {
    var coverSpec: CoverSpec {
        if case .cover(let spec) = self { return spec }
        // Defensive default; only called from a `.cover` switch arm.
        return CoverSpec(emotion: .neutral, position: .front, poseDirective: "")
    }
}

// MARK: - Cover deck card

/// Cover variant of the placeholder card. Same frame and caption-area layout
/// as `PlaceholderPanelCard` but uses the YAML cover beat (or a stand-in)
/// instead of `spec.beat` substitution. Kept inline because the cover only
/// renders here; if a second caller surfaces, lift it.
private struct CoverDeckCard: View {
    @Environment(\.themeKind) private var theme
    let spec: CoverSpec
    let playerName: String
    let characterName: String
    let className: String
    let slot: PlaceholderSlotState

    var body: some View {
        let p = theme.palette
        VStack(spacing: 10) {
            imageArea
                .background(p.surfaceRaised)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(p.inkPrimary.opacity(0.4), lineWidth: 1)
                )
            captionText
        }
    }

    @ViewBuilder
    private var imageArea: some View {
        switch slot {
        case .filled(let image):
            Image(uiImage: image).resizable().scaledToFit()
        case .spinning:
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay(ProgressView())
        case .stuck(let image):
            ZStack {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .saturation(0)
                        .opacity(0.55)
                } else {
                    Color.clear.aspectRatio(1, contentMode: .fit)
                }
            }
        }
    }

    private var captionText: some View {
        let p = theme.palette
        let label = characterName.isEmpty
            ? "Cover — \(playerName) the \(className)"
            : "Cover — \(characterName) (\(playerName)), \(className)"
        return Text(label)
            .font(theme.captionFont(13))
            .foregroundStyle(p.inkSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 6)
    }
}

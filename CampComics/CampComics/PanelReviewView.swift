import SwiftUI
import UIKit
import CampComicsCore

/// The slice-9/11b review surface. Drives one target at a time — panels 1..12
/// and the cover sibling — and auto-advances the cursor to the next unfinished
/// slot on Accept. Renders the candidate gallery as a filmstrip, exposes
/// Generate / Accept / Re-roll / Cancel, and shows the out-of-order chip when
/// an earlier panel hasn't been accepted (cover never flags out-of-order).
struct PanelReviewView: View {
    let player: PlayerRecord
    let template: ClassTemplate
    let store: PlayerStore
    let generator: any PanelGenerator

    @State private var currentTarget: PanelTarget
    @State private var review: PanelReviewState
    @State private var candidates: [PanelCandidate] = []
    @State private var selectedCandidate: PanelCandidate?
    @State private var pendingTask: Task<Void, Never>?
    @State private var lastPrompt: String = ""
    @State private var lastReferences: [ReferenceSlot] = []
    @State private var lastError: String?
    @State private var showPromptDetail: Bool = false
    @State private var throttleCountdown: Int = 0
    @State private var throttleTask: Task<Void, Never>?
    @State private var showingMissingPhotoCapture: Bool = false
    @State private var showingGrid: Bool = false
    @State private var showingReprompt: Bool = false

    /// Fallback wait when Vertex 429s without a parseable retry-after.
    private static let defaultRetryAfterSeconds: TimeInterval = 6

    init(player: PlayerRecord,
         template: ClassTemplate,
         store: PlayerStore,
         generator: any PanelGenerator = FirebaseAIPanelGenerator(),
         startAt: PanelTarget) {
        self.player = player
        self.template = template
        self.store = store
        self.generator = generator
        _currentTarget = State(initialValue: startAt)
        _review = State(initialValue: PanelReviewState.hydrate(playerId: player.id,
                                                               target: startAt.id,
                                                               store: store))
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
        .navigationTitle(headerTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reloadCurrentTarget)
        .onDisappear {
            pendingTask?.cancel()
            throttleTask?.cancel()
        }
        .fullScreenCover(isPresented: $showingMissingPhotoCapture) {
            MissingPhotoCaptureView(
                requirement: currentRequirement,
                onSaved: { jpegData in
                    try? store.savePhoto(playerId: player.id,
                                         requirement: currentRequirement,
                                         jpegData: jpegData)
                    showingMissingPhotoCapture = false
                    review.markUnstarted()
                    startGenerate()
                },
                onCancel: { showingMissingPhotoCapture = false }
            )
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingGrid = true
                } label: {
                    Image(systemName: "square.grid.3x3")
                }
                .accessibilityLabel("Open panel grid")
            }
        }
        .sheet(isPresented: $showingReprompt) {
            RepromptSheet(prefill: repromptPrefill,
                          aspect: currentAspect,
                          onSubmit: { edited in
                              showingReprompt = false
                              submitReprompt(edited)
                          },
                          onCancel: { showingReprompt = false })
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingGrid) {
            NavigationStack {
                PanelGridView(player: player,
                              template: template,
                              store: store) { tappedID in
                    if let next = allTargets.first(where: { $0.id == tappedID }) {
                        currentTarget = next
                    }
                    showingGrid = false
                    afterNav()
                }
                .navigationTitle("Grid")
                .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private var allFinalized: Bool {
        allTargets.allSatisfy { store.hasPanel(playerId: player.id, target: $0.id) }
    }

    private var allDoneBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("All 13 artifacts reviewed").font(.headline)
            Text("Tap ‹ back to return to the player.")
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
            if !currentBeat.isEmpty {
                Text(currentBeat)
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
        let plan = PhotoReferenceResolver.references(for: currentTarget,
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
           let data = store.loadPanel(playerId: player.id, target: currentTarget.id),
           let image = UIImage(data: data) {
            ZoomableImage(image: image)
                .aspectRatio(image.size, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
        } else if case .throttled(let autoRetryPending) = review.phase {
            placeholder(autoRetryPending
                        ? "Throttled — Vertex per-minute quota hit. Auto-retrying in \(throttleCountdown)s…"
                        : "Throttled — auto-retry didn't clear it. Tap Retry when ready.")
        } else if case .missingPhoto = review.phase {
            placeholder("Missing reference photo: \(PromptCopyBook.copy(for: currentRequirement).title). Tap Capture this photo below.")
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
        case .unstarted:
            Button("Generate") { startGenerate() }
                .buttonStyle(.borderedProminent)
        case .missingPhoto:
            let copy = PromptCopyBook.copy(for: currentRequirement)
            VStack(alignment: .leading, spacing: 6) {
                Text("⚠️ Missing reference photo: \(copy.title)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.orange)
                Text(copy.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Capture this photo") { showingMissingPhotoCapture = true }
                    .buttonStyle(.borderedProminent)
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
                Button("Re-prompt") { showingReprompt = true }
                    .buttonStyle(.bordered)
            }
        case .accepted:
            Button("Re-roll") { rerollAccepted() }
                .buttonStyle(.bordered)
        case .throttled(let autoRetryPending):
            if autoRetryPending {
                HStack {
                    Text("Auto-retrying in \(throttleCountdown)s…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel") {
                        throttleTask?.cancel()
                        throttleCountdown = 0
                        review.cancelGeneration()
                    }
                    .buttonStyle(.bordered)
                    .tint(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Auto-retry didn't clear the throttle. Tap Retry when ready.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Retry") { startGenerate() }
                        .buttonStyle(.borderedProminent)
                }
            }
        case .failed(let msg):
            VStack(alignment: .leading, spacing: 6) {
                Text(msg).font(.footnote).foregroundStyle(.red)
                Button("Retry") { startGenerate() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    /// Always-visible navigation row so the operator can step through every
    /// target (panels 1..12 + cover) regardless of slot phase. Hidden while a
    /// generation is in flight.
    @ViewBuilder
    private var navRow: some View {
        if case .generating = review.phase {
            EmptyView()
        } else {
            HStack {
                Button("Previous") { goPrev() }
                    .disabled(currentIndex <= 0)
                Spacer()
                Button("Next") { goNext() }
                    .disabled(currentIndex >= allTargets.count - 1)
            }
            .buttonStyle(.bordered)
        }
    }

    /// Expandable diagnostic block — confirms exactly what prompt + reference
    /// slots were sent on the most recent generation for this target. Lets the
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
                Text(targetDiagnostic)
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

    /// Slice-9/11b diagnostic: surface raw target context so we can tell whether
    /// a surprising chip summary is a loader bug, a resolver bug, or wrong-
    /// target navigation.
    private var targetDiagnostic: String {
        switch currentTarget {
        case .panel(let n, let spec):
            let ref = spec.referencePanel.map(String.init) ?? "nil"
            let cost = spec.costumeOverride.map { "yes (\($0.prefix(40))…)" } ?? "no"
            let style = spec.styleOverride.map { "yes (\($0.prefix(40))…)" } ?? "no"
            return "panel \(n) · referencePanel = \(ref) · costume_override = \(cost) · style_override = \(style)"
        case .cover(let spec):
            return "cover · pose = \(spec.poseDirective.prefix(60))… · aspect = \(spec.aspect)"
        }
    }

    // MARK: - Actions

    private func startGenerate(autoRetry: Bool = false, promptOverride: String? = nil) {
        lastError = nil
        throttleTask?.cancel()
        throttleCountdown = 0
        let target = currentTarget
        guard let photoData = store.loadPhoto(playerId: player.id,
                                              requirement: currentRequirement) else {
            review.markMissingPhoto()
            return
        }
        let plan = PhotoReferenceResolver.references(for: target,
                                                     playerId: player.id,
                                                     store: store)
        guard let references = materialize(plan: plan, photoData: photoData) else {
            lastError = "Couldn't load all reference images for this target."
            return
        }
        let prompt = promptOverride ?? PromptBuilder.buildPrompt(
            for: target,
            template: template,
            tokens: ["camper_name": player.playerName]
        )
        lastPrompt = prompt
        lastReferences = plan.slots
        if autoRetry {
            review.autoRetry()
        } else {
            review.startGeneration()
        }

        pendingTask = Task {
            do {
                let pngData = try await generator.generatePanel(prompt: prompt,
                                                                references: references)
                if Task.isCancelled { return }
                let saved = try store.savePendingCandidate(playerId: player.id,
                                                           target: target.id,
                                                           pngData: pngData)
                appendAttempt(prompt: prompt, candidate: saved)
                await MainActor.run {
                    candidates = store.listCandidates(playerId: player.id, target: target.id)
                    selectedCandidate = saved
                    review.candidateReceived()
                }
            } catch is CancellationError {
                // Cancel path: cancelGenerate() already moved state.
            } catch PanelGeneratorError.throttled(let retryAfter) {
                await MainActor.run { handleThrottled(retryAfter: retryAfter) }
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
        throttleTask?.cancel()
        throttleCountdown = 0
        review.cancelGeneration()
    }

    /// Vertex 429 handler. Drives the SM into `.throttled`; if the state machine
    /// grants the one-shot auto-retry budget (pending=true), schedules a
    /// countdown task that fires `startGenerate(autoRetry: true)` when it
    /// elapses. The second 429 in the same cycle holds at pending=false and
    /// waits for an operator Retry tap (per ADR-0003 / design memo #14).
    private func handleThrottled(retryAfter: TimeInterval?) {
        review.markThrottled()
        guard case .throttled(autoRetryPending: true) = review.phase else {
            throttleCountdown = 0
            return
        }
        let wait = retryAfter ?? Self.defaultRetryAfterSeconds
        throttleCountdown = max(Int(wait.rounded(.up)), 1)
        throttleTask?.cancel()
        throttleTask = Task { @MainActor in
            while throttleCountdown > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                throttleCountdown -= 1
            }
            if Task.isCancelled { return }
            startGenerate(autoRetry: true)
        }
    }

    private func commitAccept() {
        guard let candidate = selectedCandidate else { return }
        do {
            try store.acceptCandidate(playerId: player.id,
                                      target: currentTarget.id,
                                      candidateIndex: candidate.index)
            advance()
        } catch {
            lastError = String(describing: error)
        }
    }

    /// After Accept, jump to the next unfinished target (auto-advance per
    /// design memo #5). If everything is finalized, just refresh in place
    /// so the filmstrip clears and the accepted image displays correctly.
    private func advance() {
        if let next = nextUnfinished(skipping: currentTarget) {
            currentTarget = next
        }
        reloadCurrentTarget()
    }

    private func goPrev() {
        let idx = currentIndex - 1
        guard idx >= 0 else { return }
        currentTarget = allTargets[idx]
        afterNav()
    }

    private func goNext() {
        let idx = currentIndex + 1
        guard idx < allTargets.count else { return }
        currentTarget = allTargets[idx]
        afterNav()
    }

    private func afterNav() {
        throttleTask?.cancel()
        throttleCountdown = 0
        reloadCurrentTarget()
    }

    /// Re-roll-after-accept (design memo #3): demote the prior accepted image
    /// back into the candidate gallery so it's still visible while a new
    /// candidate is generated. Operator can Accept either one when reviewing.
    private func rerollAccepted() {
        do {
            try store.demoteAcceptedToCandidate(playerId: player.id, target: currentTarget.id)
            review = PanelReviewState(phase: .reviewing)
            candidates = store.listCandidates(playerId: player.id, target: currentTarget.id)
            selectedCandidate = candidates.first
            startGenerate()
        } catch {
            lastError = String(describing: error)
        }
    }

    private func reloadCurrentTarget() {
        review = PanelReviewState.hydrate(playerId: player.id, target: currentTarget.id, store: store)
        candidates = store.listCandidates(playerId: player.id, target: currentTarget.id)
        selectedCandidate = candidates.last
        lastError = nil
        lastPrompt = store.attemptsState(playerId: player.id)
            .last(where: { $0.target == currentTarget.id })?
            .prompt ?? ""
        let plan = PhotoReferenceResolver.references(for: currentTarget,
                                                     playerId: player.id,
                                                     store: store)
        lastReferences = plan.slots
        showPromptDetail = false
    }

    // MARK: - Helpers

    /// Ordered review surface: panels 1..N followed by the cover sibling.
    /// CONTEXT.md / project spec #11b: cover is the last slot and labelled
    /// "Cover" (not "13 of 13").
    private var allTargets: [PanelTarget] {
        var out: [PanelTarget] = template.panels.map { .panel(n: $0.n, spec: $0) }
        out.append(.cover(spec: template.cover))
        return out
    }

    private var currentIndex: Int {
        allTargets.firstIndex(where: { $0.id == currentTarget.id }) ?? 0
    }

    private var currentRequirement: PanelRequirement { currentTarget.requirement }

    private var currentAspect: String {
        switch currentTarget {
        case .panel(let n, _): return PromptBuilder.panelAspectRatios[n] ?? "4:3"
        case .cover(let spec): return spec.aspect
        }
    }

    /// Prefill for the Re-prompt textarea: always the freshly-built preamble.
    /// We deliberately ignore the persisted `lastPrompt` here so that template
    /// edits and new layout hints (e.g. slice 30a's diagonal-pair composition
    /// pressure) reach the model on the next regen. Tradeoff acknowledged in
    /// issue #35: per-panel manual edits don't survive re-opening Re-prompt.
    private var repromptPrefill: String {
        PromptBuilder.buildPreamble(
            for: currentTarget,
            template: template,
            tokens: ["camper_name": player.playerName]
        )
    }

    private func submitReprompt(_ editedPreamble: String) {
        let assembled = editedPreamble
            + " Style: \(PromptBuilder.styleSuffix)"
            + " Image aspect ratio: \(currentAspect)."
        startGenerate(promptOverride: assembled)
    }

    private var currentBeat: String {
        switch currentTarget {
        case .panel(_, let spec): return spec.beat
        case .cover: return "Cover — hero portrait"
        }
    }

    private var headerTitle: String {
        switch currentTarget {
        case .panel(let n, _): return "Panel \(n) of \(allTargets.count)"
        case .cover: return "Cover"
        }
    }

    private var stateLabel: String {
        switch review.phase {
        case .unstarted: return "Unstarted"
        case .generating: return "Generating…"
        case .reviewing:
            let idx = (selectedCandidate?.index ?? -1) + 1
            return "Candidate \(idx) of \(candidates.count) · Reviewing"
        case .accepted: return "Accepted"
        case .throttled(let autoRetryPending):
            return autoRetryPending ? "Throttled — auto-retry in \(throttleCountdown)s" : "Throttled — manual retry needed"
        case .failed: return "Failed"
        case .missingPhoto: return "Missing reference photo"
        }
    }

    /// "Next" = first unfinished target in `allTargets` whose id differs from
    /// `skipping`. Wraps back to earlier slots if the operator jumped ahead,
    /// so out-of-order acceptance still converges on all 13 artifacts.
    private func nextUnfinished(skipping target: PanelTarget) -> PanelTarget? {
        for candidate in allTargets where candidate.id != target.id {
            if !store.hasPanel(playerId: player.id, target: candidate.id) {
                return candidate
            }
        }
        return nil
    }

    private func materialize(plan: ReferencePlan, photoData: Data) -> [ImageReference]? {
        var refs: [ImageReference] = []
        for slot in plan.slots {
            switch slot {
            case .photo:
                refs.append(ImageReference(data: photoData, mimeType: "image/jpeg"))
            case .hero:
                let hero = BundledTemplates.heroCardData(forClassKey: template.classKey)
                refs.append(ImageReference(data: hero, mimeType: "image/png"))
            case .panel(let m):
                guard let data = store.loadPanel(playerId: player.id, target: .panel(m)) else { return nil }
                refs.append(ImageReference(data: data, mimeType: "image/png"))
            }
        }
        return refs
    }

    private func appendAttempt(prompt: String, candidate: PanelCandidate) {
        var existing = store.attemptsState(playerId: player.id)
        existing.append(PanelAttempt(target: currentTarget.id,
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

/// Scoped deep-link capture surface for a single missing reference photo.
/// Lighter than `CaptureFlowView`: no checklist, no QA-gate submit, just
/// camera → review → save for one `(emotion, position)`. Reached from the
/// `.missingPhoto` action row in `PanelReviewView`; on confirm the parent
/// hydrates back to `.unstarted` and auto-fires generation.
private struct MissingPhotoCaptureView: View {
    let requirement: PanelRequirement
    let onSaved: (Data) -> Void
    let onCancel: () -> Void

    @State private var captured: UIImage?
    @State private var showingPicker: Bool = true

    var body: some View {
        let copy = PromptCopyBook.copy(for: requirement)
        NavigationStack {
            VStack(spacing: 20) {
                if let captured {
                    Image(uiImage: captured)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 320)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    VStack(spacing: 4) {
                        Text(copy.title).font(.title2.weight(.semibold))
                        Text(copy.subtitle).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)
                    HStack(spacing: 12) {
                        Button("Retake", role: .destructive) {
                            self.captured = nil
                            showingPicker = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        Button("Looks good") {
                            if let data = captured.jpegData(compressionQuality: 0.9) {
                                onSaved(data)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                } else {
                    Spacer()
                    VStack(spacing: 12) {
                        Text(copy.emoji).font(.system(size: 96))
                        Text(copy.title).font(.title2.weight(.semibold))
                        Text(copy.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Open camera") { showingPicker = true }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .padding(.top, 8)
                    }
                    Spacer()
                }
            }
            .padding()
            .navigationTitle("Missing reference photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
            .fullScreenCover(isPresented: $showingPicker) {
                ImagePicker(sourceType: ImagePicker.preferredSourceType) { image in
                    captured = image
                    showingPicker = false
                }
                .ignoresSafeArea()
            }
        }
    }
}

/// Slice-11c Re-prompt editor. Edits the preamble (scene/composition/costume/
/// lighting); STYLE_SUFFIX + aspect are locked per
/// `feedback_style_override_face_fidelity` — appending anything after
/// STYLE_SUFFIX without reiterating face-fidelity instructions softens the
/// model's identity lock. Submit assembles `editedPreamble + " Style: " +
/// styleSuffix + " Image aspect ratio: \(aspect)."` and kicks generation;
/// the new candidate appends to the gallery without dropping priors.
private struct RepromptSheet: View {
    let prefill: String
    let aspect: String
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    @State private var edited: String

    init(prefill: String,
         aspect: String,
         onSubmit: @escaping (String) -> Void,
         onCancel: @escaping () -> Void) {
        self.prefill = prefill
        self.aspect = aspect
        self.onSubmit = onSubmit
        self.onCancel = onCancel
        _edited = State(initialValue: prefill)
    }

    private var trimmedIsEmpty: Bool {
        edited.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                TextEditor(text: $edited)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color(.secondarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .frame(minHeight: 200)
                Text("+ Style: (locked) · Image aspect ratio: \(aspect)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
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
                    Button("Submit") { onSubmit(edited) }
                        .disabled(trimmedIsEmpty)
                }
            }
        }
    }
}

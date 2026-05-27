import SwiftUI
import UIKit
import CampComicsCore

/// The slice-9 review surface. Drives one panel at a time and auto-advances
/// the cursor to the next unfinished slot on Accept. Renders the candidate
/// gallery as a filmstrip, exposes Generate / Accept / Re-roll / Cancel, and
/// shows the out-of-order chip when an earlier panel hasn't been accepted.
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
    @State private var throttleCountdown: Int = 0
    @State private var throttleTask: Task<Void, Never>?
    @State private var showingMissingPhotoCapture: Bool = false

    /// Fallback wait when Vertex 429s without a parseable retry-after.
    private static let defaultRetryAfterSeconds: TimeInterval = 6

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
        .onDisappear {
            pendingTask?.cancel()
            throttleTask?.cancel()
        }
        .fullScreenCover(isPresented: $showingMissingPhotoCapture) {
            MissingPhotoCaptureView(
                requirement: currentSpec.requirement,
                onSaved: { jpegData in
                    try? store.savePhoto(playerId: player.id,
                                         requirement: currentSpec.requirement,
                                         jpegData: jpegData)
                    showingMissingPhotoCapture = false
                    review.markUnstarted()
                    startGenerate()
                },
                onCancel: { showingMissingPhotoCapture = false }
            )
        }
    }

    private var allFinalized: Bool {
        (1...12).allSatisfy { store.hasPanel(playerId: player.id, n: $0) }
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
            placeholder("Missing reference photo: \(PromptCopyBook.copy(for: currentSpec.requirement).title). Tap Capture this photo below.")
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
            let copy = PromptCopyBook.copy(for: currentSpec.requirement)
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

    private func startGenerate(autoRetry: Bool = false) {
        lastError = nil
        throttleTask?.cancel()
        throttleCountdown = 0
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
                                      n: currentN,
                                      candidateIndex: candidate.index)
            advance()
        } catch {
            lastError = String(describing: error)
        }
    }

    /// After Accept, jump to the next unfinished panel (auto-advance per
    /// design memo #5). If everything is finalized, just refresh in place
    /// so the filmstrip clears and the accepted image displays correctly.
    private func advance() {
        if let next = nextUnfinished(after: currentN) {
            currentN = next
        }
        reloadCurrentPanel()
    }

    private func goTo(_ n: Int) {
        guard (1...12).contains(n) else { return }
        throttleTask?.cancel()
        throttleCountdown = 0
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
        case .throttled(let autoRetryPending):
            return autoRetryPending ? "Throttled — auto-retry in \(throttleCountdown)s" : "Throttled — manual retry needed"
        case .failed: return "Failed"
        case .missingPhoto: return "Missing reference photo"
        }
    }

    private func nextUnfinished(after n: Int) -> Int? {
        // "Next" = lowest unfinished panel ≠ n. Wraps back to earlier slots
        // if the operator jumped ahead, so out-of-order acceptance still
        // converges on all 12.
        for m in 1...12 where m != n {
            if !store.hasPanel(playerId: player.id, n: m) {
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

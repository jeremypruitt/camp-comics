import Foundation
import CampComicsCore

/// Static panel-generation workers shared by the deck surface's queue worker
/// and its ad-hoc Re-roll / panel-1 / triptych tasks. `runOne` is the
/// queue-safe path (early-exits on accepted + deferred targets);
/// `runOneAppendingCandidate` is the Re-roll path that always generates and
/// appends to the gallery.
enum PanelGenerationWorker {
    static func runOne(target: PanelTarget,
                       playerId: String,
                       template: ClassTemplate,
                       store: PlayerStore,
                       generator: any PanelGenerator) async throws {
        if store.hasPanel(playerId: playerId, target: target.id) { return }
        // A deferred panel must not auto-regenerate on session start — the
        // operator chose to skip it; auto-retrying would burn budget silently.
        // The only re-entry is an explicit grid-tap (pulls the card back to
        // deck top) or a stuck-card tap-to-retry per ADR-0010.
        if store.isDeferred(playerId: playerId, target: target.id) { return }
        try await runOneAppendingCandidate(target: target,
                                           playerId: playerId,
                                           template: template,
                                           store: store,
                                           generator: generator)
    }

    /// Always-generate-and-append path used by Re-roll and panel-1 bootstrap.
    /// The `hasPanel` guard is skipped because the head panel is by definition
    /// not yet accepted (Accept advances the deck). Decrements budget on
    /// success the same way the queue's worker does.
    ///
    /// `addendum` is preserved as dead code per ADR-0010 — long-press Re-prompt
    /// is dropped from the active surface but the parameter stays so a possible
    /// future return doesn't require a signature change.
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
}

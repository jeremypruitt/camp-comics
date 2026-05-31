import Foundation
import Testing
@testable import CampComicsCore

@Suite("PanelGridCellStatus")
struct PanelGridCellStatusTests {

    // MARK: - Fixtures

    private func makeStore() throws -> (PlayerStore, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("camp-comics-tests-\(UUID().uuidString)", isDirectory: true)
        let store = try PlayerStore(root: root)
        return (store, root)
    }

    private func makeTemplate() -> ClassTemplate {
        let combos: [(Emotion, Position)] = [
            (.neutral, .front), (.joy, .front), (.surprise, .front), (.fear, .front),
            (.neutral, .profile), (.joy, .profile), (.surprise, .profile), (.fear, .profile),
            (.neutral, .front), (.joy, .front), (.surprise, .profile), (.neutral, .profile)
        ]
        let panels = combos.enumerated().map { idx, combo in
            PanelSpec(n: idx + 1, beat: "panel \(idx + 1)",
                      emotion: combo.0, position: combo.1)
        }
        return ClassTemplate(
            classKey: "druid",
            name: "Druid",
            panels: panels,
            cover: CoverSpec(emotion: .joy, position: .front)
        )
    }

    private func capturePhoto(for target: PanelTarget,
                              playerId: String,
                              store: PlayerStore) throws {
        try store.savePhoto(playerId: playerId, requirement: target.requirement,
                            jpegData: Data([0xFF, 0xD8, 0xFF]))
    }

    private let pngStub = Data([0x89, 0x50, 0x4E, 0x47])

    // MARK: - Tests

    @Test func panelWithAcceptedWinnerYieldsAccepted() throws {
        let (store, _) = try makeStore()
        let template = makeTemplate()
        let player = try store.create(playerName: "Alex", characterName: "",
                                      classKey: "druid")
        let target = PanelTarget.panel(n: 1, spec: template.panels[0])
        try store.savePanel(playerId: player.id, target: target.id,
                            pngData: pngStub)

        let status = PanelGridCellStatus.derive(target: target,
                                                playerId: player.id,
                                                store: store)
        #expect(status == .accepted)
    }

    @Test func panelWithCandidatesAndNoWinnerYieldsReviewing() throws {
        let (store, _) = try makeStore()
        let template = makeTemplate()
        let player = try store.create(playerName: "Alex", characterName: "",
                                      classKey: "druid")
        let target = PanelTarget.panel(n: 1, spec: template.panels[0])
        try capturePhoto(for: target, playerId: player.id, store: store)
        _ = try store.savePendingCandidate(playerId: player.id, target: target.id,
                                           pngData: pngStub)

        let status = PanelGridCellStatus.derive(target: target,
                                                playerId: player.id,
                                                store: store)
        #expect(status == .reviewing)
    }

    @Test func panelWithNoCandidatesAndNoPhotoYieldsMissingPhoto() throws {
        let (store, _) = try makeStore()
        let template = makeTemplate()
        let player = try store.create(playerName: "Alex", characterName: "",
                                      classKey: "druid")
        let target = PanelTarget.panel(n: 1, spec: template.panels[0])

        let status = PanelGridCellStatus.derive(target: target,
                                                playerId: player.id,
                                                store: store)
        #expect(status == .missingPhoto)
    }

    @Test func panelWithPhotoButNothingElseYieldsUnstarted() throws {
        let (store, _) = try makeStore()
        let template = makeTemplate()
        let player = try store.create(playerName: "Alex", characterName: "",
                                      classKey: "druid")
        let target = PanelTarget.panel(n: 1, spec: template.panels[0])
        try capturePhoto(for: target, playerId: player.id, store: store)

        let status = PanelGridCellStatus.derive(target: target,
                                                playerId: player.id,
                                                store: store)
        #expect(status == .unstarted)
    }

    @Test func coverWithAcceptedWinnerYieldsAccepted() throws {
        let (store, _) = try makeStore()
        let template = makeTemplate()
        let player = try store.create(playerName: "Alex", characterName: "",
                                      classKey: "druid")
        let target = PanelTarget.cover(spec: template.cover)
        try store.savePanel(playerId: player.id, target: target.id, pngData: pngStub)

        let status = PanelGridCellStatus.derive(target: target,
                                                playerId: player.id,
                                                store: store)
        #expect(status == .accepted)
    }

    @Test func coverWithCandidatesAndNoWinnerYieldsReviewing() throws {
        let (store, _) = try makeStore()
        let template = makeTemplate()
        let player = try store.create(playerName: "Alex", characterName: "",
                                      classKey: "druid")
        let target = PanelTarget.cover(spec: template.cover)
        try capturePhoto(for: target, playerId: player.id, store: store)
        _ = try store.savePendingCandidate(playerId: player.id, target: target.id,
                                           pngData: pngStub)

        let status = PanelGridCellStatus.derive(target: target,
                                                playerId: player.id,
                                                store: store)
        #expect(status == .reviewing)
    }

    @Test func coverWithNoCandidatesAndNoPhotoYieldsMissingPhoto() throws {
        let (store, _) = try makeStore()
        let template = makeTemplate()
        let player = try store.create(playerName: "Alex", characterName: "",
                                      classKey: "druid")
        let target = PanelTarget.cover(spec: template.cover)

        let status = PanelGridCellStatus.derive(target: target,
                                                playerId: player.id,
                                                store: store)
        #expect(status == .missingPhoto)
    }

    @Test func coverWithPhotoButNothingElseYieldsUnstarted() throws {
        let (store, _) = try makeStore()
        let template = makeTemplate()
        let player = try store.create(playerName: "Alex", characterName: "",
                                      classKey: "druid")
        let target = PanelTarget.cover(spec: template.cover)
        try capturePhoto(for: target, playerId: player.id, store: store)

        let status = PanelGridCellStatus.derive(target: target,
                                                playerId: player.id,
                                                store: store)
        #expect(status == .unstarted)
    }

    @Test func panelWithDeferMarkerYieldsFailed() throws {
        // Slice H: a deferred panel persists a `.failed` sentinel under
        // `_candidates/{stem}/`. The grid surfaces it as `.failed` so the
        // operator can return from the grid and retry from the swipe stack.
        let (store, _) = try makeStore()
        let template = makeTemplate()
        let player = try store.create(playerName: "Alex", characterName: "",
                                      classKey: "druid")
        let target = PanelTarget.panel(n: 1, spec: template.panels[0])
        try capturePhoto(for: target, playerId: player.id, store: store)
        try store.markDeferred(playerId: player.id, target: target.id)

        let status = PanelGridCellStatus.derive(target: target,
                                                playerId: player.id,
                                                store: store)
        #expect(status == .failed)
    }

    @Test func coverWithDeferMarkerYieldsFailed() throws {
        let (store, _) = try makeStore()
        let template = makeTemplate()
        let player = try store.create(playerName: "Alex", characterName: "",
                                      classKey: "druid")
        let target = PanelTarget.cover(spec: template.cover)
        try capturePhoto(for: target, playerId: player.id, store: store)
        try store.markDeferred(playerId: player.id, target: target.id)

        let status = PanelGridCellStatus.derive(target: target,
                                                playerId: player.id,
                                                store: store)
        #expect(status == .failed)
    }

    @Test func acceptedWinnerBeatsLingeringDeferMarker() throws {
        // Defensive: if an accepted panel.png coexists with a stale `.failed`
        // marker (shouldn't happen — accept clears the gallery dir — but
        // belt-and-braces), the accepted winner wins the priority.
        let (store, _) = try makeStore()
        let template = makeTemplate()
        let player = try store.create(playerName: "Alex", characterName: "",
                                      classKey: "druid")
        let target = PanelTarget.panel(n: 1, spec: template.panels[0])
        try store.savePanel(playerId: player.id, target: target.id, pngData: pngStub)
        try store.markDeferred(playerId: player.id, target: target.id)

        let status = PanelGridCellStatus.derive(target: target,
                                                playerId: player.id,
                                                store: store)
        #expect(status == .accepted)
    }

    @Test func winnerOnDiskBeatsLingeringCandidates() throws {
        // After Accept the winner is saved but `_candidates/` is not pruned;
        // both exist on disk. The grid must report `.accepted`, not `.reviewing`,
        // so the cell renders the winning image.
        let (store, _) = try makeStore()
        let template = makeTemplate()
        let player = try store.create(playerName: "Alex", characterName: "",
                                      classKey: "druid")
        let target = PanelTarget.panel(n: 1, spec: template.panels[0])
        try capturePhoto(for: target, playerId: player.id, store: store)
        _ = try store.savePendingCandidate(playerId: player.id, target: target.id,
                                           pngData: pngStub)
        try store.savePanel(playerId: player.id, target: target.id, pngData: pngStub)

        let status = PanelGridCellStatus.derive(target: target,
                                                playerId: player.id,
                                                store: store)
        #expect(status == .accepted)
    }
}

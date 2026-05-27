import Foundation
import Testing
@testable import CampComicsCore

@Suite("PlayerStatus")
struct PlayerStatusTests {

    // MARK: - Fixtures

    private func makeStore() throws -> (PlayerStore, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("camp-comics-tests-\(UUID().uuidString)", isDirectory: true)
        let store = try PlayerStore(root: root)
        return (store, root)
    }

    /// 12-panel template that cycles all four emotions across both positions
    /// so every test exercises a realistic requirement set without needing the
    /// real druid YAML on disk.
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
            cover: PanelRequirement(emotion: .joy, position: .front)
        )
    }

    private func captureAllPhotos(for template: ClassTemplate,
                                  playerId: String,
                                  store: PlayerStore) throws {
        for req in CapturePlanner.plan(for: template) {
            try store.savePhoto(playerId: playerId, requirement: req,
                                jpegData: Data([0xFF, 0xD8, 0xFF]))
        }
    }

    // MARK: - Tests

    @Test func freshCapturedPlayerHasCapturedStatus() throws {
        let (store, _) = try makeStore()
        let template = makeTemplate()
        let player = try store.create(playerName: "Alex", characterName: "",
                                      classKey: "druid")
        try captureAllPhotos(for: template, playerId: player.id, store: store)

        let status = PlayerStatus.derive(playerId: player.id,
                                         template: template,
                                         store: store)
        #expect(status == .captured)
    }

    @Test func oneAcceptedPanelTransitionsToGenerating() throws {
        let (store, _) = try makeStore()
        let template = makeTemplate()
        let player = try store.create(playerName: "Alex", characterName: "",
                                      classKey: "druid")
        try captureAllPhotos(for: template, playerId: player.id, store: store)
        try store.savePanel(playerId: player.id, n: 1,
                            pngData: Data([0x89, 0x50, 0x4E, 0x47]))

        let status = PlayerStatus.derive(playerId: player.id,
                                         template: template,
                                         store: store)
        #expect(status == .generating(done: 1, total: 12))
    }

    @Test func skippedPanelCountsTowardDone() throws {
        let (store, _) = try makeStore()
        let template = makeTemplate()
        let player = try store.create(playerName: "Alex", characterName: "",
                                      classKey: "druid")
        try captureAllPhotos(for: template, playerId: player.id, store: store)
        try store.markSkipped(playerId: player.id, n: 3)

        let status = PlayerStatus.derive(playerId: player.id,
                                         template: template,
                                         store: store)
        #expect(status == .generating(done: 1, total: 12))
    }

    @Test func allAcceptedReportsDone() throws {
        let (store, _) = try makeStore()
        let template = makeTemplate()
        let player = try store.create(playerName: "Alex", characterName: "",
                                      classKey: "druid")
        try captureAllPhotos(for: template, playerId: player.id, store: store)
        for panel in template.panels {
            try store.savePanel(playerId: player.id, n: panel.n,
                                pngData: Data([0x89, 0x50, 0x4E, 0x47]))
        }

        let status = PlayerStatus.derive(playerId: player.id,
                                         template: template,
                                         store: store)
        #expect(status == .done)
    }

    @Test func unresolvedPanelWithMissingPhotoReportsNeedsPhoto() throws {
        let (store, _) = try makeStore()
        let template = makeTemplate()
        let player = try store.create(playerName: "Alex", characterName: "",
                                      classKey: "druid")
        // Capture every required photo EXCEPT the one panel 1 needs.
        let panel1Req = template.panels[0].requirement
        for req in CapturePlanner.plan(for: template) where req != panel1Req {
            try store.savePhoto(playerId: player.id, requirement: req,
                                jpegData: Data([0xFF, 0xD8, 0xFF]))
        }

        let status = PlayerStatus.derive(playerId: player.id,
                                         template: template,
                                         store: store)
        #expect(status == .needsPhoto)
    }

    @Test func mixOfAcceptedAndSkippedAlsoReportsDone() throws {
        let (store, _) = try makeStore()
        let template = makeTemplate()
        let player = try store.create(playerName: "Alex", characterName: "",
                                      classKey: "druid")
        try captureAllPhotos(for: template, playerId: player.id, store: store)
        for panel in template.panels {
            if panel.n.isMultiple(of: 2) {
                try store.markSkipped(playerId: player.id, n: panel.n)
            } else {
                try store.savePanel(playerId: player.id, n: panel.n,
                                    pngData: Data([0x89, 0x50, 0x4E, 0x47]))
            }
        }

        let status = PlayerStatus.derive(playerId: player.id,
                                         template: template,
                                         store: store)
        #expect(status == .done)
    }

    @Test func deletingPanelFileFromDoneDropsBackToGenerating() throws {
        let (store, _) = try makeStore()
        let template = makeTemplate()
        let player = try store.create(playerName: "Alex", characterName: "",
                                      classKey: "druid")
        try captureAllPhotos(for: template, playerId: player.id, store: store)
        for panel in template.panels {
            try store.savePanel(playerId: player.id, n: panel.n,
                                pngData: Data([0x89, 0x50, 0x4E, 0x47]))
        }
        #expect(PlayerStatus.derive(playerId: player.id, template: template,
                                    store: store) == .done)

        try store.deletePanel(playerId: player.id, n: 5)

        let status = PlayerStatus.derive(playerId: player.id,
                                         template: template,
                                         store: store)
        #expect(status == .generating(done: 11, total: 12))
    }

    @Test func missingPhotoDoesNotFlagWhenEveryPanelResolved() throws {
        let (store, _) = try makeStore()
        let template = makeTemplate()
        let player = try store.create(playerName: "Alex", characterName: "",
                                      classKey: "druid")
        try captureAllPhotos(for: template, playerId: player.id, store: store)
        for panel in template.panels {
            try store.savePanel(playerId: player.id, n: panel.n,
                                pngData: Data([0x89, 0x50, 0x4E, 0x47]))
        }
        // Delete a required photo *after* all panels are done. Since no panel
        // still needs that photo for generation, the player should stay .done.
        try store.deletePhoto(playerId: player.id,
                              requirement: template.panels[0].requirement)

        let status = PlayerStatus.derive(playerId: player.id,
                                         template: template,
                                         store: store)
        #expect(status == .done)
    }
}

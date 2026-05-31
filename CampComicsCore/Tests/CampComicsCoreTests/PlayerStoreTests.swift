import Foundation
import Testing
@testable import CampComicsCore

@Suite("PlayerStore")
struct PlayerStoreTests {

    private func makeStore() throws -> (PlayerStore, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("camp-comics-tests-\(UUID().uuidString)", isDirectory: true)
        let store = try PlayerStore(root: root)
        return (store, root)
    }

    @Test func createAssignsSequentialIds() throws {
        let (store, _) = try makeStore()
        let a = try store.create(playerName: "Alex", characterName: "", classKey: "druid")
        let b = try store.create(playerName: "Bea", characterName: "", classKey: "druid")
        let c = try store.create(playerName: "Cy", characterName: "", classKey: "druid")
        #expect(a.id == "player_001")
        #expect(b.id == "player_002")
        #expect(c.id == "player_003")
    }

    @Test func createWritesTokensJsonReadableByLoad() throws {
        let (store, _) = try makeStore()
        let when = Date(timeIntervalSince1970: 1_750_000_000)
        let created = try store.create(playerName: "Alex",
                                       characterName: "Faeloria",
                                       classKey: "druid",
                                       now: when)
        let loaded = try store.load(id: created.id)
        #expect(loaded == created)
    }

    @Test func listReturnsAllPlayersSortedById() throws {
        let (store, _) = try makeStore()
        _ = try store.create(playerName: "A", characterName: "", classKey: "druid")
        _ = try store.create(playerName: "B", characterName: "", classKey: "druid")
        _ = try store.create(playerName: "C", characterName: "", classKey: "druid")
        let all = try store.list()
        #expect(all.map(\.id) == ["player_001", "player_002", "player_003"])
    }

    @Test func loadThrowsForUnknownId() throws {
        let (store, _) = try makeStore()
        #expect(throws: PlayerStoreError.playerNotFound("player_404")) {
            try store.load(id: "player_404")
        }
    }

    @Test func filenameEncodesEmotionAndPosition() {
        let r = PanelRequirement(emotion: .joy, position: .front)
        #expect(PlayerStore.filename(for: r) == "joy_front.jpg")
    }

    @Test func parseFilenameRoundTripsEveryPair() {
        for emotion in Emotion.allCases {
            for position in Position.allCases {
                let req = PanelRequirement(emotion: emotion, position: position)
                let name = PlayerStore.filename(for: req)
                #expect(PlayerStore.parseFilename(name) == req)
            }
        }
    }

    @Test func parseFilenameRejectsGarbage() {
        #expect(PlayerStore.parseFilename("README.md") == nil)
        #expect(PlayerStore.parseFilename("joy.jpg") == nil)
        #expect(PlayerStore.parseFilename("bogus_front.jpg") == nil)
    }

    @Test func savePhotoRoundTripsBytes() throws {
        let (store, _) = try makeStore()
        let player = try store.create(playerName: "Alex", characterName: "", classKey: "druid")
        let req = PanelRequirement(emotion: .neutral, position: .front)
        let bytes = Data((0..<2048).map { _ in UInt8.random(in: 0...255) })
        try store.savePhoto(playerId: player.id, requirement: req, jpegData: bytes)
        let loaded = store.loadPhoto(playerId: player.id, requirement: req)
        #expect(loaded == bytes)
    }

    @Test func savePhotoOverwritesPriorBytes() throws {
        let (store, _) = try makeStore()
        let player = try store.create(playerName: "Alex", characterName: "", classKey: "druid")
        let req = PanelRequirement(emotion: .neutral, position: .front)
        try store.savePhoto(playerId: player.id, requirement: req, jpegData: Data([0x01]))
        try store.savePhoto(playerId: player.id, requirement: req, jpegData: Data([0x02, 0x03]))
        #expect(store.loadPhoto(playerId: player.id, requirement: req) == Data([0x02, 0x03]))
    }

    @Test func deletePhotoRemovesIt() throws {
        let (store, _) = try makeStore()
        let player = try store.create(playerName: "Alex", characterName: "", classKey: "druid")
        let req = PanelRequirement(emotion: .joy, position: .front)
        try store.savePhoto(playerId: player.id, requirement: req, jpegData: Data([0x09]))
        try store.deletePhoto(playerId: player.id, requirement: req)
        #expect(store.loadPhoto(playerId: player.id, requirement: req) == nil)
    }

    @Test func deletePhotoIsNoOpWhenAbsent() throws {
        let (store, _) = try makeStore()
        let player = try store.create(playerName: "Alex", characterName: "", classKey: "druid")
        let req = PanelRequirement(emotion: .fear, position: .profile)
        try store.deletePhoto(playerId: player.id, requirement: req)
    }

    @Test func capturedRequirementsReflectsWhatsOnDisk() throws {
        let (store, _) = try makeStore()
        let player = try store.create(playerName: "Alex", characterName: "", classKey: "druid")
        let r1 = PanelRequirement(emotion: .neutral, position: .front)
        let r2 = PanelRequirement(emotion: .joy, position: .front)
        try store.savePhoto(playerId: player.id, requirement: r1, jpegData: Data([0x01]))
        try store.savePhoto(playerId: player.id, requirement: r2, jpegData: Data([0x02]))
        #expect(store.capturedRequirements(playerId: player.id) == [r1, r2])
        try store.deletePhoto(playerId: player.id, requirement: r1)
        #expect(store.capturedRequirements(playerId: player.id) == [r2])
    }

    @Test func nextIdSkipsGapsAndPicksMaxPlusOne() throws {
        let (store, root) = try makeStore()
        _ = try store.create(playerName: "A", characterName: "", classKey: "druid")
        _ = try store.create(playerName: "B", characterName: "", classKey: "druid")
        _ = try store.create(playerName: "C", characterName: "", classKey: "druid")
        try FileManager.default.removeItem(at: root.appendingPathComponent("players/player_002"))
        let d = try store.create(playerName: "D", characterName: "", classKey: "druid")
        #expect(d.id == "player_004")
    }

    // MARK: - QA panel persistence

    @Test func saveQAPanelRoundTripsBytes() throws {
        let (store, _) = try makeStore()
        let player = try store.create(playerName: "Alex", characterName: "", classKey: "druid")
        let bytes = Data((0..<4096).map { _ in UInt8.random(in: 0...255) })
        try store.saveQAPanel(playerId: player.id, pngData: bytes)
        #expect(store.loadQAPanel(playerId: player.id) == bytes)
    }

    @Test func saveQAPanelOverwritesPriorBytes() throws {
        let (store, _) = try makeStore()
        let player = try store.create(playerName: "Alex", characterName: "", classKey: "druid")
        try store.saveQAPanel(playerId: player.id, pngData: Data([0x01]))
        try store.saveQAPanel(playerId: player.id, pngData: Data([0x02, 0x03]))
        #expect(store.loadQAPanel(playerId: player.id) == Data([0x02, 0x03]))
    }

    @Test func loadQAPanelReturnsNilWhenAbsent() throws {
        let (store, _) = try makeStore()
        let player = try store.create(playerName: "Alex", characterName: "", classKey: "druid")
        #expect(store.loadQAPanel(playerId: player.id) == nil)
    }

    @Test func deleteQAPanelRemovesIt() throws {
        let (store, _) = try makeStore()
        let player = try store.create(playerName: "Alex", characterName: "", classKey: "druid")
        try store.saveQAPanel(playerId: player.id, pngData: Data([0x09]))
        try store.deleteQAPanel(playerId: player.id)
        #expect(store.loadQAPanel(playerId: player.id) == nil)
    }

    @Test func deleteQAPanelIsNoOpWhenAbsent() throws {
        let (store, _) = try makeStore()
        let player = try store.create(playerName: "Alex", characterName: "", classKey: "druid")
        try store.deleteQAPanel(playerId: player.id)
    }

    // MARK: - Narrative panel persistence (slice 8+)

    @Test func savePanelRoundTripsBytes() throws {
        let (store, _) = try makeStore()
        let player = try store.create(playerName: "Alex", characterName: "", classKey: "druid")
        let bytes = Data((0..<8192).map { _ in UInt8.random(in: 0...255) })
        try store.savePanel(playerId: player.id, target: .panel(1), pngData: bytes)
        #expect(store.loadPanel(playerId: player.id, target: .panel(1)) == bytes)
    }

    @Test func savePanelWritesPaddedFilename() throws {
        // panel_01.png, not panel_1.png — matches the legacy layout and the
        // on-disk grammar in CONTEXT.md / project_panel_loop_design.md #15.
        let (store, root) = try makeStore()
        let player = try store.create(playerName: "Alex", characterName: "", classKey: "druid")
        try store.savePanel(playerId: player.id, target: .panel(7), pngData: Data([0x01]))
        let url = root.appendingPathComponent("players/\(player.id)/panels/panel_07.png")
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func saveCoverWritesCoverPng() throws {
        // Slice 11b: cover target maps to `panels/cover.png` (no panel_ prefix).
        let (store, root) = try makeStore()
        let player = try store.create(playerName: "Alex", characterName: "", classKey: "druid")
        try store.savePanel(playerId: player.id, target: .cover, pngData: Data([0xC0, 0x5E, 0x18]))
        let url = root.appendingPathComponent("players/\(player.id)/panels/cover.png")
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(store.loadPanel(playerId: player.id, target: .cover) == Data([0xC0, 0x5E, 0x18]))
        #expect(store.hasPanel(playerId: player.id, target: .cover))
    }

    @Test func saveCoverCandidatesLandUnderCoverDir() throws {
        // Slice 11b: cover candidates live in `_candidates/cover/`, separate
        // from any `_candidates/NN/` panel galleries on the same player.
        let (store, root) = try makeStore()
        let player = try store.create(playerName: "Alex", characterName: "", classKey: "druid")
        _ = try store.savePendingCandidate(playerId: player.id, target: .cover,
                                           pngData: Data([0xAA]))
        _ = try store.savePendingCandidate(playerId: player.id, target: .cover,
                                           pngData: Data([0xBB]))

        let coverDir = root.appendingPathComponent(
            "players/\(player.id)/panels/_candidates/cover")
        let entries = try FileManager.default.contentsOfDirectory(atPath: coverDir.path).sorted()
        #expect(entries == ["000.png", "001.png"])

        try store.acceptCandidate(playerId: player.id, target: .cover, candidateIndex: 1)
        #expect(store.loadPanel(playerId: player.id, target: .cover) == Data([0xBB]))
        #expect(store.listCandidates(playerId: player.id, target: .cover).isEmpty)
    }

    @Test func hasPanelReflectsDiskState() throws {
        let (store, _) = try makeStore()
        let player = try store.create(playerName: "Alex", characterName: "", classKey: "druid")
        #expect(store.hasPanel(playerId: player.id, target: .panel(1)) == false)
        try store.savePanel(playerId: player.id, target: .panel(1), pngData: Data([0x09]))
        #expect(store.hasPanel(playerId: player.id, target: .panel(1)) == true)
    }

    @Test func loadPanelReturnsNilWhenAbsent() throws {
        let (store, _) = try makeStore()
        let player = try store.create(playerName: "Alex", characterName: "", classKey: "druid")
        #expect(store.loadPanel(playerId: player.id, target: .panel(1)) == nil)
    }

    @Test func hasQAPanelReflectsDiskState() throws {
        let (store, _) = try makeStore()
        let player = try store.create(playerName: "Alex", characterName: "", classKey: "druid")
        #expect(store.hasQAPanel(playerId: player.id) == false)
        try store.saveQAPanel(playerId: player.id, pngData: Data([0x01]))
        #expect(store.hasQAPanel(playerId: player.id) == true)
        try store.deleteQAPanel(playerId: player.id)
        #expect(store.hasQAPanel(playerId: player.id) == false)
    }

    // MARK: - Candidate gallery (slice 9)

    @Test func savePendingCandidateAssignsZeroForFirstAndOneForSecond() throws {
        let (store, _) = try makeStore()
        let player = try store.create(playerName: "Alex", characterName: "", classKey: "druid")

        let first = try store.savePendingCandidate(playerId: player.id, target: .panel(3), pngData: Data([0xAA]))
        let second = try store.savePendingCandidate(playerId: player.id, target: .panel(3), pngData: Data([0xBB]))

        #expect(first.index == 0)
        #expect(second.index == 1)
    }

    @Test func listCandidatesReturnsAllSavedInIndexOrder() throws {
        let (store, _) = try makeStore()
        let player = try store.create(playerName: "Alex", characterName: "", classKey: "druid")
        _ = try store.savePendingCandidate(playerId: player.id, target: .panel(3), pngData: Data([0xAA]))
        _ = try store.savePendingCandidate(playerId: player.id, target: .panel(3), pngData: Data([0xBB]))
        _ = try store.savePendingCandidate(playerId: player.id, target: .panel(3), pngData: Data([0xCC]))

        let candidates = store.listCandidates(playerId: player.id, target: .panel(3))

        #expect(candidates.map(\.index) == [0, 1, 2])
    }

    @Test func listCandidatesIsEmptyForUntouchedPanel() throws {
        let (store, _) = try makeStore()
        let player = try store.create(playerName: "Alex", characterName: "", classKey: "druid")
        #expect(store.listCandidates(playerId: player.id, target: .panel(7)).isEmpty)
    }

    @Test func acceptCandidatePromotesChosenAndDeletesTheRest() throws {
        let (store, _) = try makeStore()
        let player = try store.create(playerName: "Alex", characterName: "", classKey: "druid")
        _ = try store.savePendingCandidate(playerId: player.id, target: .panel(4), pngData: Data([0xAA]))
        _ = try store.savePendingCandidate(playerId: player.id, target: .panel(4), pngData: Data([0xBB]))
        _ = try store.savePendingCandidate(playerId: player.id, target: .panel(4), pngData: Data([0xCC]))

        try store.acceptCandidate(playerId: player.id, target: .panel(4), candidateIndex: 1)

        #expect(store.loadPanel(playerId: player.id, target: .panel(4)) == Data([0xBB]))
        #expect(store.listCandidates(playerId: player.id, target: .panel(4)).isEmpty)
    }

    @Test func deletePanelRemovesTheAcceptedImage() throws {
        let (store, _) = try makeStore()
        let player = try store.create(playerName: "Alex", characterName: "", classKey: "druid")
        _ = try store.savePendingCandidate(playerId: player.id, target: .panel(2), pngData: Data([0x09]))
        try store.acceptCandidate(playerId: player.id, target: .panel(2), candidateIndex: 0)
        #expect(store.hasPanel(playerId: player.id, target: .panel(2)))

        try store.deletePanel(playerId: player.id, target: .panel(2))

        #expect(store.hasPanel(playerId: player.id, target: .panel(2)) == false)
    }

    @Test func attemptsStateIsEmptyBeforeAnyWrites() throws {
        let (store, _) = try makeStore()
        let player = try store.create(playerName: "Alex", characterName: "", classKey: "druid")
        #expect(store.attemptsState(playerId: player.id).isEmpty)
    }

    @Test func demoteAcceptedToCandidateMovesPanelIntoCandidatesDir() throws {
        // Re-roll-after-accept demotes the prior winner back to candidate #1 so
        // the operator doesn't lose the previously-accepted image until they
        // commit a new winner (design memo decision #3).
        let (store, _) = try makeStore()
        let player = try store.create(playerName: "Alex", characterName: "", classKey: "druid")
        _ = try store.savePendingCandidate(playerId: player.id, target: .panel(5), pngData: Data([0xAA]))
        try store.acceptCandidate(playerId: player.id, target: .panel(5), candidateIndex: 0)
        #expect(store.hasPanel(playerId: player.id, target: .panel(5)))

        try store.demoteAcceptedToCandidate(playerId: player.id, target: .panel(5))

        #expect(store.hasPanel(playerId: player.id, target: .panel(5)) == false)
        let candidates = store.listCandidates(playerId: player.id, target: .panel(5))
        #expect(candidates.count == 1)
        let bytes = try Data(contentsOf: candidates[0].url)
        #expect(bytes == Data([0xAA]))
    }

    @Test func setAttemptsStateRoundTrips() throws {
        let (store, _) = try makeStore()
        let player = try store.create(playerName: "Alex", characterName: "", classKey: "druid")
        let when = Date(timeIntervalSince1970: 1_750_000_000)
        let records: [PanelAttempt] = [
            PanelAttempt(target: .panel(1), attempt: 0, prompt: "first prompt",
                         candidateFile: "_candidates/01/000.png", generatedAt: when),
            PanelAttempt(target: .panel(1), attempt: 1, prompt: "tweaked prompt",
                         candidateFile: "_candidates/01/001.png", generatedAt: when),
            PanelAttempt(target: .cover, attempt: 0, prompt: "cover prompt",
                         candidateFile: "_candidates/cover/000.png", generatedAt: when),
        ]

        try store.setAttemptsState(playerId: player.id, attempts: records)

        #expect(store.attemptsState(playerId: player.id) == records)
    }

    @Test func panelAttemptEncodesTargetAsDiscriminatorString() throws {
        // Slice 11b: PanelAttempt.target is persisted as "panel_07" / "cover"
        // on disk so the JSON stays human-readable and the same file works for
        // both panel and cover attempts.
        let attempts: [PanelAttempt] = [
            PanelAttempt(target: .panel(7), attempt: 0, prompt: "p",
                         candidateFile: "f", generatedAt: Date(timeIntervalSince1970: 0)),
            PanelAttempt(target: .cover, attempt: 0, prompt: "p",
                         candidateFile: "f", generatedAt: Date(timeIntervalSince1970: 0)),
        ]

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let json = String(data: try encoder.encode(attempts), encoding: .utf8) ?? ""

        #expect(json.contains("\"target\":\"panel_07\""))
        #expect(json.contains("\"target\":\"cover\""))
    }

    // MARK: - Candidate timestamp + re-roll append semantics (slice E)

    @Test func savePendingCandidateStampsGeneratedAt() throws {
        let (store, _) = try makeStore()
        let player = try store.create(playerName: "Alex", characterName: "", classKey: "druid")
        let before = Date()
        let candidate = try store.savePendingCandidate(playerId: player.id,
                                                       target: .panel(3),
                                                       pngData: Data([0xAA]))
        let after = Date()
        let stamped = try #require(candidate.generatedAt)
        #expect(stamped >= before.addingTimeInterval(-1))
        #expect(stamped <= after.addingTimeInterval(1))
    }

    @Test func listCandidatesPopulatesGeneratedAt() throws {
        let (store, _) = try makeStore()
        let player = try store.create(playerName: "Alex", characterName: "", classKey: "druid")
        _ = try store.savePendingCandidate(playerId: player.id, target: .panel(3), pngData: Data([0xAA]))
        _ = try store.savePendingCandidate(playerId: player.id, target: .panel(3), pngData: Data([0xBB]))

        let candidates = store.listCandidates(playerId: player.id, target: .panel(3))
        #expect(candidates.count == 2)
        for c in candidates {
            #expect(c.generatedAt != nil)
        }
    }

    @Test func rerollAppendsNewCandidateAtNextIndex() throws {
        // The slice-E re-roll path is just another `savePendingCandidate` call:
        // it must land at index = current_max + 1 and not disturb prior bytes.
        // This guards against any future "rotate / replace" refactor.
        let (store, _) = try makeStore()
        let player = try store.create(playerName: "Alex", characterName: "", classKey: "druid")
        _ = try store.savePendingCandidate(playerId: player.id, target: .panel(5), pngData: Data([0xAA]))
        _ = try store.savePendingCandidate(playerId: player.id, target: .panel(5), pngData: Data([0xBB]))

        let rerolled = try store.savePendingCandidate(playerId: player.id, target: .panel(5),
                                                      pngData: Data([0xCC]))
        #expect(rerolled.index == 2)

        let candidates = store.listCandidates(playerId: player.id, target: .panel(5))
        let bytes = try candidates.map { try Data(contentsOf: $0.url) }
        #expect(bytes == [Data([0xAA]), Data([0xBB]), Data([0xCC])])
    }

    @Test func acceptCandidatePromotesVisibleAndDiscardsRest() throws {
        // Slice-E swipe-right Accept must use the *currently visible* index,
        // not always "last". Three candidates, accept #1 (middle) — verify the
        // chosen bytes win and the candidates directory is wiped.
        let (store, root) = try makeStore()
        let player = try store.create(playerName: "Alex", characterName: "", classKey: "druid")
        _ = try store.savePendingCandidate(playerId: player.id, target: .panel(7), pngData: Data([0xAA]))
        _ = try store.savePendingCandidate(playerId: player.id, target: .panel(7), pngData: Data([0xBB]))
        _ = try store.savePendingCandidate(playerId: player.id, target: .panel(7), pngData: Data([0xCC]))

        try store.acceptCandidate(playerId: player.id, target: .panel(7), candidateIndex: 1)

        #expect(store.loadPanel(playerId: player.id, target: .panel(7)) == Data([0xBB]))
        let dir = root.appendingPathComponent("players/\(player.id)/panels/_candidates/07")
        #expect(!FileManager.default.fileExists(atPath: dir.path))
    }

    // MARK: - Defer marker (slice H — ADR-0009 failed-card recovery)

    @Test func markDeferredWritesSentinelInCandidatesDir() throws {
        // Slice H: a deferred panel persists a zero-byte `.failed` sentinel at
        // `panels/_candidates/{stem}/.failed`. Co-locating with the gallery
        // means `acceptCandidate`'s existing `removeItem(_candidates/{stem})`
        // auto-clears the marker if the operator later retries-and-accepts.
        let (store, root) = try makeStore()
        let player = try store.create(playerName: "Alex", characterName: "", classKey: "druid")
        try store.markDeferred(playerId: player.id, target: .panel(7))
        let url = root.appendingPathComponent(
            "players/\(player.id)/panels/_candidates/07/.failed")
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(store.isDeferred(playerId: player.id, target: .panel(7)))
    }

    @Test func markDeferredForCoverWritesUnderCoverDir() throws {
        let (store, root) = try makeStore()
        let player = try store.create(playerName: "Alex", characterName: "", classKey: "druid")
        try store.markDeferred(playerId: player.id, target: .cover)
        let url = root.appendingPathComponent(
            "players/\(player.id)/panels/_candidates/cover/.failed")
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(store.isDeferred(playerId: player.id, target: .cover))
    }

    @Test func unmarkDeferredRemovesSentinel() throws {
        let (store, _) = try makeStore()
        let player = try store.create(playerName: "Alex", characterName: "", classKey: "druid")
        try store.markDeferred(playerId: player.id, target: .panel(3))
        #expect(store.isDeferred(playerId: player.id, target: .panel(3)))
        try store.unmarkDeferred(playerId: player.id, target: .panel(3))
        #expect(!store.isDeferred(playerId: player.id, target: .panel(3)))
    }

    @Test func unmarkDeferredIsNoOpWhenAbsent() throws {
        let (store, _) = try makeStore()
        let player = try store.create(playerName: "Alex", characterName: "", classKey: "druid")
        try store.unmarkDeferred(playerId: player.id, target: .panel(4))
        #expect(!store.isDeferred(playerId: player.id, target: .panel(4)))
    }

    @Test func isDeferredIsFalseForFreshPanel() throws {
        let (store, _) = try makeStore()
        let player = try store.create(playerName: "Alex", characterName: "", classKey: "druid")
        #expect(!store.isDeferred(playerId: player.id, target: .panel(7)))
        #expect(!store.isDeferred(playerId: player.id, target: .cover))
    }

    @Test func acceptCandidateClearsDeferMarker() throws {
        // Retry path: the operator deferred a failed panel, later retried, a
        // candidate landed, Accept cleared the gallery dir. Since the marker
        // lives inside `_candidates/{stem}/`, acceptCandidate's existing
        // removeItem wipes it without us having to call unmarkDeferred.
        let (store, _) = try makeStore()
        let player = try store.create(playerName: "Alex", characterName: "", classKey: "druid")
        try store.markDeferred(playerId: player.id, target: .panel(5))
        _ = try store.savePendingCandidate(playerId: player.id, target: .panel(5),
                                           pngData: Data([0xAA]))
        try store.acceptCandidate(playerId: player.id, target: .panel(5), candidateIndex: 0)
        #expect(!store.isDeferred(playerId: player.id, target: .panel(5)))
    }

    @Test func savePendingCandidateClearsDeferMarker() throws {
        // Retry that produces a candidate (operator hasn't accepted yet)
        // should clear the marker too — otherwise the cell would render as
        // both .failed and .reviewing simultaneously.
        let (store, _) = try makeStore()
        let player = try store.create(playerName: "Alex", characterName: "", classKey: "druid")
        try store.markDeferred(playerId: player.id, target: .panel(5))
        _ = try store.savePendingCandidate(playerId: player.id, target: .panel(5),
                                           pngData: Data([0xAA]))
        #expect(!store.isDeferred(playerId: player.id, target: .panel(5)))
    }

    @Test func attemptsStateReturnsEmptyForLegacyNSchemaJSON() throws {
        // Slice 11b: hard cutover — pre-slice-11b _attempts.json carried
        // `{"n": 1, ...}` rows. They no longer match PanelAttempt's shape, so
        // the decoder fails and attemptsState() yields [] rather than crashing.
        // No migration is performed; the operator just loses prior-prompt
        // recall for already-generated panels (irrelevant for fresh cohorts).
        let (store, root) = try makeStore()
        let player = try store.create(playerName: "Alex", characterName: "", classKey: "druid")
        let panelsDir = root
            .appendingPathComponent("players/\(player.id)/panels", isDirectory: true)
        try FileManager.default.createDirectory(at: panelsDir, withIntermediateDirectories: true)
        let legacyJSON = """
        [
          { "n": 1, "attempt": 0, "prompt": "old", "candidateFile": "f", "generatedAt": "2026-01-01T00:00:00Z" }
        ]
        """.data(using: .utf8)!
        try legacyJSON.write(to: panelsDir.appendingPathComponent("_attempts.json"))

        #expect(store.attemptsState(playerId: player.id).isEmpty)
    }
}

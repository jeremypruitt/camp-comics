import Foundation

/// Player profile + creation timestamp as it lives in `tokens.json`. The
/// captured-photo set is derivable from the `photos/` directory listing
/// (filenames encode `(emotion, position)`), so we don't store it here too.
public struct PlayerRecord: Hashable, Codable, Sendable {
    public let id: String
    public var playerName: String
    public var characterName: String
    public var classKey: String
    public let createdAt: Date

    public init(id: String,
                playerName: String,
                characterName: String,
                classKey: String,
                createdAt: Date) {
        self.id = id
        self.playerName = playerName
        self.characterName = characterName
        self.classKey = classKey
        self.createdAt = createdAt
    }
}

public enum PlayerStoreError: Error, Equatable {
    case playerNotFound(String)
}

/// One candidate in a panel's review gallery: the on-disk PNG plus the integer
/// index used to address it for `acceptCandidate`. Indices are dense (0, 1, 2…)
/// in save order and survive across re-roll cancels until Accept clears them.
public struct PanelCandidate: Equatable, Sendable {
    public let index: Int
    public let url: URL

    public init(index: Int, url: URL) {
        self.index = index
        self.url = url
    }
}

/// One row of `_attempts.json` — used by Re-prompt to recover the operator's
/// last-edited prompt and by debug tooling to audit what was generated where.
/// `target` is the disk discriminator (`panel_07` / `cover`) so the cover and
/// panel attempts can coexist in one file (slice 11b).
public struct PanelAttempt: Equatable, Codable, Sendable {
    public let target: PanelTargetID
    public let attempt: Int
    public let prompt: String
    public let candidateFile: String
    public let generatedAt: Date

    public init(target: PanelTargetID, attempt: Int, prompt: String,
                candidateFile: String, generatedAt: Date) {
        self.target = target
        self.attempt = attempt
        self.prompt = prompt
        self.candidateFile = candidateFile
        self.generatedAt = generatedAt
    }
}

/// On-disk player layout, rooted at an injectable directory so tests can use
/// a tmpdir and the app can use `Documents/`:
///
///   {root}/players/player_001/tokens.json
///   {root}/players/player_001/photos/{emotion}_{position}.jpg
///   {root}/players/player_001/panels/qa_avatar.png
///
/// All methods are non-mutating; the struct is a thin façade over FileManager.
public struct PlayerStore: Sendable {
    private let root: URL

    public init(root: URL) throws {
        self.root = root
        try FileManager.default.createDirectory(at: playersDir(in: root),
                                                withIntermediateDirectories: true)
    }

    public static func documentsRoot() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    // MARK: - Player lifecycle

    public func create(playerName: String,
                       characterName: String,
                       classKey: String,
                       now: Date = Date()) throws -> PlayerRecord {
        let id = try nextId()
        let record = PlayerRecord(id: id,
                                  playerName: playerName,
                                  characterName: characterName,
                                  classKey: classKey,
                                  createdAt: now)
        try FileManager.default.createDirectory(at: photosDir(for: id),
                                                withIntermediateDirectories: true)
        try writeTokens(record)
        return record
    }

    public func list() throws -> [PlayerRecord] {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: playersDir(in: root),
            includingPropertiesForKeys: nil)) ?? []
        return entries
            .compactMap { try? readTokens(in: $0) }
            .sorted { $0.id < $1.id }
    }

    public func load(id: String) throws -> PlayerRecord {
        do {
            return try readTokens(in: playerDir(for: id))
        } catch {
            throw PlayerStoreError.playerNotFound(id)
        }
    }

    // MARK: - Photos

    public func savePhoto(playerId: String,
                          requirement: PanelRequirement,
                          jpegData: Data) throws {
        try jpegData.write(to: photoURL(playerId: playerId, requirement: requirement),
                           options: .atomic)
    }

    public func loadPhoto(playerId: String, requirement: PanelRequirement) -> Data? {
        try? Data(contentsOf: photoURL(playerId: playerId, requirement: requirement))
    }

    public func deletePhoto(playerId: String, requirement: PanelRequirement) throws {
        let url = photoURL(playerId: playerId, requirement: requirement)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - QA panel (the avatar preview)

    public func saveQAPanel(playerId: String, pngData: Data) throws {
        try FileManager.default.createDirectory(at: panelsDir(for: playerId),
                                                withIntermediateDirectories: true)
        try pngData.write(to: qaPanelURL(playerId: playerId), options: .atomic)
    }

    public func loadQAPanel(playerId: String) -> Data? {
        try? Data(contentsOf: qaPanelURL(playerId: playerId))
    }

    public func deleteQAPanel(playerId: String) throws {
        let url = qaPanelURL(playerId: playerId)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    public func hasQAPanel(playerId: String) -> Bool {
        FileManager.default.fileExists(atPath: qaPanelURL(playerId: playerId).path)
    }

    // MARK: - Accepted artifact (panel_NN.png / cover.png — slice 11b)

    public func savePanel(playerId: String, target: PanelTargetID, pngData: Data) throws {
        try FileManager.default.createDirectory(at: panelsDir(for: playerId),
                                                withIntermediateDirectories: true)
        try pngData.write(to: panelURL(playerId: playerId, target: target), options: .atomic)
    }

    public func loadPanel(playerId: String, target: PanelTargetID) -> Data? {
        try? Data(contentsOf: panelURL(playerId: playerId, target: target))
    }

    public func hasPanel(playerId: String, target: PanelTargetID) -> Bool {
        FileManager.default.fileExists(atPath: panelURL(playerId: playerId, target: target).path)
    }

    // MARK: - Candidate gallery (slice 9, slice 11b unified for cover)

    /// Append a candidate PNG to `_candidates/{NN or cover}/` and return its
    /// assigned index. Indices are dense and monotonically increasing per
    /// target until `acceptCandidate` clears the directory.
    public func savePendingCandidate(playerId: String, target: PanelTargetID,
                                     pngData: Data) throws -> PanelCandidate {
        let dir = candidatesDir(for: playerId, target: target)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let index = nextCandidateIndex(in: dir)
        let url = candidateURL(playerId: playerId, target: target, index: index)
        try pngData.write(to: url, options: .atomic)
        return PanelCandidate(index: index, url: url)
    }

    public func listCandidates(playerId: String, target: PanelTargetID) -> [PanelCandidate] {
        let dir = candidatesDir(for: playerId, target: target)
        let entries = (try? FileManager.default.contentsOfDirectory(at: dir,
                                                                    includingPropertiesForKeys: nil)) ?? []
        return entries
            .compactMap { url -> PanelCandidate? in
                guard let index = Int(url.deletingPathExtension().lastPathComponent) else { return nil }
                return PanelCandidate(index: index, url: url)
            }
            .sorted { $0.index < $1.index }
    }

    /// Promote one candidate to `panel_NN.png` / `cover.png` and discard the
    /// rest of the gallery. After this, `listCandidates(target)` is empty and
    /// `loadPanel(target)` returns the chosen bytes.
    public func acceptCandidate(playerId: String, target: PanelTargetID, candidateIndex: Int) throws {
        let source = candidateURL(playerId: playerId, target: target, index: candidateIndex)
        let data = try Data(contentsOf: source)
        try FileManager.default.createDirectory(at: panelsDir(for: playerId),
                                                withIntermediateDirectories: true)
        try data.write(to: panelURL(playerId: playerId, target: target), options: .atomic)
        try clearCandidates(playerId: playerId, target: target)
    }

    public func deletePanel(playerId: String, target: PanelTargetID) throws {
        let url = panelURL(playerId: playerId, target: target)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    /// Re-roll-after-accept (design memo #3). Moves `panel_NN.png` / `cover.png`
    /// back into the candidate dir as index 0 and removes the accepted file —
    /// the operator's prior choice stays visible in the gallery until they
    /// commit a new winner. If a gallery already exists, prepends to it.
    public func demoteAcceptedToCandidate(playerId: String, target: PanelTargetID) throws {
        let panelFile = panelURL(playerId: playerId, target: target)
        guard FileManager.default.fileExists(atPath: panelFile.path) else { return }
        let bytes = try Data(contentsOf: panelFile)
        let dir = candidatesDir(for: playerId, target: target)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Renumber any existing candidates upward so the demoted prior winner
        // takes index 0 (operators expect it first in the filmstrip).
        let existing = listCandidates(playerId: playerId, target: target)
            .sorted { $0.index > $1.index }
        for candidate in existing {
            let bumped = candidateURL(playerId: playerId, target: target, index: candidate.index + 1)
            try FileManager.default.moveItem(at: candidate.url, to: bumped)
        }
        let demoted = candidateURL(playerId: playerId, target: target, index: 0)
        try bytes.write(to: demoted, options: .atomic)
        try FileManager.default.removeItem(at: panelFile)
    }

    public func attemptsState(playerId: String) -> [PanelAttempt] {
        let url = attemptsURL(playerId: playerId)
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([PanelAttempt].self, from: data)) ?? []
    }

    public func setAttemptsState(playerId: String, attempts: [PanelAttempt]) throws {
        try FileManager.default.createDirectory(at: panelsDir(for: playerId),
                                                withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(attempts)
        try data.write(to: attemptsURL(playerId: playerId), options: .atomic)
    }

    private func clearCandidates(playerId: String, target: PanelTargetID) throws {
        let dir = candidatesDir(for: playerId, target: target)
        if FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.removeItem(at: dir)
        }
    }

    public func capturedRequirements(playerId: String) -> Set<PanelRequirement> {
        let dir = photosDir(for: playerId)
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil)) ?? []
        var out = Set<PanelRequirement>()
        for entry in entries {
            if let req = Self.parseFilename(entry.lastPathComponent) {
                out.insert(req)
            }
        }
        return out
    }

    // MARK: - Filename ↔ requirement (exposed for tests and the UI)

    public static func filename(for requirement: PanelRequirement) -> String {
        "\(requirement.emotion.rawValue)_\(requirement.position.rawValue).jpg"
    }

    public static func parseFilename(_ name: String) -> PanelRequirement? {
        guard name.hasSuffix(".jpg") else { return nil }
        let stem = String(name.dropLast(4))
        let parts = stem.split(separator: "_", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let emotion = Emotion(rawValue: parts[0]),
              let position = Position(rawValue: parts[1]) else { return nil }
        return PanelRequirement(emotion: emotion, position: position)
    }

    // MARK: - Paths

    /// On-disk root for one player — the directory holding `tokens.json`,
    /// `photos/`, `panels/`, and (after `PDFRenderer.render`) `comic.pdf`.
    /// Public so the PDF renderer can pass it as `WKWebView`'s read-access
    /// directory when loading `panels/_render.html`.
    public func playerDirectory(playerId: String) -> URL {
        playerDir(for: playerId)
    }

    /// On-disk address of the finalized comic PDF for one player.
    public func comicURL(playerId: String) -> URL {
        playerDir(for: playerId).appendingPathComponent("comic.pdf")
    }

    /// On-disk address of the `panels/` directory (panels + cover + the
    /// transient `_render.html` written by `PDFRenderer`).
    public func panelsDirectory(playerId: String) -> URL {
        panelsDir(for: playerId)
    }

    private func playerDir(for id: String) -> URL {
        playersDir(in: root).appendingPathComponent(id)
    }

    private func photosDir(for id: String) -> URL {
        playerDir(for: id).appendingPathComponent("photos")
    }

    private func photoURL(playerId: String, requirement: PanelRequirement) -> URL {
        photosDir(for: playerId).appendingPathComponent(Self.filename(for: requirement))
    }

    private func panelsDir(for id: String) -> URL {
        playerDir(for: id).appendingPathComponent("panels")
    }

    private func qaPanelURL(playerId: String) -> URL {
        panelsDir(for: playerId).appendingPathComponent("qa_avatar.png")
    }

    private func panelURL(playerId: String, target: PanelTargetID) -> URL {
        panelsDir(for: playerId).appendingPathComponent("\(target.diskName).png")
    }

    private func attemptsURL(playerId: String) -> URL {
        panelsDir(for: playerId).appendingPathComponent("_attempts.json")
    }

    /// Cover and panels share the parent `_candidates/` dir but get different
    /// stems: `_candidates/07/` for panel 7, `_candidates/cover/` for the
    /// cover. Panel-stem stays zero-padded-N so legacy tests keep working.
    private func candidatesDir(for playerId: String, target: PanelTargetID) -> URL {
        let stem: String = switch target {
        case .panel(let n): String(format: "%02d", n)
        case .cover: "cover"
        }
        return panelsDir(for: playerId)
            .appendingPathComponent("_candidates")
            .appendingPathComponent(stem)
    }

    private func candidateURL(playerId: String, target: PanelTargetID, index: Int) -> URL {
        candidatesDir(for: playerId, target: target)
            .appendingPathComponent(String(format: "%03d.png", index))
    }

    private func nextCandidateIndex(in dir: URL) -> Int {
        let entries = (try? FileManager.default.contentsOfDirectory(at: dir,
                                                                    includingPropertiesForKeys: nil)) ?? []
        let max = entries
            .map { $0.deletingPathExtension().lastPathComponent }
            .compactMap { Int($0) }
            .max()
        return (max ?? -1) + 1
    }

    // MARK: - tokens.json

    private func writeTokens(_ record: PlayerRecord) throws {
        let url = playerDir(for: record.id).appendingPathComponent("tokens.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(record)
        try data.write(to: url, options: .atomic)
    }

    private func readTokens(in playerDir: URL) throws -> PlayerRecord {
        let url = playerDir.appendingPathComponent("tokens.json")
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PlayerRecord.self, from: data)
    }

    // MARK: - Sequential IDs

    private func nextId() throws -> String {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: playersDir(in: root),
            includingPropertiesForKeys: nil)) ?? []
        let max = entries
            .map { $0.lastPathComponent }
            .compactMap { Self.parsePlayerId($0) }
            .max() ?? 0
        return String(format: "player_%03d", max + 1)
    }

    public static func parsePlayerId(_ name: String) -> Int? {
        guard name.hasPrefix("player_") else { return nil }
        return Int(name.dropFirst("player_".count))
    }
}

private func playersDir(in root: URL) -> URL {
    root.appendingPathComponent("players")
}

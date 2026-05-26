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

    // MARK: - Narrative panels (panel_NN.png — slice 8+)

    public func savePanel(playerId: String, n: Int, pngData: Data) throws {
        try FileManager.default.createDirectory(at: panelsDir(for: playerId),
                                                withIntermediateDirectories: true)
        try pngData.write(to: panelURL(playerId: playerId, n: n), options: .atomic)
    }

    public func loadPanel(playerId: String, n: Int) -> Data? {
        try? Data(contentsOf: panelURL(playerId: playerId, n: n))
    }

    public func hasPanel(playerId: String, n: Int) -> Bool {
        FileManager.default.fileExists(atPath: panelURL(playerId: playerId, n: n).path)
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

    private func panelURL(playerId: String, n: Int) -> URL {
        panelsDir(for: playerId).appendingPathComponent(String(format: "panel_%02d.png", n))
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

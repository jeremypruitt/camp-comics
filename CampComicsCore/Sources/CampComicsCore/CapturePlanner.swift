import Foundation

public enum Emotion: String, CaseIterable, Codable, Sendable {
    case neutral, joy, surprise, fear
}

public enum Position: String, CaseIterable, Codable, Sendable {
    case front, profile
}

public struct PanelRequirement: Hashable, Codable, Sendable {
    public let emotion: Emotion
    public let position: Position

    public init(emotion: Emotion, position: Position) {
        self.emotion = emotion
        self.position = position
    }
}

public struct PanelSpec: Equatable, Codable, Sendable {
    public let n: Int
    public let beat: String
    public let emotion: Emotion
    public let position: Position

    public init(n: Int, beat: String, emotion: Emotion, position: Position) {
        self.n = n
        self.beat = beat
        self.emotion = emotion
        self.position = position
    }

    public var requirement: PanelRequirement {
        PanelRequirement(emotion: emotion, position: position)
    }
}

public struct ClassTemplate: Equatable, Codable, Sendable {
    public let classKey: String
    public let name: String
    public let panels: [PanelSpec]
    public let cover: PanelRequirement

    public init(classKey: String, name: String, panels: [PanelSpec], cover: PanelRequirement) {
        self.classKey = classKey
        self.name = name
        self.panels = panels
        self.cover = cover
    }
}

public enum CapturePlanner {
    private static let emotionOrder: [Emotion] = [.neutral, .joy, .surprise, .fear]

    /// Deduplicated union of (emotion, position) requirements drawn from every
    /// panel + the cover, sorted for stable presentation: front-facing shots
    /// first, then profile shots, with emotions ordered neutral → joy →
    /// surprise → fear within each group. Mirrors the prototype's capturePlan().
    public static func plan(for template: ClassTemplate) -> [PanelRequirement] {
        var seen = Set<PanelRequirement>()
        for spec in template.panels { seen.insert(spec.requirement) }
        seen.insert(template.cover)
        return seen.sorted(by: order)
    }

    private static func order(_ a: PanelRequirement, _ b: PanelRequirement) -> Bool {
        if a.position != b.position { return a.position == .front }
        return rank(a.emotion) < rank(b.emotion)
    }

    private static func rank(_ e: Emotion) -> Int {
        emotionOrder.firstIndex(of: e) ?? Int.max
    }
}

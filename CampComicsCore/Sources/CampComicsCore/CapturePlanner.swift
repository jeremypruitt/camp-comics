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
    public let scene: String
    public let composition: String
    public let costumeOverride: String?
    public let styleOverride: String?
    public let referencePanel: Int?
    public let emotion: Emotion
    public let position: Position

    public init(n: Int,
                beat: String,
                scene: String = "",
                composition: String = "",
                costumeOverride: String? = nil,
                styleOverride: String? = nil,
                referencePanel: Int? = nil,
                emotion: Emotion,
                position: Position) {
        self.n = n
        self.beat = beat
        self.scene = scene
        self.composition = composition
        self.costumeOverride = costumeOverride
        self.styleOverride = styleOverride
        self.referencePanel = referencePanel
        self.emotion = emotion
        self.position = position
    }

    public var requirement: PanelRequirement {
        PanelRequirement(emotion: emotion, position: position)
    }
}

public struct Palette: Equatable, Codable, Sendable {
    public let lighting: String
    public let colors: String

    public init(lighting: String, colors: String) {
        self.lighting = lighting
        self.colors = colors
    }
}

/// Cover-only counterpart to `PanelSpec`. The cover is a sibling artifact (not
/// "panel 13" per CONTEXT.md): its prompt skeleton, references, and aspect
/// ratio diverge from the panel path, so it gets its own spec rather than
/// reusing PanelSpec's beat/scene/composition vocabulary.
public struct CoverSpec: Equatable, Codable, Sendable {
    public let requirement: PanelRequirement
    public let poseDirective: String
    public let aspect: String

    public init(requirement: PanelRequirement,
                poseDirective: String,
                aspect: String = "3:4") {
        self.requirement = requirement
        self.poseDirective = poseDirective
        self.aspect = aspect
    }

    public init(emotion: Emotion,
                position: Position,
                poseDirective: String = "",
                aspect: String = "3:4") {
        self.init(requirement: PanelRequirement(emotion: emotion, position: position),
                  poseDirective: poseDirective,
                  aspect: aspect)
    }
}

public struct ClassTemplate: Equatable, Codable, Sendable {
    public let classKey: String
    public let name: String
    public let costume: String
    public let palette: Palette
    public let panels: [PanelSpec]
    public let cover: CoverSpec

    public init(classKey: String,
                name: String,
                costume: String = "",
                palette: Palette = Palette(lighting: "", colors: ""),
                panels: [PanelSpec],
                cover: CoverSpec) {
        self.classKey = classKey
        self.name = name
        self.costume = costume
        self.palette = palette
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
        seen.insert(template.cover.requirement)
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

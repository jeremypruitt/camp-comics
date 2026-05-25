import Foundation

/// User-facing coaching copy for a single (emotion, position) shot.
/// Mirrors the prototype's PROMPTS table (prototype/intake-mobile/index.html).
public struct PromptCopy: Equatable, Sendable {
    public let emoji: String
    public let title: String
    public let subtitle: String

    public init(emoji: String, title: String, subtitle: String) {
        self.emoji = emoji
        self.title = title
        self.subtitle = subtitle
    }
}

public enum PromptCopyBook {
    public static func copy(for requirement: PanelRequirement) -> PromptCopy {
        switch (requirement.emotion, requirement.position) {
        case (.neutral,  .front):   return .init(emoji: "🙂", title: "Neutral, looking at me",    subtitle: "Mouth closed or barely open. Camera at eye level.")
        case (.joy,      .front):   return .init(emoji: "😄", title: "Big smile",                  subtitle: "Teeth showing, eyes a little crinkled. Real joy.")
        case (.fear,     .front):   return .init(emoji: "😨", title: "Worried, wide-eyed",         subtitle: "Like something just went wrong. Eyebrows up.")
        case (.surprise, .front):   return .init(emoji: "😲", title: "Surprised!",                 subtitle: "Like you just saw something you didn't expect.")
        case (.neutral,  .profile): return .init(emoji: "👤", title: "Turn 45° to the side",      subtitle: "Whichever side feels natural. Neutral face.")
        case (.joy,      .profile): return .init(emoji: "😏", title: "Side profile with a smile",  subtitle: "45° turn, slight grin, looking off-camera.")
        case (.fear,     .profile): return .init(emoji: "😟", title: "Side profile, looking off",  subtitle: "45° turn, worried expression.")
        case (.surprise, .profile): return .init(emoji: "😳", title: "Side profile, surprised",    subtitle: "45° turn, brows up.")
        }
    }
}

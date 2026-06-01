import Foundation

/// Slice M (#94, ADR-0010). Caption substitution for the placeholder card
/// primitives: the placeholder shows the YAML caption from t=0 so the operator
/// has something to read during the wait, and `{camper_name}` is the only
/// token the panel captions use today. Mirrors the `tokens:` map the prompt
/// builder threads through, but scoped to the single caption case so view code
/// doesn't take a dependency on the whole prompt-builder surface.
public enum PanelCaption {
    public static func substitute(_ caption: String, playerName: String) -> String {
        caption.replacingOccurrences(of: "{camper_name}", with: playerName)
    }
}

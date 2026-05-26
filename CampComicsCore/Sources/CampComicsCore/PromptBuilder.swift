import Foundation

/// Assembles the Vertex prompt for a panel generation call. Direct port of
/// _legacy/scripts/generate.py:assemble_panel_prompt — the assembled text and
/// trailing STYLE_SUFFIX must match the legacy implementation so iOS-generated
/// panels carry the same anti-drift instructions as the legacy cohort runs.
public enum PromptBuilder {

    /// The canonical anti-drift block. Load-bearing per ADR-0004: face-fidelity
    /// to slot 1 (photo) and costume continuity to slots 2 + 3 (hero + most-
    /// recent approved panel). All caps + recency are deliberate. Do not edit
    /// without a full-cohort regression — see ADR-0004 and the comment at
    /// _legacy/scripts/generate.py:65-80.
    public static let styleSuffix: String =
        "painted digital fantasy illustration, in the style of a Dungeons & "
        + "Dragons 5th Edition sourcebook, cinematic lighting, painterly "
        + "brushwork, high detail on face. No text or letters anywhere in the image. "
        + "ENSURE FACE MATCHES THE ORIGINAL SOURCE PHOTO — the first reference image "
        + "is the canonical identity. Preserve facial structure, eye color and shape, "
        + "nose, jawline, mouth, skin tone, hair color and hairstyle exactly. The "
        + "camper must be instantly recognizable as the same specific person across "
        + "every panel. "
        + "ENSURE CLOTHES MATCH THE PREVIOUS PICTURE — the costume, armor, props, "
        + "and accessories must be identical to those shown in the second reference "
        + "(costume/style anchor) and the third reference if present (the most "
        + "recent approved panel). Do not invent new clothing details, swap colors, "
        + "or restyle existing gear between panels."

    /// Aspect ratio per panel number, mirroring PANEL_ASPECT_RATIOS in
    /// _legacy/scripts/generate.py — driven by panel beat, not class. The CSS
    /// layout in _legacy/layout/comic.css uses matching grid cell shapes.
    public static let panelAspectRatios: [Int: String] = [
        1: "1:1",
        2: "3:4",
        3: "1:1",
        4: "16:9",
        5: "16:9",
        6: "1:1",
        7: "3:4",
        8: "1:1",
        9: "16:9",
        10: "16:9",
        11: "16:9",
        12: "16:9",
    ]

    public static func buildPanelPrompt(spec: PanelSpec,
                                        template: ClassTemplate,
                                        tokens: [String: String]) -> String {
        let scene = interpolate(spec.scene, tokens: tokens)
        let composition = spec.composition
        let costume = template.costume
        let lighting = template.palette.lighting
        let colors = template.palette.colors
        let aspect = panelAspectRatios[spec.n] ?? "4:3"

        return "\(scene). \(composition). "
            + "Costume: \(costume). "
            + "Lighting and color: \(lighting), \(colors). "
            + "Style: \(styleSuffix) "
            + "Image aspect ratio: \(aspect)."
    }

    private static func interpolate(_ template: String, tokens: [String: String]) -> String {
        var result = template
        for (key, value) in tokens {
            result = result.replacingOccurrences(of: "{\(key)}", with: value)
        }
        return result
    }
}

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

    /// Aspect ratio per panel number. Originally mirrored PANEL_ASPECT_RATIOS in
    /// _legacy/scripts/generate.py. ADR-0007 renumbered to 15 panels with two
    /// transition triptychs; the table below reflects the new numbering.
    /// Triptych bookends (3, 5, 12, 14) use 16:9 to match the trapezoid /
    /// pentagon horizontal extent; triptych middles (4, 13) use 1:1 for the
    /// hand/prop close-up framing.
    public static let panelAspectRatios: [Int: String] = [
        1: "1:1",   // everyday kitchen (mirror of new-P15)
        2: "3:4",   // sees-stag TALL PORTRAIT
        3: "16:9",  // P-in left bookend, mid-stride
        4: "1:1",   // P-in middle, hand close-up
        5: "16:9",  // P-in right bookend, mid-stride
        6: "16:9",  // hero splash
        7: "16:9",  // vast forest splash
        8: "1:1",   // mentor + gift handoff close
        9: "3:4",   // obstacle towering
        10: "1:1",  // strain close-up
        11: "16:9", // kneeling cinematic
        12: "16:9", // H-out left bookend, mid-stride
        13: "1:1",  // H-out middle, hand close-up
        14: "16:9", // H-out right bookend, mid-stride
        15: "16:9", // kitchen return splash (wide mirror of P1)
    ]

    /// Slice 11c: the editable section of a target's prompt — everything before
    /// ` Style: \(styleSuffix)…`. Re-prompt prefills the editor with this and
    /// reassembles `preamble + " Style: " + styleSuffix + " Image aspect ratio:
    /// \(aspect)."` on submit. `buildPanelPrompt` and `buildCoverPrompt` also
    /// route through this helper so prefill and final assembly share one path.
    public static func buildPreamble(for target: PanelTarget,
                                     template: ClassTemplate,
                                     tokens: [String: String]) -> String {
        switch target {
        case .panel(_, let spec):
            let scene = interpolate(spec.scene, tokens: tokens)
            let costume = spec.costumeOverride ?? template.costume
            return "\(scene). \(spec.composition). "
                + "Costume: \(costume). "
                + "Lighting and color: \(template.palette.lighting), \(template.palette.colors)."
        case .cover(let spec):
            let name = tokens["camper_name"] ?? ""
            return "\(spec.poseDirective), depicting \(name) as a \(template.name). "
                + "Costume: \(template.costume). "
                + "Lighting and color: \(template.palette.lighting), \(template.palette.colors)."
        }
    }

    /// Unified entry (slice 11b): dispatches to `buildPanelPrompt` for panel
    /// targets and `buildCoverPrompt` for the cover. Callers in the review
    /// loop hold a `PanelTarget` so they don't have to switch on the case.
    ///
    /// Slice F (#66): an optional `addendum` is appended after the fully
    /// assembled prompt — including STYLE_SUFFIX and aspect — separated by a
    /// blank line. Recency wins on the model side, so corrective phrases
    /// ("include a torch") land after the style guidance. The addendum is
    /// per-press: callers never persist it. Whitespace-only / nil → no-op.
    public static func buildPrompt(for target: PanelTarget,
                                   template: ClassTemplate,
                                   tokens: [String: String],
                                   addendum: String? = nil) -> String {
        let base: String
        switch target {
        case .panel(_, let spec):
            base = buildPanelPrompt(spec: spec, template: template, tokens: tokens)
        case .cover(let spec):
            base = buildCoverPrompt(spec: spec, template: template, tokens: tokens)
        }
        guard let trimmed = addendum?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return base }
        return base + "\n\n" + trimmed
    }

    /// Direct port of _legacy/scripts/generate.py:assemble_cover_prompt
    /// (lines 145-156). The cover skips the panel scene/composition vocabulary
    /// and leans on `poseDirective` + `display_name` to set the heroic shot.
    /// STYLE_SUFFIX trails per ADR-0004; the cover doesn't append anything
    /// after it (no style_override on the cover).
    public static func buildCoverPrompt(spec: CoverSpec,
                                        template: ClassTemplate,
                                        tokens: [String: String]) -> String {
        let preamble = buildPreamble(for: .cover(spec: spec),
                                     template: template,
                                     tokens: tokens)
        return preamble + " Style: \(styleSuffix) Image aspect ratio: \(spec.aspect)."
    }

    public static func buildPanelPrompt(spec: PanelSpec,
                                        template: ClassTemplate,
                                        tokens: [String: String]) -> String {
        let preamble = buildPreamble(for: .panel(n: spec.n, spec: spec),
                                     template: template,
                                     tokens: tokens)
        let aspect = panelAspectRatios[spec.n] ?? "4:3"
        let styleBlock = spec.styleOverride.map { "\(styleSuffix) \($0)" } ?? styleSuffix
        return preamble + " Style: \(styleBlock) Image aspect ratio: \(aspect)."
    }

    private static func interpolate(_ template: String, tokens: [String: String]) -> String {
        var result = template
        for (key, value) in tokens {
            result = result.replacingOccurrences(of: "{\(key)}", with: value)
        }
        return result
    }
}

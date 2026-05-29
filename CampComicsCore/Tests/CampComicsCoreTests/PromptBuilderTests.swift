import Testing
@testable import CampComicsCore

@Suite("PromptBuilder")
struct PromptBuilderTests {

    // The legacy STYLE_SUFFIX block, lifted verbatim from
    // _legacy/scripts/generate.py:66-80. ADR-0004 makes this load-bearing —
    // the iOS port must produce the same string character-for-character so
    // generated panels carry the same anti-drift instructions as the legacy
    // cohort runs. If you find yourself wanting to edit STYLE_SUFFIX, read
    // ADR-0004 first.
    static let legacyStyleSuffix: String =
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

    @Test func styleSuffixMatchesLegacyVerbatim() {
        #expect(PromptBuilder.styleSuffix == Self.legacyStyleSuffix)
    }

    @Test func interpolatesTokensInScene() {
        // The YAML scene field carries {token} placeholders — the legacy
        // python uses .format(**tokens) to substitute. iOS must do the same
        // so panel 1's "{camper_name} in modern everyday clothes" comes out
        // as "Alex in modern everyday clothes" before assembling the prompt.
        let spec = PanelSpec(
            n: 1,
            beat: "It was Tuesday.",
            scene: "{camper_name} in modern everyday clothes, holding {prop}",
            composition: "intimate medium shot",
            emotion: .neutral,
            position: .front
        )
        let prompt = PromptBuilder.buildPanelPrompt(
            spec: spec,
            template: Self.druidTemplate,
            tokens: ["camper_name": "Alex", "prop": "a mug"]
        )
        #expect(prompt.contains("Alex in modern everyday clothes, holding a mug"))
        #expect(!prompt.contains("{camper_name}"))
        #expect(!prompt.contains("{prop}"))
    }

    @Test func panelPromptMatchesLegacyFormat() {
        // Mirrors _legacy/scripts/generate.py:assemble_panel_prompt. The text
        // join — periods + spaces, "Costume:", "Lighting and color:", "Style:",
        // "Image aspect ratio:" — is part of the prompt's actual behavior on
        // the model side; deviating from the legacy format means iOS-generated
        // panels carry different instructions than the legacy cohort runs.
        let spec = PanelSpec(
            n: 1,
            beat: "It was Tuesday.",
            scene: "{camper_name} stands in a kitchen",
            composition: "intimate medium shot, centered",
            emotion: .neutral,
            position: .front
        )
        let prompt = PromptBuilder.buildPanelPrompt(
            spec: spec,
            template: Self.druidTemplate,
            tokens: ["camper_name": "Alex"]
        )

        let expected = "Alex stands in a kitchen. intimate medium shot, centered. "
            + "Costume: weathered leather and bark armor. "
            + "Lighting and color: warm golden-hour, deep mossy greens. "
            + "Style: \(PromptBuilder.styleSuffix) "
            + "Image aspect ratio: 1:1."
        #expect(prompt == expected)
    }

    @Test func costumeOverrideReplacesClassCostume() {
        // Panel-1 and panel-12 carry costume_override to peel the class
        // fantasy costume off pre-quest / return-home beats. Without this
        // the Costume: line + hero ref would override the scene's "everyday
        // clothes" cue (legacy generate.py:131).
        let spec = PanelSpec(
            n: 1,
            beat: "Tuesday.",
            scene: "Alex in a kitchen",
            composition: "wide",
            costumeOverride: "ordinary modern everyday clothes from the photo",
            emotion: .neutral,
            position: .front
        )
        let prompt = PromptBuilder.buildPanelPrompt(
            spec: spec, template: Self.druidTemplate, tokens: [:]
        )
        #expect(prompt.contains("Costume: ordinary modern everyday clothes from the photo."))
        #expect(!prompt.contains("Costume: weathered leather and bark armor"))
    }

    @Test func styleOverrideAppendsAfterStyleSuffix() {
        // style_override piggy-backs after STYLE_SUFFIX so recency lets it
        // win over the "match second reference" instruction baked into the
        // suffix (legacy generate.py:133-134). Panel 1 uses this to point
        // the model at the FIRST reference photo instead of the hero card.
        let spec = PanelSpec(
            n: 1,
            beat: "Tuesday.",
            scene: "Alex in a kitchen",
            composition: "wide",
            styleOverride: "OVERRIDE: match the FIRST reference, not the second.",
            emotion: .neutral,
            position: .front
        )
        let prompt = PromptBuilder.buildPanelPrompt(
            spec: spec, template: Self.druidTemplate, tokens: [:]
        )
        let expectedStyleBlock =
            PromptBuilder.styleSuffix + " OVERRIDE: match the FIRST reference, not the second."
        #expect(prompt.contains("Style: \(expectedStyleBlock)"))
    }

    @Test func coverPromptMatchesLegacyFormat() {
        // Slice 11b: ports assemble_cover_prompt from
        // _legacy/scripts/generate.py:145-156 verbatim. STYLE_SUFFIX MUST
        // trail per ADR-0004 — anything after it wins on recency, and the
        // cover doesn't override face/costume guidance.
        let coverSpec = CoverSpec(
            emotion: .neutral,
            position: .profile,
            poseDirective: "heroic full-body portrait in full druid regalia"
        )
        let template = ClassTemplate(
            classKey: "druid",
            name: "Druid",
            costume: "weathered leather and bark armor",
            palette: Palette(lighting: "warm golden-hour", colors: "deep mossy greens"),
            panels: [],
            cover: coverSpec
        )

        let prompt = PromptBuilder.buildPrompt(
            for: .cover(spec: coverSpec),
            template: template,
            tokens: ["camper_name": "Alex"]
        )

        let expected =
            "heroic full-body portrait in full druid regalia, depicting Alex as a Druid. "
            + "Costume: weathered leather and bark armor. "
            + "Lighting and color: warm golden-hour, deep mossy greens. "
            + "Style: \(PromptBuilder.styleSuffix) "
            + "Image aspect ratio: 3:4."
        #expect(prompt == expected)
    }

    @Test func panelTargetEntryMatchesPanelPromptForPanelCase() {
        // The unified buildPrompt(for: PanelTarget) entry produces the same
        // text as the existing panel-only path for the .panel(n:spec:) case.
        let spec = PanelSpec(n: 1, beat: "Tuesday.",
                             scene: "Alex stands in a kitchen",
                             composition: "intimate medium shot, centered",
                             emotion: .neutral, position: .front)

        let direct = PromptBuilder.buildPanelPrompt(
            spec: spec, template: Self.druidTemplate, tokens: ["camper_name": "Alex"]
        )
        let unified = PromptBuilder.buildPrompt(
            for: .panel(n: 1, spec: spec),
            template: Self.druidTemplate,
            tokens: ["camper_name": "Alex"]
        )

        #expect(direct == unified)
    }

    private static let druidTemplate = ClassTemplate(
        classKey: "druid",
        name: "Druid",
        costume: "weathered leather and bark armor",
        palette: Palette(lighting: "warm golden-hour", colors: "deep mossy greens"),
        panels: [],
        cover: CoverSpec(emotion: .neutral, position: .profile)
    )
}

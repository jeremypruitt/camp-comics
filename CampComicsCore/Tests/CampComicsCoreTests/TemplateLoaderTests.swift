import Foundation
import Testing
@testable import CampComicsCore

@Suite("TemplateLoader")
struct TemplateLoaderTests {

    /// Trimmed-down druid YAML in the canonical shape: class identity + 12
    /// panels (each with emotion + position) + cover with emotion + position.
    /// Mirrors templates/druid.yaml — kept compact so the test stays focused on
    /// parser behavior, not prose drift.
    static let druidYAML = """
    class: druid
    display_name: Druid
    palette:
      lighting: warm
      colors: green
    costume: bark armor
    hero_card_reference: refs/druid_hero.png

    panels:
      - n: 1
        emotion: neutral
        position: front
        caption: Everyday self
      - n: 2
        emotion: surprise
        position: front
        caption: Stag appears
      - n: 3
        emotion: neutral
        position: front
        caption: Hand transforming
      - n: 4
        emotion: joy
        position: front
        caption: Hero reveal
      - n: 5
        emotion: neutral
        position: profile
        caption: Vast forest realm
      - n: 6
        emotion: neutral
        position: front
        caption: Tree spirit guide
      - n: 7
        emotion: fear
        position: front
        caption: Fear made manifest
      - n: 8
        emotion: fear
        position: front
        caption: First attempt fails
      - n: 9
        emotion: neutral
        position: front
        caption: Kneel, listen
      - n: 10
        emotion: joy
        position: profile
        caption: Walking past obstacle
      - n: 11
        emotion: neutral
        position: front
        caption: Receiving the reward
      - n: 12
        emotion: joy
        position: front
        caption: Return home

    cover:
      emotion: neutral
      position: profile
      pose_directive: heroic stance

    fallbacks:
      1: anything
    """

    @Test func parsesClassIdentityAndPanelCount() throws {
        let template = try TemplateLoader.load(yaml: Self.druidYAML)

        #expect(template.classKey == "druid")
        #expect(template.name == "Druid")
        #expect(template.panels.count == 12)
    }

    @Test func parsesEveryPanelEmotionAndPosition() throws {
        let template = try TemplateLoader.load(yaml: Self.druidYAML)
        let expected: [(Int, Emotion, Position)] = [
            (1,  .neutral,  .front),
            (2,  .surprise, .front),
            (3,  .neutral,  .front),
            (4,  .joy,      .front),
            (5,  .neutral,  .profile),
            (6,  .neutral,  .front),
            (7,  .fear,     .front),
            (8,  .fear,     .front),
            (9,  .neutral,  .front),
            (10, .joy,      .profile),
            (11, .neutral,  .front),
            (12, .joy,      .front),
        ]

        for (i, spec) in template.panels.enumerated() {
            let (n, emotion, position) = expected[i]
            #expect(spec.n == n)
            #expect(spec.emotion == emotion)
            #expect(spec.position == position)
        }
    }

    @Test func parsesCoverRequirement() throws {
        let template = try TemplateLoader.load(yaml: Self.druidYAML)

        #expect(template.cover.emotion == .neutral)
        #expect(template.cover.position == .profile)
    }

    @Test func parsesPaletteAndCostume() throws {
        // Slice 8: PromptBuilder folds palette.lighting, palette.colors, and
        // the class-level costume into the assembled panel prompt. They have
        // to survive the YAML round-trip onto ClassTemplate.
        let yaml = """
        class: druid
        display_name: Druid
        palette:
          lighting: warm golden-hour light
          colors: deep mossy greens
        costume: weathered leather and bark armor
        panels:
          - n: 1
            emotion: neutral
            position: front
            caption: Tuesday
        cover:
          emotion: neutral
          position: profile
          pose_directive: heroic
        """
        let template = try TemplateLoader.load(yaml: yaml)
        #expect(template.palette.lighting == "warm golden-hour light")
        #expect(template.palette.colors == "deep mossy greens")
        #expect(template.costume == "weathered leather and bark armor")
    }

    @Test func parsesPanelOverrides() throws {
        // costume_override + style_override are panel-level prompt switches
        // used for transition-out (panel 12, return-home) and transition-in
        // (panel 1, pre-quest). Both default to nil. PromptBuilder consumes
        // them to peel the class costume / hero ref off a specific panel.
        let yaml = """
        class: druid
        display_name: Druid
        palette:
          lighting: warm
          colors: green
        costume: bark armor
        panels:
          - n: 1
            emotion: neutral
            position: front
            scene: "scene"
            composition: "comp"
            caption: Tuesday
            costume_override: "everyday clothes from the photo"
            style_override: "OVERRIDE: pre-transformation, photo wins."
          - n: 2
            emotion: surprise
            position: front
            scene: "scene"
            composition: "comp"
            caption: Stag
        cover:
          emotion: neutral
          position: profile
          pose_directive: heroic
        """
        let template = try TemplateLoader.load(yaml: yaml)
        #expect(template.panels[0].costumeOverride == "everyday clothes from the photo")
        #expect(template.panels[0].styleOverride == "OVERRIDE: pre-transformation, photo wins.")
        #expect(template.panels[1].costumeOverride == nil)
        #expect(template.panels[1].styleOverride == nil)
    }

    @Test func parsesReferencePanelOverrideFromQuotedString() throws {
        // Legacy YAML stores reference_panel as a zero-padded quoted string
        // (e.g. "01") so the legacy generate.py can pattern-match the
        // `panel_NN.png` filename. The iOS app's PhotoReferenceResolver wants
        // it as an Int. Loader normalizes the form.
        let yaml = """
        class: druid
        display_name: Druid
        palette:
          lighting: warm
          colors: green
        costume: bark armor
        panels:
          - n: 1
            emotion: neutral
            position: front
            caption: Tuesday
          - n: 12
            emotion: joy
            position: front
            caption: Return home
            reference_panel: "01"
        cover:
          emotion: neutral
          position: profile
          pose_directive: heroic
        """
        let template = try TemplateLoader.load(yaml: yaml)
        #expect(template.panels[0].referencePanel == nil)
        #expect(template.panels[1].referencePanel == 1)
    }

    @Test func parsesSceneAndComposition() throws {
        // Slice 8: PromptBuilder needs scene (with {token} placeholders) and
        // composition on every PanelSpec to assemble the legacy panel prompt.
        let yaml = """
        class: druid
        display_name: Druid
        palette:
          lighting: warm
          colors: green
        costume: bark armor
        panels:
          - n: 1
            emotion: neutral
            position: front
            scene: "{camper_name} stands in a kitchen on Tuesday"
            composition: "intimate eye-level medium shot, centered"
            caption: Tuesday
        cover:
          emotion: neutral
          position: profile
          pose_directive: heroic
        """
        let template = try TemplateLoader.load(yaml: yaml)
        #expect(template.panels[0].scene == "{camper_name} stands in a kitchen on Tuesday")
        #expect(template.panels[0].composition == "intimate eye-level medium shot, centered")
    }

    @Test func loadedTemplateFeedsCapturePlannerCleanly() throws {
        let template = try TemplateLoader.load(yaml: Self.druidYAML)
        let plan = CapturePlanner.plan(for: template)

        // Druid touches: neutral|front, joy|front, surprise|front, fear|front,
        // neutral|profile, joy|profile (cover collapses into neutral|profile).
        #expect(plan == [
            PanelRequirement(emotion: .neutral,  position: .front),
            PanelRequirement(emotion: .joy,      position: .front),
            PanelRequirement(emotion: .surprise, position: .front),
            PanelRequirement(emotion: .fear,     position: .front),
            PanelRequirement(emotion: .neutral,  position: .profile),
            PanelRequirement(emotion: .joy,      position: .profile),
        ])
    }

    @Test func rejectsMalformedYAML() {
        let bogus = "class: druid\npanels: nope"
        #expect(throws: TemplateLoaderError.self) {
            try TemplateLoader.load(yaml: bogus)
        }
    }

    // MARK: - On-disk class YAMLs
    //
    // The five non-druid templates were retrofitted with (emotion, position) per
    // panel + cover in this slice. These tests load the real files from
    // templates/ at the repo root (resolved relative to this test source file)
    // and verify the structural shape — count, cover, and the two profile-shot
    // anchor panels (5 and 10) that drive the capture plan's "front + profile"
    // photo set.

    @Test func loadsWarriorYAML() throws {
        try assertCanonicalArc(classKey: "warrior", displayName: "Warrior")
    }

    @Test func loadsWizardYAML() throws {
        try assertCanonicalArc(classKey: "wizard", displayName: "Wizard")
    }

    @Test func loadsBardYAML() throws {
        try assertCanonicalArc(classKey: "bard", displayName: "Bard")
    }

    @Test func loadsHealerYAML() throws {
        try assertCanonicalArc(classKey: "healer", displayName: "Healer")
    }

    @Test func loadsTricksterYAML() throws {
        try assertCanonicalArc(classKey: "trickster", displayName: "Trickster")
    }

    @Test func loadsDruidYAMLFromDisk() throws {
        try assertCanonicalArc(classKey: "druid", displayName: "Druid")
    }

    @Test func druidPanel12LoadsReferencePanelOverrideOne() throws {
        let yaml = try loadTemplateYAML(classKey: "druid")
        let template = try TemplateLoader.load(yaml: yaml)
        let panel12 = template.panels.first(where: { $0.n == 12 })

        #expect(panel12?.referencePanel == 1)
    }

    /// All six class arcs share the same emotion/position structure (they're
    /// clones of druid.yaml). A failure here means a YAML drifted off-pattern
    /// or didn't get its emotion/position fields.
    private func assertCanonicalArc(classKey: String, displayName: String) throws {
        let yaml = try loadTemplateYAML(classKey: classKey)
        let template = try TemplateLoader.load(yaml: yaml)

        #expect(template.classKey == classKey)
        #expect(template.name == displayName)
        #expect(template.panels.count == 12)

        let expected: [(Int, Emotion, Position)] = [
            (1,  .neutral,  .front),
            (2,  .surprise, .front),
            (3,  .neutral,  .front),
            (4,  .joy,      .front),
            (5,  .neutral,  .profile),
            (6,  .neutral,  .front),
            (7,  .fear,     .front),
            (8,  .fear,     .front),
            (9,  .neutral,  .front),
            (10, .joy,      .profile),
            (11, .neutral,  .front),
            (12, .joy,      .front),
        ]
        for (i, spec) in template.panels.enumerated() {
            let (n, emotion, position) = expected[i]
            #expect(spec.n == n)
            #expect(spec.emotion == emotion)
            #expect(spec.position == position)
        }

        #expect(template.cover.emotion == .neutral)
        #expect(template.cover.position == .profile)
    }

    private func loadTemplateYAML(classKey: String,
                                  file: StaticString = #filePath) throws -> String {
        // #filePath points at this test source file. Walk up to the repo root
        // and read templates/{class}.yaml from there.
        let testFile = URL(fileURLWithPath: String(describing: file))
        let repoRoot = testFile
            .deletingLastPathComponent()  // CampComicsCoreTests/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // CampComicsCore/
            .deletingLastPathComponent()  // repo root
        let yamlURL = repoRoot
            .appendingPathComponent("templates", isDirectory: true)
            .appendingPathComponent("\(classKey).yaml")
        return try String(contentsOf: yamlURL, encoding: .utf8)
    }
}

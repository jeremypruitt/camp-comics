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
}

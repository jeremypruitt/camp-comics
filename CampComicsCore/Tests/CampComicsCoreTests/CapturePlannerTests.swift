import Testing
import Foundation
@testable import CampComicsCore

@Suite("CapturePlanner")
struct CapturePlannerTests {

    // The prototype's hand-tagged druid template — known good reference.
    // 12 panels + 1 cover collapse to exactly 6 shots in a specific order.
    @Test func druidTemplateDedupsToSixShotsInFrontThenProfileOrder() {
        let plan = CapturePlanner.plan(for: druidTemplate())

        #expect(plan.count == 6)
        #expect(plan == [
            PanelRequirement(emotion: .neutral,  position: .front),
            PanelRequirement(emotion: .joy,      position: .front),
            PanelRequirement(emotion: .surprise, position: .front),
            PanelRequirement(emotion: .fear,     position: .front),
            PanelRequirement(emotion: .neutral,  position: .profile),
            PanelRequirement(emotion: .joy,      position: .profile),
        ])
    }

    // The wizard template has every panel as neutral|front except #2 (surprise),
    // #4 + #10 (joy), and cover neutral|profile → 3 front shots + 1 profile.
    @Test func wizardTemplateDedupsToFourShots() {
        let plan = CapturePlanner.plan(for: wizardTemplate())

        #expect(plan == [
            PanelRequirement(emotion: .neutral,  position: .front),
            PanelRequirement(emotion: .joy,      position: .front),
            PanelRequirement(emotion: .surprise, position: .front),
            PanelRequirement(emotion: .neutral,  position: .profile),
        ])
    }

    // Minimum case: a single panel that matches the cover.
    @Test func singlePanelMatchingCoverYieldsOneShot() {
        let template = ClassTemplate(
            classKey: "minimal",
            name: "Minimal",
            panels: [PanelSpec(n: 1, beat: "only", emotion: .neutral, position: .front)],
            cover: CoverSpec(emotion: .neutral, position: .front)
        )

        #expect(CapturePlanner.plan(for: template) ==
            [PanelRequirement(emotion: .neutral, position: .front)]
        )
    }

    // Cover requirements always join the plan even if no panel covers them.
    @Test func coverRequirementAlwaysIncludedEvenIfNoPanelHasIt() {
        let template = ClassTemplate(
            classKey: "front-only",
            name: "Front Only",
            panels: [PanelSpec(n: 1, beat: "x", emotion: .neutral, position: .front)],
            cover: CoverSpec(emotion: .joy, position: .profile)
        )

        #expect(CapturePlanner.plan(for: template) == [
            PanelRequirement(emotion: .neutral, position: .front),
            PanelRequirement(emotion: .joy,     position: .profile),
        ])
    }

    // Sort is purely positional/emotional — never dependent on panel input order.
    @Test func planOrderIsStableRegardlessOfInputOrder() {
        let scrambled = ClassTemplate(
            classKey: "scrambled",
            name: "Scrambled",
            panels: [
                PanelSpec(n: 1, beat: "a", emotion: .fear,     position: .profile),
                PanelSpec(n: 2, beat: "b", emotion: .joy,      position: .front),
                PanelSpec(n: 3, beat: "c", emotion: .surprise, position: .front),
                PanelSpec(n: 4, beat: "d", emotion: .neutral,  position: .profile),
                PanelSpec(n: 5, beat: "e", emotion: .neutral,  position: .front),
            ],
            cover: CoverSpec(emotion: .joy, position: .profile)
        )

        #expect(CapturePlanner.plan(for: scrambled) == [
            PanelRequirement(emotion: .neutral,  position: .front),
            PanelRequirement(emotion: .joy,      position: .front),
            PanelRequirement(emotion: .surprise, position: .front),
            PanelRequirement(emotion: .neutral,  position: .profile),
            PanelRequirement(emotion: .joy,      position: .profile),
            PanelRequirement(emotion: .fear,     position: .profile),
        ])
    }

    // Duplicate panel requirements never produce duplicate shots.
    @Test func duplicatePanelsCollapseToSingleRequirement() {
        let template = ClassTemplate(
            classKey: "dup",
            name: "Dup",
            panels: Array(repeating:
                PanelSpec(n: 1, beat: "x", emotion: .joy, position: .front),
                count: 5
            ),
            cover: CoverSpec(emotion: .joy, position: .front)
        )

        #expect(CapturePlanner.plan(for: template) ==
            [PanelRequirement(emotion: .joy, position: .front)]
        )
    }

    // ClassTemplate round-trips through Codable so YAML/JSON loading stays viable.
    @Test func classTemplateRoundTripsThroughJSON() throws {
        let original = druidTemplate()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ClassTemplate.self, from: data)
        #expect(decoded == original)
    }
}

// MARK: - Fixtures (mirror prototype/intake-mobile/index.html TEMPLATES)

private func druidTemplate() -> ClassTemplate {
    ClassTemplate(
        classKey: "druid",
        name: "Druid",
        panels: [
            PanelSpec(n: 1,  beat: "Everyday self",         emotion: .neutral,  position: .front),
            PanelSpec(n: 2,  beat: "Stag of stars appears", emotion: .surprise, position: .front),
            PanelSpec(n: 3,  beat: "Hand transforming",     emotion: .neutral,  position: .front),
            PanelSpec(n: 4,  beat: "Hero reveal",           emotion: .joy,      position: .front),
            PanelSpec(n: 5,  beat: "Vast forest realm",     emotion: .neutral,  position: .profile),
            PanelSpec(n: 6,  beat: "Tree spirit guide",     emotion: .neutral,  position: .front),
            PanelSpec(n: 7,  beat: "Fear made manifest",    emotion: .fear,     position: .front),
            PanelSpec(n: 8,  beat: "First attempt fails",   emotion: .fear,     position: .front),
            PanelSpec(n: 9,  beat: "Kneel, listen",         emotion: .neutral,  position: .front),
            PanelSpec(n: 10, beat: "Walking past obstacle", emotion: .joy,      position: .profile),
            PanelSpec(n: 11, beat: "Receiving the reward",  emotion: .neutral,  position: .front),
            PanelSpec(n: 12, beat: "Return home",           emotion: .joy,      position: .front),
        ],
        cover: CoverSpec(emotion: .neutral, position: .profile)
    )
}

private func wizardTemplate() -> ClassTemplate {
    ClassTemplate(
        classKey: "wizard",
        name: "Wizard",
        panels: [
            PanelSpec(n: 1,  beat: "Everyday self",        emotion: .neutral,  position: .front),
            PanelSpec(n: 2,  beat: "A question intrudes", emotion: .surprise, position: .front),
            PanelSpec(n: 3,  beat: "First spell flickers", emotion: .neutral,  position: .front),
            PanelSpec(n: 4,  beat: "Hero reveal",          emotion: .joy,      position: .front),
            PanelSpec(n: 5,  beat: "The grand library",    emotion: .neutral,  position: .front),
            PanelSpec(n: 6,  beat: "The old master",       emotion: .neutral,  position: .front),
            PanelSpec(n: 7,  beat: "Riddle appears",       emotion: .neutral,  position: .front),
            PanelSpec(n: 8,  beat: "Arrogance fails",      emotion: .neutral,  position: .front),
            PanelSpec(n: 9,  beat: "Humble study",         emotion: .neutral,  position: .front),
            PanelSpec(n: 10, beat: "Eureka",               emotion: .joy,      position: .front),
            PanelSpec(n: 11, beat: "The bound tome",       emotion: .neutral,  position: .front),
            PanelSpec(n: 12, beat: "Return, wiser",        emotion: .neutral,  position: .front),
        ],
        cover: CoverSpec(emotion: .neutral, position: .profile)
    )
}

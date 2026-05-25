import CampComicsCore

// For the first vertical slice the app drives off a hand-built druid template.
// The YAML loader exists in CampComicsCore; wiring it to Bundle.main and shipping
// templates/*.yaml as bundle resources lands in a later slice.
enum BundledTemplates {
    static let druid = ClassTemplate(
        classKey: "druid",
        name: "Druid",
        panels: [
            PanelSpec(n: 1,  beat: "Everyday self",          emotion: .neutral,  position: .front),
            PanelSpec(n: 2,  beat: "Stag of stars appears",  emotion: .surprise, position: .front),
            PanelSpec(n: 3,  beat: "Hand transforming",      emotion: .neutral,  position: .front),
            PanelSpec(n: 4,  beat: "Hero reveal",            emotion: .joy,      position: .front),
            PanelSpec(n: 5,  beat: "Vast forest realm",      emotion: .neutral,  position: .profile),
            PanelSpec(n: 6,  beat: "Tree spirit guide",      emotion: .neutral,  position: .front),
            PanelSpec(n: 7,  beat: "Fear made manifest",     emotion: .fear,     position: .front),
            PanelSpec(n: 8,  beat: "First attempt fails",    emotion: .fear,     position: .front),
            PanelSpec(n: 9,  beat: "Kneel, listen",          emotion: .neutral,  position: .front),
            PanelSpec(n: 10, beat: "Walking past obstacle",  emotion: .joy,      position: .profile),
            PanelSpec(n: 11, beat: "Receiving the reward",   emotion: .neutral,  position: .front),
            PanelSpec(n: 12, beat: "Return home",            emotion: .joy,      position: .front),
        ],
        cover: PanelRequirement(emotion: .neutral, position: .profile)
    )

    static func template(forClassKey key: String) -> ClassTemplate {
        druid
    }
}

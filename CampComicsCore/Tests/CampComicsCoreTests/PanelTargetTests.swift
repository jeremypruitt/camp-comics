import Testing
@testable import CampComicsCore

@Suite("PanelTarget")
struct PanelTargetTests {

    private static let spec = PanelSpec(n: 7, beat: "x", emotion: .neutral, position: .front)
    private static let cover = CoverSpec(emotion: .neutral, position: .profile, poseDirective: "p")

    @Test func panelDiskNameIsZeroPadded() {
        #expect(PanelTarget.panel(n: 7, spec: Self.spec).diskName == "panel_07")
        #expect(PanelTarget.panel(n: 12, spec: Self.spec).diskName == "panel_12")
    }

    @Test func coverDiskNameIsLiteralCover() {
        #expect(PanelTarget.cover(spec: Self.cover).diskName == "cover")
    }
}

import Foundation
import Testing
@testable import CampComicsCore

@Suite("HTMLAssembler")
struct HTMLAssemblerTests {

    private static func player(characterName: String = "Faeloria") -> PlayerRecord {
        PlayerRecord(id: "player_001",
                     playerName: "Alex",
                     characterName: characterName,
                     classKey: "druid",
                     createdAt: Date(timeIntervalSince1970: 0))
    }

    private static func template() -> ClassTemplate {
        let panels = (1...12).map { n in
            PanelSpec(n: n,
                      beat: "Beat \(n) caption",
                      emotion: .neutral,
                      position: .front)
        }
        let cover = CoverSpec(emotion: .neutral, position: .profile)
        return ClassTemplate(classKey: "druid", name: "Druid", panels: panels, cover: cover)
    }

    @Test func outputContainsCoverSection() {
        let html = HTMLAssembler.assemble(player: Self.player(), template: Self.template())
        #expect(html.contains(#"<section class="page cover">"#))
    }

    @Test func outputContainsCharacterName() {
        let html = HTMLAssembler.assemble(player: Self.player(characterName: "Faeloria"),
                                          template: Self.template())
        #expect(html.contains("Faeloria"))
    }

    @Test func eachPanelFilenameAppearsInExpectedActBlock() {
        let html = HTMLAssembler.assemble(player: Self.player(), template: Self.template())
        for n in 1...12 {
            let act = (n - 1) / 4 + 1
            let filename = String(format: "panel_%02d.png", n)
            let block = actBlock(in: html, act: act)
            #expect(block.contains(filename),
                    "expected \(filename) inside page-act-\(act) block")
        }
    }

    @Test func actThreeDiagonalPairUsesCSSClipPath() {
        let html = HTMLAssembler.assemble(player: Self.player(), template: Self.template())
        let act3 = actBlock(in: html, act: 3)
        #expect(act3.contains(#"class="diag-left""#))
        #expect(act3.contains(#"class="diag-right""#))
        #expect(html.contains(".diag-left"))
        #expect(html.contains(".diag-right"))
        #expect(html.contains("clip-path: polygon("))
    }

    @Test func eachPanelBeatAppearsInOutput() {
        let html = HTMLAssembler.assemble(player: Self.player(), template: Self.template())
        for n in 1...12 {
            #expect(html.contains("Beat \(n) caption"), "missing caption for panel \(n)")
        }
    }

    @Test func coverImageFilenameAppearsInCoverBlock() {
        let html = HTMLAssembler.assemble(player: Self.player(), template: Self.template())
        let cover = coverBlock(in: html)
        #expect(cover.contains("cover.png"))
    }

    /// WKWebView's 980 CSS-px default viewport leaves a ~30% white column on
    /// the right of every page (issue #25). The viewport meta tag pins the
    /// rendering width to the actual page width — 6.625in × 96 CSS px/in = 636.
    @Test func headContainsViewportMetaPinnedToPageWidth() {
        let html = HTMLAssembler.assemble(player: Self.player(), template: Self.template())
        #expect(html.contains(#"<meta name="viewport" content="width=636">"#))
    }

    private func coverBlock(in html: String) -> Substring {
        guard let openRange = html.range(of: #"<section class="page cover">"#) else { return "" }
        let after = html[openRange.upperBound...]
        guard let closeRange = after.range(of: "</section>") else { return after }
        return after[..<closeRange.lowerBound]
    }

    private func actBlock(in html: String, act: Int) -> Substring {
        let openMarker = #"<section class="page interior page-act-\#(act)">"#
        guard let openRange = html.range(of: openMarker) else { return "" }
        let after = html[openRange.upperBound...]
        guard let closeRange = after.range(of: "</section>") else { return after }
        return after[..<closeRange.lowerBound]
    }
}

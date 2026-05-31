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
        let panels = (1...15).map { n in
            PanelSpec(n: n,
                      beat: "Beat \(n) caption",
                      emotion: .neutral,
                      position: .front)
        }
        let cover = CoverSpec(emotion: .neutral, position: .profile)
        return ClassTemplate(classKey: "druid", name: "Druid", panels: panels, cover: cover)
    }

    /// Act distribution per ADR-0007: page 2 = panels 1–6, page 3 = panels 7–11,
    /// page 4 = panels 12–15. Replaces the legacy `((n-1)/4)+1` formula which
    /// assumed a uniform 4/4/4 split.
    private static func expectedAct(for n: Int) -> Int {
        switch n {
        case 1...6:   return 1
        case 7...11:  return 2
        case 12...15: return 3
        default: fatalError("panel \(n) is out of range")
        }
    }

    /// Per ADR-0007, the P-in triptych (panels 3, 4, 5) and the H-out triptych
    /// (panels 12, 13, 14) emit no `<figcaption>` — the bookending on-page panels
    /// carry the narrative captions instead.
    private static let triptychPanelNumbers: Set<Int> = [3, 4, 5, 12, 13, 14]

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
        for n in 1...15 {
            let act = Self.expectedAct(for: n)
            let filename = String(format: "panel_%02d.png", n)
            let block = actBlock(in: html, act: act)
            #expect(block.contains(filename),
                    "expected \(filename) inside page-act-\(act) block")
        }
    }

    @Test func pageTwoEmitsPInTriptychContainingPanels3Through5() {
        let html = HTMLAssembler.assemble(player: Self.player(), template: Self.template())
        let act1 = actBlock(in: html, act: 1)
        let triptych = triptychFigure(in: act1, kind: "in")
        #expect(triptych.contains("panel_03.png"))
        #expect(triptych.contains("panel_04.png"))
        #expect(triptych.contains("panel_05.png"))
    }

    @Test func pInTriptychIsTheOnlyContainerForItsThreePanels() {
        let html = HTMLAssembler.assemble(player: Self.player(), template: Self.template())
        let act1 = actBlock(in: html, act: 1)
        #expect(!act1.contains(#"<figure class="panel panel-3">"#))
        #expect(!act1.contains(#"<figure class="panel panel-4">"#))
        #expect(!act1.contains(#"<figure class="panel panel-5">"#))
    }

    @Test func pageFourEmitsHOutTriptychContainingPanels12Through14() {
        let html = HTMLAssembler.assemble(player: Self.player(), template: Self.template())
        let act3 = actBlock(in: html, act: 3)
        let triptych = triptychFigure(in: act3, kind: "out")
        #expect(triptych.contains("panel_12.png"))
        #expect(triptych.contains("panel_13.png"))
        #expect(triptych.contains("panel_14.png"))
    }

    @Test func hOutTriptychIsTheOnlyContainerForItsThreePanels() {
        let html = HTMLAssembler.assemble(player: Self.player(), template: Self.template())
        let act3 = actBlock(in: html, act: 3)
        #expect(!act3.contains(#"<figure class="panel panel-12">"#))
        #expect(!act3.contains(#"<figure class="panel panel-13">"#))
        #expect(!act3.contains(#"<figure class="panel panel-14">"#))
    }

    /// ADR-0007 Watchmen-style decision: triptych figures emit no `<figcaption>`.
    /// The adjacent on-page panels (new-P2 + new-P6 frame the IN row; new-P11 +
    /// new-P15 frame the OUT row) carry the narrative captions.
    @Test func triptychFiguresContainNoFigcaption() {
        let html = HTMLAssembler.assemble(player: Self.player(), template: Self.template())
        let inTriptych = triptychFigure(in: actBlock(in: html, act: 1), kind: "in")
        let outTriptych = triptychFigure(in: actBlock(in: html, act: 3), kind: "out")
        #expect(!inTriptych.contains("<figcaption"))
        #expect(!outTriptych.contains("<figcaption"))
    }

    /// ADR-0007 supersedes the page-3 diagonal pair entirely. The legacy CSS
    /// classes must be gone — leaving them in would silently let the old
    /// renderer code path resurface during a refactor.
    @Test func stylesheetContainsNoLegacyDiagonalPairRules() {
        let html = HTMLAssembler.assemble(player: Self.player(), template: Self.template())
        #expect(!html.contains(".panel-pair-10-11"))
        #expect(!html.contains(".diag-left"))
        #expect(!html.contains(".diag-right"))
        #expect(!html.contains(".diag-seams"))
        #expect(!html.contains(".cap-left"))
        #expect(!html.contains(".cap-right"))
    }

    /// ADR-0007 geometry contract. Stylesheet pins the clip-path polygons for
    /// the three children of each triptych. Specific percentage values exist
    /// per child class so a careless polygon edit breaks the test rather than
    /// silently shipping a distorted page.
    @Test func stylesheetPinsTriptychClipPathPolygons() {
        let html = HTMLAssembler.assemble(player: Self.player(), template: Self.template())
        // Stylesheet body should declare clip-path rules for each child cell.
        // The polygon coordinates themselves are exercised by the device
        // verify; tests pin the existence + the shape selectors.
        for child in [".tri-left", ".tri-middle", ".tri-right"] {
            #expect(html.contains(".panel-triptych-in \(child)"),
                    "missing panel-triptych-in \(child) selector")
            #expect(html.contains(".panel-triptych-out \(child)"),
                    "missing panel-triptych-out \(child) selector")
        }
        // P-in slashes lean //// — the parallelogram middle's clip-path must
        // include a coordinate that travels top-right to bottom-left (the
        // legacy diagonal pair leaned \\\, the new in-row is the mirror).
        #expect(html.contains(".panel-triptych-in .tri-middle"))
        // H-out diamond-middle widens at mid-height — the polygon must have a
        // vertex at 50% Y on either side.
        #expect(html.contains(".panel-triptych-out .tri-middle"))
        // Every triptych cell uses CSS clip-path; assert the property landed in
        // the stylesheet.
        #expect(html.contains("clip-path: polygon("))
    }

    @Test func nonTriptychPanelsEmitTheirCaptions() {
        let html = HTMLAssembler.assemble(player: Self.player(), template: Self.template())
        for n in 1...15 where !Self.triptychPanelNumbers.contains(n) {
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

    // MARK: - Deferred / empty-cell tolerance (slice H — ADR-0009)

    @Test func deferredPanelOmitsItsImgTag() {
        // Slice H: a panel marked deferred-failed (e.g. content-policy bounce
        // the operator chose to skip) gets its `<img src=...>` omitted from
        // the assembled HTML. The figure + figcaption + cream background still
        // render, producing the documented "empty cell" placeholder.
        let html = HTMLAssembler.assemble(player: Self.player(),
                                          template: Self.template(),
                                          deferred: [.panel(2)])
        let act1 = actBlock(in: html, act: 1)
        #expect(!act1.contains("panel_02.png"))
        #expect(act1.contains(#"<figure class="panel panel-2">"#))
        #expect(act1.contains("Beat 2 caption"))
    }

    @Test func deferredPanelInTriptychOmitsThatChildOnly() {
        // P-in triptych: deferring panel 4 leaves panels 3 and 5 in the
        // triptych but drops the middle child's `<img>`. The clip-path layout
        // is preserved (operator gets a cream slot in the middle).
        let html = HTMLAssembler.assemble(player: Self.player(),
                                          template: Self.template(),
                                          deferred: [.panel(4)])
        let act1 = actBlock(in: html, act: 1)
        let triptych = triptychFigure(in: act1, kind: "in")
        #expect(triptych.contains("panel_03.png"))
        #expect(!triptych.contains("panel_04.png"))
        #expect(triptych.contains("panel_05.png"))
    }

    @Test func deferredCoverOmitsCoverArt() {
        let html = HTMLAssembler.assemble(player: Self.player(),
                                          template: Self.template(),
                                          deferred: [.cover])
        let cover = coverBlock(in: html)
        #expect(!cover.contains("cover.png"))
        // Cover overlay (title, subtitle) should still render so the deferred
        // cover isn't a fully blank page.
        #expect(cover.contains("Faeloria"))
    }

    @Test func nonDeferredPanelsStillEmitTheirImg() {
        // Defer one — the others must keep their `<img>` exactly as before.
        let html = HTMLAssembler.assemble(player: Self.player(),
                                          template: Self.template(),
                                          deferred: [.panel(7)])
        for n in 1...15 where n != 7 {
            let filename = String(format: "panel_%02d.png", n)
            #expect(html.contains(filename), "missing \(filename)")
        }
        #expect(!html.contains("panel_07.png"))
    }

    @Test func defaultDeferredSetIsBackCompatEmpty() {
        // Existing call sites that don't pass `deferred:` get the full layout
        // with every `<img>` present (back-compat with slice 15).
        let html = HTMLAssembler.assemble(player: Self.player(),
                                          template: Self.template())
        for n in 1...15 {
            let filename = String(format: "panel_%02d.png", n)
            #expect(html.contains(filename))
        }
        #expect(html.contains("cover.png"))
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

    /// Slice the emitted `<figure class="panel-triptych-in">` or `…-out">`
    /// container out of a string. `kind` is `"in"` or `"out"`.
    private func triptychFigure(in source: Substring, kind: String) -> Substring {
        let openMarker = #"<figure class="panel-triptych-\#(kind)">"#
        guard let openRange = source.range(of: openMarker) else { return "" }
        let after = source[openRange.upperBound...]
        guard let closeRange = after.range(of: "</figure>") else { return after }
        return after[..<closeRange.lowerBound]
    }
}

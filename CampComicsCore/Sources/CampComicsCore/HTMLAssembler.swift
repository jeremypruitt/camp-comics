import Foundation

/// Assembles the print-ready HTML for one player's comic. Pure: takes player +
/// template (no `PlayerStore`, no disk), returns a self-contained HTML string
/// that the iOS-side `PDFRenderer` writes alongside the player's panel PNGs
/// and feeds to `WKWebView.createPDF`.
///
/// Ports `_legacy/layout/comic.html.j2` + `comic.css` near-verbatim, with two
/// deltas:
///   1. No page-5 roster (deferred until cohorts ship).
///   2. Diagonal P10/P11 pair is two `<img>` tags clipped via CSS
///      `clip-path: polygon(...)` instead of the legacy PIL-baked alpha PNGs
///      (see ADR-0005).
public enum HTMLAssembler {

    public struct Constants: Sendable {
        public static let `default` = Constants(
            campName: "Camp Eldermoot",
            weekLabel: "Summer 2026"
        )

        public let campName: String
        public let weekLabel: String

        public init(campName: String, weekLabel: String) {
            self.campName = campName
            self.weekLabel = weekLabel
        }
    }

    /// `deferred` lists targets whose `<img>` tag should be omitted because
    /// the operator chose Defer on a failed generation (slice H — ADR-0009).
    /// The figure/cover frame still renders so the print layout's geometry
    /// stays intact; an empty cell shows the cream page background plus the
    /// figcaption.
    public static func assemble(player: PlayerRecord,
                                template: ClassTemplate,
                                constants: Constants = .default,
                                deferred: Set<PanelTargetID> = []) -> String {
        let body = renderCover(player: player, constants: constants,
                               coverDeferred: deferred.contains(.cover))
            + (1...3).map { renderActPage(act: $0, template: template, deferred: deferred) }.joined()
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=636">
        <title>\(escape(player.characterName)) — A Tale from \(escape(constants.campName))</title>
        <style>\(stylesheet)</style>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }

    private static func renderCover(player: PlayerRecord, constants: Constants,
                                    coverDeferred: Bool) -> String {
        let art = coverDeferred ? "" : #"<img class="cover-art" src="cover.png" alt="">"#
        return """
        <section class="page cover">
          \(art)
          <div class="cover-overlay">
            <h1 class="character-name">\(escape(player.characterName))</h1>
            <p class="subtitle">A Tale from \(escape(constants.campName))</p>
            <p class="weeknote">\(escape(constants.weekLabel))</p>
          </div>
        </section>
        """
    }

    /// Explicit per-act panel-range table. Replaces the legacy
    /// `((n-1)/4)+1` formula which assumed a uniform 4/4/4 split. ADR-0007 splits
    /// 6/5/4 so the page-2 P-in triptych (panels 3–5) and the page-4 H-out
    /// triptych (panels 12–14) each have room for the surrounding bookending
    /// on-page panels.
    private static let actPanelRanges: [Int: ClosedRange<Int>] = [
        1: 1...6,
        2: 7...11,
        3: 12...15
    ]

    /// Per ADR-0007: panels in these ranges render as one shared triptych
    /// figure rather than three standalone panels. **P-in** spans page 2 / act 1
    /// (panels 3–5, parallelogram middle + trapezoid bookends, //// slashes).
    /// **H-out** spans page 4 / act 3 (panels 12–14, hexagonal diamond-middle +
    /// pentagon bookends).
    private static let pInTriptychPanels: ClosedRange<Int> = 3...5
    private static let hOutTriptychPanels: ClosedRange<Int> = 12...14

    private static func renderActPage(act: Int, template: ClassTemplate,
                                      deferred: Set<PanelTargetID>) -> String {
        let range = actPanelRanges[act] ?? 1...0
        let panels = template.panels.filter { range.contains($0.n) }
        var body = ""
        var emittedTriptych = false
        for panel in panels {
            let triptychRange = triptychRange(forActPage: act)
            if let triptychRange, triptychRange.contains(panel.n) {
                if !emittedTriptych {
                    let triptychPanels = panels.filter { triptychRange.contains($0.n) }
                    body += renderTriptych(panels: triptychPanels,
                                           kind: triptychKind(forActPage: act),
                                           deferred: deferred)
                    emittedTriptych = true
                }
                continue
            }
            let filename = String(format: "panel_%02d.png", panel.n)
            let img = deferred.contains(.panel(panel.n)) ? "" : #"<img src="\#(filename)" alt="">"#
            body += """
              <figure class="panel panel-\(panel.n)">
                \(img)
                <figcaption>\(escape(panel.beat))</figcaption>
              </figure>
            """
        }
        return """
        <section class="page interior page-act-\(act)">
          <div class="panel-grid">
        \(body)
          </div>
        </section>
        """
    }

    private static func triptychRange(forActPage act: Int) -> ClosedRange<Int>? {
        switch act {
        case 1: return pInTriptychPanels
        case 3: return hOutTriptychPanels
        default: return nil
        }
    }

    private static func triptychKind(forActPage act: Int) -> String {
        act == 1 ? "in" : "out"
    }

    /// Renders one transition triptych (ADR-0007): three `<img>` tags sharing
    /// one figure, each clipped via CSS `clip-path: polygon(...)`. `kind` is
    /// `"in"` (page 2, parallelogram middle + trapezoid bookends, "/" slashes
    /// — lower-left to upper-right, forward motion) or `"out"` (page 4,
    /// hexagonal diamond-middle + pentagon bookends). No `<figcaption>` — the
    /// adjacent on-page panels carry the narrative captions (Watchmen-style).
    ///
    /// The SVG overlay strokes a 0.5pt line along each diagonal seam edge so
    /// the visual border continues across the cuts (same approach as the
    /// legacy diagonal pair). `clip-path` cuts the rectangular border off the
    /// diagonal portions of each cell, so the SVG overlay supplies it.
    private static func renderTriptych(panels: [PanelSpec], kind: String,
                                       deferred: Set<PanelTargetID>) -> String {
        let imgs = zip(panels, ["tri-left", "tri-middle", "tri-right"])
            .compactMap { panel, cls -> String? in
                // Slice H: deferred sub-panels emit nothing — the clip-path
                // shape stays in the stylesheet (it's pinned to the parent's
                // grid cell), so the cream container background shows through
                // the missing child while sibling sub-panels render normally.
                if deferred.contains(.panel(panel.n)) { return nil }
                let filename = String(format: "panel_%02d.png", panel.n)
                return #"<img class="\#(cls)" src="\#(filename)" alt="">"#
            }
            .joined(separator: "\n    ")
        return """
          <figure class="panel-triptych-\(kind)">
            \(imgs)
            \(triptychSeamsSVG(kind: kind))
          </figure>
        """
    }

    /// SVG overlay strokes the diagonal edges of each clipped cell with a
    /// 0.5pt line, matching the rectangular 1pt panel borders in visual weight
    /// at print resolution. Polygon vertices below match the corresponding
    /// `clip-path: polygon(...)` declarations in the stylesheet.
    private static func triptychSeamsSVG(kind: String) -> String {
        let lines: String
        switch kind {
        case "in":
            // P-in: four diagonal seam edges (two cells on each side of each
            // of the two seams). "/" slope — top X > bottom X.
            lines = """
            <line x1="37.83" y1="0" x2="25.83" y2="100" stroke="#2a1f15" stroke-width="0.5pt" vector-effect="non-scaling-stroke"/>
            <line x1="40.83" y1="0" x2="28.83" y2="100" stroke="#2a1f15" stroke-width="0.5pt" vector-effect="non-scaling-stroke"/>
            <line x1="71.16" y1="0" x2="59.16" y2="100" stroke="#2a1f15" stroke-width="0.5pt" vector-effect="non-scaling-stroke"/>
            <line x1="74.16" y1="0" x2="62.16" y2="100" stroke="#2a1f15" stroke-width="0.5pt" vector-effect="non-scaling-stroke"/>
            """
        case "out":
            // H-out: four diagonal contours (pentagon inner ">", hex left "<",
            // hex right ">", pentagon inner "<"). Each is a 3-point polyline
            // tracing the cell's inner diagonal edge. Pentagon edges are
            // PARALLEL to the hex edges with a constant 2.7pp horizontal
            // offset, giving a uniform cream gap that matches the panel
            // gutter elsewhere on the page.
            lines = """
            <polyline points="31.3,0 16.3,50 31.3,100" fill="none" stroke="#2a1f15" stroke-width="0.5pt" vector-effect="non-scaling-stroke"/>
            <polyline points="34,0 19,50 34,100" fill="none" stroke="#2a1f15" stroke-width="0.5pt" vector-effect="non-scaling-stroke"/>
            <polyline points="66,0 81,50 66,100" fill="none" stroke="#2a1f15" stroke-width="0.5pt" vector-effect="non-scaling-stroke"/>
            <polyline points="68.7,0 83.7,50 68.7,100" fill="none" stroke="#2a1f15" stroke-width="0.5pt" vector-effect="non-scaling-stroke"/>
            """
        default:
            return ""
        }
        return """
        <svg class="tri-seams" viewBox="0 0 100 100" preserveAspectRatio="none">
        \(lines)
        </svg>
        """
    }

    /// CSS clip-path replacement for the legacy PIL alpha-baked PNG pair
    /// (ADR-0005). Two `<img>` tags share the cell; each is clipped to a
    /// trapezoid via CSS `clip-path: polygon(...)`. The two polygons sit on
    /// either side of the original (70,0)→(30,100) seam, each shifted 1.75pp
    /// horizontally outward, giving a 3.5pp cream gap (~0.21in on a 6.025in
    /// grid) that visually matches the 0.16in gutter between other panels.
    /// Equal offsets at top and bottom keep the perpendicular gap width
    /// constant along the diagonal.
    private static func renderDiagonalPair(left: PanelSpec, right: PanelSpec) -> String {
        let leftFile = String(format: "panel_%02d.png", left.n)
        let rightFile = String(format: "panel_%02d.png", right.n)
        return """
          <figure class="panel panel-pair-\(left.n)-\(right.n)">
            <img class="diag-left" src="\(leftFile)" alt="">
            <img class="diag-right" src="\(rightFile)" alt="">
            <svg class="diag-seams" viewBox="0 0 100 100" preserveAspectRatio="none">
              <line x1="68.25" y1="0" x2="28.25" y2="100"
                    stroke="#2a1f15" stroke-width="0.5pt"
                    vector-effect="non-scaling-stroke"/>
              <line x1="71.75" y1="0" x2="31.75" y2="100"
                    stroke="#2a1f15" stroke-width="0.5pt"
                    vector-effect="non-scaling-stroke"/>
            </svg>
            <figcaption class="cap-left">\(escape(left.beat))</figcaption>
            <figcaption class="cap-right">\(escape(right.beat))</figcaption>
          </figure>
        """
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// Ported near-verbatim from `_legacy/layout/comic.css`. Deltas vs. legacy:
    /// (1) roster section removed (deferred with page 5 — see ADR-0005),
    /// (2) `.diag-img` rules replaced with two `<img>` tags clipped via CSS
    /// `clip-path: polygon(...)` — the SVG approach distorted images under the
    /// non-uniform viewBox stretch (issue #24).
    /// File names PDFRenderer copies into the player's `panels/` directory
    /// before rendering. Stylesheet's `@font-face` `src:` rules reference these
    /// by relative path. PRD §40 requires offline operation — no Google Fonts
    /// link, no network fetch.
    public static let bundledFontFiles = ["Cinzel.ttf",
                                          "EBGaramond.ttf",
                                          "EBGaramond-Italic.ttf"]

    private static let stylesheet: String = """
    @font-face { font-family: 'Cinzel';      src: url('Cinzel.ttf'); }
    @font-face { font-family: 'EB Garamond'; src: url('EBGaramond.ttf'); }
    @font-face { font-family: 'EB Garamond'; font-style: italic; src: url('EBGaramond-Italic.ttf'); }
    @page { size: 6.625in 10.25in; margin: 0; }
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: 'EB Garamond', Garamond, 'Times New Roman', serif;
      color: #2a1f15;
      background: #fffaf0;
    }
    .page {
      width: 6.625in; height: 10.25in;
      page-break-after: always; break-after: page; break-inside: avoid;
      overflow: hidden; position: relative;
    }
    .page:last-child { page-break-after: auto; break-after: auto; }

    .cover { padding: 0; background: #000; }
    .cover-art { width: 100%; height: 100%; object-fit: cover; display: block; }
    .cover-overlay {
      position: absolute; top: 0; left: 0; right: 0;
      padding: 0.6in 0.4in 0;
      text-align: center; color: #fff8e6;
      text-shadow: 0 2px 6px rgba(0, 0, 0, 0.75);
    }
    .character-name {
      font-family: 'Cinzel', 'Trajan Pro', serif;
      font-size: 42pt; font-weight: 700; letter-spacing: 0.04em; line-height: 1.1;
    }
    .subtitle {
      font-family: 'Cinzel', serif;
      font-size: 13pt; font-style: italic; margin-top: 0.15in; letter-spacing: 0.05em;
    }
    .weeknote { font-size: 10pt; opacity: 0.85; margin-top: 0.05in; }

    .interior { padding: 0.3in; }
    .panel-grid {
      display: grid; gap: 0.16in; width: 100%; height: 100%;
      grid-template-columns: minmax(0, 1fr) minmax(0, 1fr);
    }
    .panel {
      position: relative; overflow: hidden;
      border: 1pt solid #2a1f15; background: #000;
      box-shadow: 0 1pt 3pt rgba(0, 0, 0, 0.3);
      min-height: 0; min-width: 0;
    }
    .panel img {
      width: 100%; height: 100%; object-fit: cover; display: block;
      object-position: center top;
    }
    .panel figcaption {
      position: absolute; bottom: 0; left: 0; right: 0;
      background: rgba(20, 14, 8, 0.85); color: #fffaf0;
      font-family: 'EB Garamond', Garamond, serif;
      font-style: italic; font-size: 8.5pt; line-height: 1.3;
      padding: 0.07in 0.1in; text-align: center;
    }

    /* Act 1 (page 2, 6 panels): two squares, P-in triptych, hero splash. */
    .page-act-1 .panel-grid {
      grid-template-columns: minmax(0, 1fr) minmax(0, 1fr);
      grid-template-rows: minmax(0, 1fr) minmax(0, 1.2fr) minmax(0, 1.3fr);
    }
    .page-act-1 .panel-1 { grid-column: 1; grid-row: 1; }
    .page-act-1 .panel-2 { grid-column: 2; grid-row: 1; }
    .page-act-1 .panel-triptych-in { grid-column: 1 / span 2; grid-row: 2; }
    .page-act-1 .panel-6 { grid-column: 1 / span 2; grid-row: 3; }

    /* Act 2 (page 3, 5 panels): forest splash, 3-up middle band, kneeling close-up. */
    .page-act-2 .panel-grid {
      grid-template-columns: minmax(0, 1fr) minmax(0, 1fr) minmax(0, 1fr);
      grid-template-rows: minmax(0, 1.4fr) minmax(0, 1fr) minmax(0, 1.4fr);
    }
    .page-act-2 .panel-7  { grid-column: 1 / span 3; grid-row: 1; }
    .page-act-2 .panel-8  { grid-column: 1; grid-row: 2; }
    .page-act-2 .panel-9  { grid-column: 2; grid-row: 2; }
    .page-act-2 .panel-10 { grid-column: 3; grid-row: 2; }
    .page-act-2 .panel-11 { grid-column: 1 / span 3; grid-row: 3; }
    .page-act-2 .panel-7 img { object-position: center bottom; }

    /* Act 3 (page 4, 4 panels): H-out triptych dominates, kitchen return splash. */
    .page-act-3 .panel-grid {
      grid-template-columns: minmax(0, 1fr) minmax(0, 1fr);
      grid-template-rows: minmax(0, 1.2fr) minmax(0, 1fr);
    }
    .page-act-3 .panel-triptych-out { grid-column: 1 / span 2; grid-row: 1; }
    .page-act-3 .panel-15 { grid-column: 1 / span 2; grid-row: 2; }

    /* Transition triptychs (ADR-0007). Each is one figure with three clipped
       <img> children. The cream container background shows through the gaps
       along the diagonal seams. Polygons leave a ~3.5pp constant-width gap
       perpendicular to each seam, matching the ADR-0005 gap convention. */
    .panel-triptych-in,
    .panel-triptych-out {
      position: relative; background: #fffaf0;
      border: none; box-shadow: none;
      overflow: hidden; min-width: 0; min-height: 0;
    }
    .panel-triptych-in .tri-left,
    .panel-triptych-in .tri-middle,
    .panel-triptych-in .tri-right,
    .panel-triptych-out .tri-left,
    .panel-triptych-out .tri-middle,
    .panel-triptych-out .tri-right {
      position: absolute; top: 0; left: 0;
      width: 100%; height: 100%;
      object-fit: cover; object-position: center top;
      display: block;
      border: 1pt solid #2a1f15;
    }
    /* SVG seam overlay strokes the diagonal edges that clip-path leaves
       borderless — see renderer's triptychSeamsSVG. */
    .panel-triptych-in .tri-seams,
    .panel-triptych-out .tri-seams {
      position: absolute; top: 0; left: 0;
      width: 100%; height: 100%; display: block;
      pointer-events: none; z-index: 1;
    }

    /* P-in: "/" slashes — seams travel from lower-left to upper-right (top X >
       bottom X), reading as forward motion / progress. Three equal-area cells,
       with seam 1 at ~33% and seam 2 at ~66% width. Aggressive 12pp lean from
       top to bottom (acute trapezoid corners) with a 3pp constant horizontal
       gap that matches the 0.16in panel gutter elsewhere on the page. */
    .panel-triptych-in .tri-left   { clip-path: polygon(0 0,       37.83% 0,  25.83% 100%, 0     100%); }
    .panel-triptych-in .tri-middle { clip-path: polygon(40.83% 0,  71.16% 0,  59.16% 100%, 28.83% 100%); }
    .panel-triptych-in .tri-right  { clip-path: polygon(74.16% 0,  100% 0,    100% 100%,   62.16% 100%); }
    /* H-out: hexagonal diamond-middle (widest at mid-height), pentagon
       bookends mirroring the hex's outward fan. The mid-height widening is
       where the gift close-up's focal subject sits — diamond was chosen over
       bow-tie so the gift isn't cropped. Pentagon inner edges run STRICTLY
       PARALLEL to the hex's outer edges with a uniform 2.7pp horizontal
       offset, giving a constant ~0.16in perpendicular cream gap that matches
       the panel-gutter elsewhere on the page. */
    .panel-triptych-out .tri-left {
      clip-path: polygon(0 0, 31.3% 0, 16.3% 50%, 31.3% 100%, 0 100%);
    }
    .panel-triptych-out .tri-middle {
      clip-path: polygon(34% 0, 66% 0, 81% 50%, 66% 100%, 34% 100%, 19% 50%);
    }
    .panel-triptych-out .tri-right {
      clip-path: polygon(68.7% 0, 100% 0, 100% 100%, 68.7% 100%, 83.7% 50%);
    }
    """
}

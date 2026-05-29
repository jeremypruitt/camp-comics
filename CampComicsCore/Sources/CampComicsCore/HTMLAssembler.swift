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

    /// Source-relative centroid of the subject inside a generated panel,
    /// 0–100 with top-left origin. Used by slice 30b (ADR-0006) to align the
    /// generated subject with the diagonal trapezoid's polygon centroid via
    /// an inline `transform: scale + translate` on the `<img>`. Absent from
    /// the per-panel map ⇒ fall through to the slice-30a CSS baseline.
    public struct PanelPosition: Sendable {
        public let xPct: Double
        public let yPct: Double

        public init(xPct: Double, yPct: Double) {
            self.xPct = xPct
            self.yPct = yPct
        }
    }

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

    public static func assemble(player: PlayerRecord,
                                template: ClassTemplate,
                                constants: Constants = .default,
                                panelPositions: [Int: PanelPosition] = [:]) -> String {
        let body = renderCover(player: player, constants: constants)
            + (1...3).map {
                renderActPage(act: $0, template: template, panelPositions: panelPositions)
            }.joined()
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

    private static func renderCover(player: PlayerRecord, constants: Constants) -> String {
        """
        <section class="page cover">
          <img class="cover-art" src="cover.png" alt="">
          <div class="cover-overlay">
            <h1 class="character-name">\(escape(player.characterName))</h1>
            <p class="subtitle">A Tale from \(escape(constants.campName))</p>
            <p class="weeknote">\(escape(constants.weekLabel))</p>
          </div>
        </section>
        """
    }

    private static func renderActPage(act: Int,
                                      template: ClassTemplate,
                                      panelPositions: [Int: PanelPosition]) -> String {
        let panels = template.panels.filter { ((($0.n - 1) / 4) + 1) == act }
        var body = ""
        var skipNext = false
        for panel in panels {
            if skipNext { skipNext = false; continue }
            if act == 3 && panel.n == 10 {
                let next = panels.first(where: { $0.n == panel.n + 1 })
                body += renderDiagonalPair(left: panel,
                                           right: next ?? panel,
                                           panelPositions: panelPositions)
                skipNext = true
            } else {
                let filename = String(format: "panel_%02d.png", panel.n)
                body += """
                  <figure class="panel panel-\(panel.n)">
                    <img src="\(filename)" alt="">
                    <figcaption>\(escape(panel.beat))</figcaption>
                  </figure>
                """
            }
        }
        return """
        <section class="page interior page-act-\(act)">
          <div class="panel-grid">
        \(body)
          </div>
        </section>
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
    private static func renderDiagonalPair(left: PanelSpec,
                                           right: PanelSpec,
                                           panelPositions: [Int: PanelPosition]) -> String {
        let leftFile = String(format: "panel_%02d.png", left.n)
        let rightFile = String(format: "panel_%02d.png", right.n)
        let leftAttr = panelPositions[left.n].map { diagTransformAttr(side: .left, position: $0) } ?? ""
        let rightAttr = panelPositions[right.n].map { diagTransformAttr(side: .right, position: $0) } ?? ""
        return """
          <figure class="panel panel-pair-\(left.n)-\(right.n)">
            <img class="diag-left" src="\(leftFile)" alt=""\(leftAttr)>
            <img class="diag-right" src="\(rightFile)" alt=""\(rightAttr)>
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

    private enum DiagSide { case left, right }

    /// Slice 30b (ADR-0006): translate the diag-{left|right} img so the
    /// salient subject (caller-provided centroid in source coords) lands on
    /// the polygon centroid in cell coords. Geometry constants:
    ///
    ///   - cell aspect = 6.025in / 2.67in = 2.258
    ///   - source aspect = 16/9 = 1.778
    ///   - under `object-fit: cover` + `object-position: center top`, source
    ///     displays 100% wide × 127% tall of the cell; upper 78.7% visible.
    ///   - polygon centroid (cell coords) computed via shoelace:
    ///       diag-left  ≈ (25.5%, 43.1%)
    ///       diag-right ≈ (74.5%, 56.9%)
    ///
    /// The fixed scale of 1.4 gives ±20% of headroom on both axes — enough
    /// to recompose any centroid in the salient region without exposing the
    /// cream background through the trapezoid edge.
    private static func diagTransformAttr(side: DiagSide, position: PanelPosition) -> String {
        let scale = 1.4
        let sourceToCellY = 2.258 / 1.778  // 1.270
        let target: (x: Double, y: Double) = {
            switch side {
            case .left:  return (25.5, 43.1)
            case .right: return (74.5, 56.9)
            }
        }()
        let cellSrcX = position.xPct
        let cellSrcY = position.yPct * sourceToCellY
        let scaledX = 50 + scale * (cellSrcX - 50)
        let scaledY = 50 + scale * (cellSrcY - 50)
        let tx = target.x - scaledX
        let ty = target.y - scaledY
        let style = String(format: "transform: translate(%.2f%%, %.2f%%) scale(%.2f); transform-origin: center;",
                           tx, ty, scale)
        return " style=\"\(style)\""
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

    .page-act-1 .panel-grid { grid-template-rows: minmax(0, 1fr) minmax(0, 1fr) minmax(0, 1.5fr); }
    .page-act-1 .panel-1 { grid-column: 1; grid-row: 1; }
    .page-act-1 .panel-2 { grid-column: 2; grid-row: 1 / span 2; }
    .page-act-1 .panel-3 { grid-column: 1; grid-row: 2; }
    .page-act-1 .panel-4 { grid-column: 1 / span 2; grid-row: 3; }

    .page-act-2 .panel-grid { grid-template-rows: minmax(0, 1.5fr) minmax(0, 1fr) minmax(0, 1fr); }
    .page-act-2 .panel-5 { grid-column: 1 / span 2; grid-row: 1; }
    .page-act-2 .panel-6 { grid-column: 1; grid-row: 2; }
    .page-act-2 .panel-7 { grid-column: 2; grid-row: 2 / span 2; }
    .page-act-2 .panel-8 { grid-column: 1; grid-row: 3; }
    .page-act-2 .panel-5 img { object-position: center bottom; }

    .page-act-3 .panel-grid { grid-template-rows: minmax(0, 1.5fr) minmax(0, 1fr) minmax(0, 1fr); }
    .page-act-3 .panel-9  { grid-column: 1 / span 2; grid-row: 1; }
    .page-act-3 .panel-12 { grid-column: 1 / span 2; grid-row: 3; }

    .page-act-3 .panel-pair-10-11 {
      grid-column: 1 / span 2; grid-row: 2;
      position: relative; background: #fffaf0;
      border: none; box-shadow: none;
      overflow: hidden; min-width: 0; min-height: 0;
    }
    .page-act-3 .panel-pair-10-11 .diag-left,
    .page-act-3 .panel-pair-10-11 .diag-right {
      position: absolute; top: 0; left: 0;
      width: 100%; height: 100%;
      object-fit: cover; object-position: center top;
      display: block;
      border: 1pt solid #2a1f15;
    }
    .page-act-3 .panel-pair-10-11 .diag-left  { clip-path: polygon(0 0,      68.25% 0, 28.25% 100%, 0   100%); }
    .page-act-3 .panel-pair-10-11 .diag-right { clip-path: polygon(71.75% 0, 100% 0,   100% 100%,   31.75% 100%); }
    .page-act-3 .panel-pair-10-11 .diag-seams {
      position: absolute; top: 0; left: 0;
      width: 100%; height: 100%; display: block;
      pointer-events: none; z-index: 1;
    }
    .page-act-3 .panel-pair-10-11 .cap-left,
    .page-act-3 .panel-pair-10-11 .cap-right {
      position: absolute; bottom: 3pt;
      background: rgba(20, 14, 8, 0.85); color: #fffaf0;
      font-family: 'EB Garamond', Garamond, serif;
      font-style: italic; font-size: 8.5pt; line-height: 1.3;
      padding: 0.07in 0.1in; text-align: center; z-index: 2;
    }
    .page-act-3 .panel-pair-10-11 .cap-left  { left: 0; right: auto; width: 28%; }
    .page-act-3 .panel-pair-10-11 .cap-right { left: auto; right: 0; width: 28%; }
    """
}

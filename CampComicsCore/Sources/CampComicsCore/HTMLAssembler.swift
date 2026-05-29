import Foundation

/// Assembles the print-ready HTML for one player's comic. Pure: takes player +
/// template (no `PlayerStore`, no disk), returns a self-contained HTML string
/// that the iOS-side `PDFRenderer` writes alongside the player's panel PNGs
/// and feeds to `WKWebView.createPDF`.
///
/// Ports `_legacy/layout/comic.html.j2` + `comic.css` near-verbatim, with two
/// deltas:
///   1. No page-5 roster (deferred until cohorts ship).
///   2. Diagonal P10/P11 pair is one inline `<svg>` with `<clipPath>`s on iOS
///      WebKit (legacy WeasyPrint 68 couldn't render clip-path so it baked the
///      alpha into intermediate PNGs via PIL — see ADR-0005).
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

    public static func assemble(player: PlayerRecord,
                                template: ClassTemplate,
                                constants: Constants = .default) -> String {
        let body = renderCover(player: player, constants: constants)
            + (1...3).map { renderActPage(act: $0, template: template) }.joined()
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

    private static func renderActPage(act: Int, template: ClassTemplate) -> String {
        let panels = template.panels.filter { ((($0.n - 1) / 4) + 1) == act }
        var body = ""
        var skipNext = false
        for panel in panels {
            if skipNext { skipNext = false; continue }
            if act == 3 && panel.n == 10 {
                let next = panels.first(where: { $0.n == panel.n + 1 })
                body += renderDiagonalPair(left: panel, right: next ?? panel)
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

    /// Inline SVG replacement for the legacy PIL alpha-baked PNG pair (ADR-0005).
    /// Shared diagonal goes from (70%, 0) to (30%, 100%); both trapezoids touch
    /// that line so the seam is exact. Cream gap between them is the container
    /// background showing through. `non-scaling-stroke` keeps the diagonal line
    /// at 1pt even though the SVG is stretched non-uniformly by the grid cell.
    private static func renderDiagonalPair(left: PanelSpec, right: PanelSpec) -> String {
        let leftFile = String(format: "panel_%02d.png", left.n)
        let rightFile = String(format: "panel_%02d.png", right.n)
        return """
          <figure class="panel panel-pair-\(left.n)-\(right.n)">
            <svg class="diag-svg" viewBox="0 0 100 100" preserveAspectRatio="none">
              <defs>
                <clipPath id="diag-left-\(left.n)" clipPathUnits="userSpaceOnUse">
                  <polygon points="0,0 70,0 30,100 0,100"/>
                </clipPath>
                <clipPath id="diag-right-\(right.n)" clipPathUnits="userSpaceOnUse">
                  <polygon points="70,0 100,0 100,100 30,100"/>
                </clipPath>
              </defs>
              <image href="\(leftFile)" x="0" y="0" width="100" height="100"
                     preserveAspectRatio="xMidYMin slice"
                     clip-path="url(#diag-left-\(left.n))"/>
              <image href="\(rightFile)" x="0" y="0" width="100" height="100"
                     preserveAspectRatio="xMidYMin slice"
                     clip-path="url(#diag-right-\(right.n))"/>
              <line x1="70" y1="0" x2="30" y2="100"
                    stroke="#2a1f15" stroke-width="1pt"
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
    /// (2) `.diag-img` rules replaced with `.diag-svg` rules — the diagonal
    /// trapezoids are now SVG `<image>` elements clipped via `<clipPath>`
    /// instead of pre-baked alpha PNGs.
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
      border: none; overflow: hidden; min-width: 0; min-height: 0;
    }
    .page-act-3 .panel-pair-10-11 .diag-svg {
      position: absolute; top: 0; left: 0;
      width: 100%; height: 100%; display: block;
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

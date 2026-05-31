import Foundation
import WebKit
import CampComicsCore

public enum PDFRenderError: Error {
    case navigationFailed(Error)
}

/// One-shot iOS WKWebView-backed PDF renderer for a single player's comic.
/// Writes `panels/_render.html` next to the on-disk panels, loads it via
/// `loadFileURL(allowingReadAccessTo:)` so `<img src="panel_01.png">` resolves,
/// awaits navigation finish, calls `WKWebView.pdf(configuration:)`, writes the
/// result to `comic.pdf` at the player-dir root.
///
/// Deliberately untested at the unit level — visual fidelity is the success
/// criterion (PRD §229). The eyeball compare against the legacy WeasyPrint
/// output of `camper_001` is the actual verification.
@MainActor
public final class PDFRenderer: NSObject {

    public static func render(player: PlayerRecord,
                              template: ClassTemplate,
                              store: PlayerStore,
                              constants: HTMLAssembler.Constants = .default) async throws -> URL {
        let renderer = PDFRenderer()
        return try await renderer.run(player: player,
                                      template: template,
                                      store: store,
                                      constants: constants)
    }

    private var navContinuation: CheckedContinuation<Void, Error>?
    private var webView: WKWebView?

    private func run(player: PlayerRecord,
                     template: ClassTemplate,
                     store: PlayerStore,
                     constants: HTMLAssembler.Constants) async throws -> URL {
        // Slice H (#68): a deferred panel/cover renders as an empty cell
        // (cream background + figcaption, no `<img>`). The set is derived
        // from disk so the renderer doesn't need a separate parameter from
        // PlayerDetailView's "Generate PDF" call site.
        var deferred = Set<PanelTargetID>()
        for panel in template.panels where store.isDeferred(playerId: player.id, target: .panel(panel.n)) {
            deferred.insert(.panel(panel.n))
        }
        if store.isDeferred(playerId: player.id, target: .cover) {
            deferred.insert(.cover)
        }
        let html = HTMLAssembler.assemble(player: player,
                                          template: template,
                                          constants: constants,
                                          deferred: deferred)
        let panelsDir = store.panelsDirectory(playerId: player.id)
        try FileManager.default.createDirectory(at: panelsDir, withIntermediateDirectories: true)
        try Self.copyBundledFonts(to: panelsDir)
        let htmlURL = panelsDir.appendingPathComponent("_render.html")
        try html.data(using: .utf8)!.write(to: htmlURL, options: .atomic)

        // CSS pixels for a 6.625in × 10.25in page at 96dpi. Sizing the web view
        // to the page's pixel dimensions keeps the layout from being scaled by
        // an arbitrary device width during PDF rendering.
        let pageRect = CGRect(x: 0, y: 0, width: 636, height: 984)
        let view = WKWebView(frame: pageRect)
        view.navigationDelegate = self
        self.webView = view

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            self.navContinuation = cont
            view.loadFileURL(htmlURL,
                             allowingReadAccessTo: store.playerDirectory(playerId: player.id))
        }

        let config = WKPDFConfiguration()
        let pdfData = try await view.pdf(configuration: config)
        let outURL = store.comicURL(playerId: player.id)
        try pdfData.write(to: outURL, options: .atomic)
        return outURL
    }

    /// Copy the bundled font files into the player's `panels/` directory so
    /// the inline `@font-face` rules in `_render.html` resolve via WKWebView's
    /// `allowingReadAccessTo:` scope. Overwrites on each render (the font
    /// bytes don't change) so callers don't have to track install state.
    private static func copyBundledFonts(to destDir: URL) throws {
        for fileName in HTMLAssembler.bundledFontFiles {
            guard let src = Bundle.main.url(forResource: fileName, withExtension: nil) else {
                continue
            }
            let dest = destDir.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: src, to: dest)
        }
    }
}

extension PDFRenderer: WKNavigationDelegate {
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let cont = navContinuation
        navContinuation = nil
        cont?.resume()
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        let cont = navContinuation
        navContinuation = nil
        cont?.resume(throwing: PDFRenderError.navigationFailed(error))
    }

    public func webView(_ webView: WKWebView,
                        didFailProvisionalNavigation navigation: WKNavigation!,
                        withError error: Error) {
        let cont = navContinuation
        navContinuation = nil
        cont?.resume(throwing: PDFRenderError.navigationFailed(error))
    }
}

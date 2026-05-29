import Foundation
import Vision
import CoreImage
import CampComicsCore

/// Slice 30b safety net (ADR-0006): on-device Apple Vision attention-based
/// saliency to locate where the subject actually landed in a generated panel.
/// `PDFRenderer` runs this on the staged panel_10.png + panel_11.png before
/// HTML assembly; the centroid feeds `HTMLAssembler.PanelPosition` so the
/// CSS transform on the diag-{left|right} img aligns the subject with the
/// polygon centroid in cell coords.
///
/// Returns nil when Vision finds no salient region — rare on subject-driven
/// panels; callers omit that panel from the map for silent fallback to the
/// slice-30a CSS baseline.
///
/// Not unit-tested: Vision needs real image bytes, not stubs, and the
/// model output isn't bit-stable across OS versions. Device verify is the
/// success criterion per #33 AC.
enum SaliencyAnalyzer {

    static func centroid(of url: URL) async -> HTMLAssembler.PanelPosition? {
        guard let image = CIImage(contentsOf: url) else { return nil }
        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard let result = request.results?.first as? VNSaliencyImageObservation,
              let box = result.salientObjects?.first?.boundingBox else {
            return nil
        }
        // Vision boundingBox is normalized 0–1 with origin bottom-left;
        // PanelPosition expects 0–100 with origin top-left.
        let centerX = box.origin.x + box.size.width / 2
        let centerYBottomLeft = box.origin.y + box.size.height / 2
        let centerYTopLeft = 1 - centerYBottomLeft
        return HTMLAssembler.PanelPosition(
            xPct: centerX * 100,
            yPct: centerYTopLeft * 100
        )
    }
}

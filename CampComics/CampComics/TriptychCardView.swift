import SwiftUI
import UIKit
import CampComicsCore

/// Slice G (#67). SwiftUI rendition of ADR-0007's print-layout triptych for
/// the Phase-2 review surface. Composites three sub-panel images (left,
/// middle, right) into one card using `Shape` clip-paths whose polygon
/// vertices mirror the percentages in `HTMLAssembler`'s stylesheet:
///
/// - **P-in** (panels 3–5): "/"-leaning trapezoid bookends + parallelogram
///   middle (12pp top-to-bottom lean, ~3pp constant horizontal gap).
/// - **H-out** (panels 12–14): pentagon bookends + hex diamond-middle
///   (mid-height widening, 2.7pp parallel offset between pentagon inner and
///   hex outer edges).
///
/// Cream gap is the card's background — the three image cells leave it
/// visible along the diagonal seams. Diagonal seam strokes match the print
/// layout's `triptychSeamsSVG`.
struct TriptychCardView: View {
    @Environment(\.themeKind) private var theme
    let kind: PanelTriptych.Kind
    /// Always three images, in `[left, middle, right]` order — matching
    /// `PanelTriptych.subTargets`. Caller (Phase2StackView) loads the newest
    /// candidate per sub-panel before rendering.
    let images: [UIImage]

    /// 16:9 (1.78) for P-in's pancake-tall bookend strip; ~2:1 (2.0) for H-out
    /// since the hex diamond reads better given more horizontal room.
    private var aspectRatio: CGFloat {
        kind == .pIn ? 16.0 / 9.0 : 2.0
    }

    var body: some View {
        let p = theme.palette
        GeometryReader { geo in
            ZStack {
                p.paper // cream gap visible through the clip-path cuts
                let shapes = TriptychShapes.cells(for: kind)
                ForEach(Array(zip(shapes.indices, shapes)), id: \.0) { (i, shape) in
                    if i < images.count {
                        Image(uiImage: images[i])
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipShape(shape)
                            .overlay(shape.stroke(p.inkPrimary, lineWidth: 1))
                    }
                }
                // Seam strokes — the diagonal edges that clip-path leaves
                // borderless. 0.5pt in print; 0.75pt on-screen at typical
                // card width gives the same visual weight.
                TriptychSeams(kind: kind)
                    .stroke(p.inkPrimary, lineWidth: 0.75)
            }
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
    }
}

/// Shape definitions for the three sub-panel cells. Each polygon's vertices
/// are normalised to `(0...1, 0...1)`; the shape maps them into the cell's
/// rect at render time. Percentages mirror
/// `HTMLAssembler.panel-triptych-{in,out} .tri-{left,middle,right}`.
enum TriptychShapes {

    static func cells(for kind: PanelTriptych.Kind) -> [PolygonShape] {
        switch kind {
        case .pIn:
            return [
                // tri-left:   0 0       37.83 0   25.83 100  0 100
                PolygonShape(points: [
                    .init(x: 0.00, y: 0.00),
                    .init(x: 0.3783, y: 0.00),
                    .init(x: 0.2583, y: 1.00),
                    .init(x: 0.00, y: 1.00)
                ]),
                // tri-middle: 40.83 0   71.16 0   59.16 100  28.83 100
                PolygonShape(points: [
                    .init(x: 0.4083, y: 0.00),
                    .init(x: 0.7116, y: 0.00),
                    .init(x: 0.5916, y: 1.00),
                    .init(x: 0.2883, y: 1.00)
                ]),
                // tri-right:  74.16 0   100 0     100 100    62.16 100
                PolygonShape(points: [
                    .init(x: 0.7416, y: 0.00),
                    .init(x: 1.00, y: 0.00),
                    .init(x: 1.00, y: 1.00),
                    .init(x: 0.6216, y: 1.00)
                ])
            ]
        case .hOut:
            return [
                // tri-left pentagon: 0 0  31.3 0  16.3 50  31.3 100  0 100
                PolygonShape(points: [
                    .init(x: 0.00, y: 0.00),
                    .init(x: 0.313, y: 0.00),
                    .init(x: 0.163, y: 0.50),
                    .init(x: 0.313, y: 1.00),
                    .init(x: 0.00, y: 1.00)
                ]),
                // tri-middle hex: 34 0  66 0  81 50  66 100  34 100  19 50
                PolygonShape(points: [
                    .init(x: 0.34, y: 0.00),
                    .init(x: 0.66, y: 0.00),
                    .init(x: 0.81, y: 0.50),
                    .init(x: 0.66, y: 1.00),
                    .init(x: 0.34, y: 1.00),
                    .init(x: 0.19, y: 0.50)
                ]),
                // tri-right pentagon: 68.7 0  100 0  100 100  68.7 100  83.7 50
                PolygonShape(points: [
                    .init(x: 0.687, y: 0.00),
                    .init(x: 1.00, y: 0.00),
                    .init(x: 1.00, y: 1.00),
                    .init(x: 0.687, y: 1.00),
                    .init(x: 0.837, y: 0.50)
                ])
            ]
        }
    }
}

/// A SwiftUI `Shape` built from a normalised polygon. Used for both the
/// `clipShape` of each sub-panel image and the matching outline stroke.
struct PolygonShape: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        let scale: (CGPoint) -> CGPoint = { p in
            CGPoint(x: rect.minX + p.x * rect.width,
                    y: rect.minY + p.y * rect.height)
        }
        path.move(to: scale(first))
        for p in points.dropFirst() {
            path.addLine(to: scale(p))
        }
        path.closeSubpath()
        return path
    }
}

/// Diagonal seam strokes that match `HTMLAssembler.triptychSeamsSVG`. Each
/// `Path` element traces the inner diagonal edge of a cell, providing the
/// border the `clip-path` cuts off the underlying image cell.
struct TriptychSeams: Shape {
    let kind: PanelTriptych.Kind

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        let pt: (CGFloat, CGFloat) -> CGPoint = { (xp, yp) in
            CGPoint(x: rect.minX + xp * w, y: rect.minY + yp * h)
        }
        switch kind {
        case .pIn:
            // Four parallel "/" seams: cell-edge pairs at ~33% and ~66%.
            path.move(to: pt(0.3783, 0)); path.addLine(to: pt(0.2583, 1))
            path.move(to: pt(0.4083, 0)); path.addLine(to: pt(0.2883, 1))
            path.move(to: pt(0.7116, 0)); path.addLine(to: pt(0.5916, 1))
            path.move(to: pt(0.7416, 0)); path.addLine(to: pt(0.6216, 1))
        case .hOut:
            // Four parallel diamond contours.
            path.move(to: pt(0.313, 0)); path.addLine(to: pt(0.163, 0.5)); path.addLine(to: pt(0.313, 1))
            path.move(to: pt(0.34, 0));  path.addLine(to: pt(0.19, 0.5));  path.addLine(to: pt(0.34, 1))
            path.move(to: pt(0.66, 0));  path.addLine(to: pt(0.81, 0.5));  path.addLine(to: pt(0.66, 1))
            path.move(to: pt(0.687, 0)); path.addLine(to: pt(0.837, 0.5)); path.addLine(to: pt(0.687, 1))
        }
        return path
    }
}

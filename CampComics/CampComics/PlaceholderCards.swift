import SwiftUI
import UIKit
import CampComicsCore

/// Slice M (#94, ADR-0010). Foundational presentation primitives used by every
/// other ADR-0010 slice: a placeholder card that renders the actual final panel
/// shape with an empty/spinning image area inside, plus a triptych variant that
/// renders the composed P-in (`/`-diagonal) or H-out (parallel-edge) frame with
/// three independent spinning image slots.
///
/// "The placeholder IS the panel frame." — ADR-0010. Same dimensions, same
/// border, same caption from the YAML, so the operator sees what's coming and
/// the wait feels like progress rather than uncertainty. No separate dark
/// "generating" UI.
///
/// Pure presentation — no `GenerationQueue` wiring, no `PlayerStore` reads, no
/// swipe handling. Slot fill state is driven from outside.

/// Per-slot render state. `.stuck` is reserved for Slice Q (#98) — Slice M
/// only consumes `.spinning` and `.filled`, but the case is included so
/// downstream slices don't have to widen this enum (an additive variant is
/// the smaller-blast-radius edit per the ADR-0010 fan-out plan).
enum PlaceholderSlotState {
    case spinning
    case filled(UIImage)
    case stuck(UIImage?)
}

// MARK: - Single panel placeholder

struct PlaceholderPanelCard: View {
    @Environment(\.themeKind) private var theme
    let spec: PanelSpec
    let playerName: String
    let slot: PlaceholderSlotState
    /// Peek cards (#108) suppress caption text but still render the colored
    /// strip background so card dimensions stay uniform across the deck —
    /// otherwise the visible sliver below the top card reveals readable
    /// text from the peek behind it.
    var showsCaption: Bool = true
    /// Head-of-deck cards (#110) wrap the rendered image in `ZoomableImage`
    /// so the operator can pinch into face/costume detail. Peek cards stay
    /// non-zoomable so their UIScrollViews can't intercept the deck's swipe
    /// gestures.
    var allowsZoom: Bool = false

    var body: some View {
        let p = theme.palette
        VStack(spacing: 0) {
            imageArea
                .background(p.surfaceRaised)
            captionStrip
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(p.inkPrimary.opacity(0.4), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var imageArea: some View {
        // Always 1:1 regardless of slot — `.scaledToFit` alone would let a
        // wider-than-tall generated image shrink the card's height, so
        // peek cards (always 1:1) would tower over the top card and break
        // the deck's offset math (#108).
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                switch slot {
                case .filled(let image):
                    if allowsZoom {
                        ZoomableImage(image: image)
                    } else {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                    }
                case .spinning:
                    ProgressView()
                case .stuck(let image):
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .saturation(0)
                            .opacity(0.55)
                    }
                }
            }
    }

    private var captionStrip: some View {
        let p = theme.palette
        return Group {
            if showsCaption {
                Text(PanelCaption.substitute(spec.beat, playerName: playerName))
                    .font(theme.captionFont(13))
                    .foregroundStyle(p.inkSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 10)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .background(p.surfaceRaised)
    }
}

// MARK: - Triptych placeholder

struct PlaceholderTriptychCard: View {
    @Environment(\.themeKind) private var theme
    let kind: PanelTriptych.Kind
    /// Exactly 3 slots, left/middle/right (matches `PanelTriptych.subTargets`).
    let slots: [PlaceholderSlotState]

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
                    let slot = slots.indices.contains(i) ? slots[i] : .spinning
                    cell(shape: shape, slot: slot, geo: geo)
                }
                TriptychSeams(kind: kind)
                    .stroke(p.inkPrimary, lineWidth: 0.75)
            }
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
    }

    @ViewBuilder
    private func cell(shape: PolygonShape,
                      slot: PlaceholderSlotState,
                      geo: GeometryProxy) -> some View {
        let p = theme.palette
        let centroid = shape.normalizedCentroid
        switch slot {
        case .filled(let img):
            Image(uiImage: img)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: geo.size.width, height: geo.size.height)
                .clipShape(shape)
                .overlay(shape.stroke(p.inkPrimary, lineWidth: 1))
        case .spinning:
            ZStack {
                shape.fill(p.surfaceRaised)
                shape.stroke(p.inkPrimary, lineWidth: 1)
                ProgressView()
                    .position(x: geo.size.width * centroid.x,
                              y: geo.size.height * centroid.y)
            }
        case .stuck(let img):
            ZStack {
                if let img {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipShape(shape)
                        .saturation(0)
                        .opacity(0.55)
                } else {
                    shape.fill(p.surfaceRaised.opacity(0.6))
                }
                shape.stroke(p.inkPrimary.opacity(0.6), lineWidth: 1)
            }
        }
    }
}

// MARK: - Polygon centroid helper

extension PolygonShape {
    /// Mean of the polygon's normalised vertices — used to anchor a spinner
    /// inside an irregular clip-path so it visually lands in the cell's
    /// optical centre rather than the bounding-box centre.
    var normalizedCentroid: CGPoint {
        guard !points.isEmpty else { return CGPoint(x: 0.5, y: 0.5) }
        let n = CGFloat(points.count)
        let x = points.reduce(into: CGFloat(0)) { $0 += $1.x } / n
        let y = points.reduce(into: CGFloat(0)) { $0 += $1.y } / n
        return CGPoint(x: x, y: y)
    }
}

// MARK: - Previews

#Preview("Panel — spinning") {
    let spec = PanelSpec(n: 1,
                         beat: "It was Tuesday. Nothing interesting was happening. Yet.",
                         emotion: .neutral,
                         position: .front)
    return PlaceholderPanelCard(spec: spec, playerName: "Quinn", slot: .spinning)
        .padding()
        .background(ThemedBackground())
}

#Preview("Panel — filled") {
    let spec = PanelSpec(n: 6,
                         beat: "Class: Druid. Stats: locked. The forest got a new friend.",
                         emotion: .joy,
                         position: .front)
    return PlaceholderPanelCard(spec: spec,
                                playerName: "Quinn",
                                slot: .filled(previewImage(color: .systemTeal)))
        .padding()
        .background(ThemedBackground())
}

#Preview("Triptych P-in — all spinning") {
    PlaceholderTriptychCard(kind: .pIn,
                            slots: [.spinning, .spinning, .spinning])
        .padding()
        .background(ThemedBackground())
}

#Preview("Triptych P-in — 2 filled / 1 spinning") {
    PlaceholderTriptychCard(
        kind: .pIn,
        slots: [
            .filled(previewImage(color: .systemIndigo)),
            .spinning,
            .filled(previewImage(color: .systemPink))
        ])
        .padding()
        .background(ThemedBackground())
}

#Preview("Triptych H-out — all filled") {
    PlaceholderTriptychCard(
        kind: .hOut,
        slots: [
            .filled(previewImage(color: .systemOrange)),
            .filled(previewImage(color: .systemGreen)),
            .filled(previewImage(color: .systemPurple))
        ])
        .padding()
        .background(ThemedBackground())
}

private func previewImage(color: UIColor) -> UIImage {
    let size = CGSize(width: 400, height: 400)
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { ctx in
        color.setFill()
        ctx.fill(CGRect(origin: .zero, size: size))
    }
}

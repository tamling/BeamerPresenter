import SwiftUI

/// The current slide at its true aspect ratio, with the ink layer on top and a
/// single gesture that draws when the pen is on, or navigates (tap an edge /
/// swipe) when it's off.
struct SlideView: View {
    @EnvironmentObject var model: PresentationModel

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                Color.black
                PDFPageView(document: model.document, pageIndex: model.index,
                            displayBox: model.slideBox)
                inkCanvas
                if let p = model.laserPoint {
                    LaserDot(point: p, in: size)
                }
            }
            .contentShape(Rectangle())
            .gesture(slideGesture(size))
        }
    }

    private var inkCanvas: some View {
        Canvas { ctx, sz in
            for stroke in model.strokes[model.index] ?? [] {
                ctx.stroke(path(stroke.points, in: sz),
                           with: .color(stroke.color),
                           style: lineStyle(stroke.width * sz.width))
            }
            if model.currentStroke.count > 1 {
                ctx.stroke(path(model.currentStroke, in: sz),
                           with: .color(model.penColor),
                           style: lineStyle(model.penWidth * sz.width))
            }
        }
        .allowsHitTesting(false)
    }

    /// One gesture for both modes: draw with the pen, otherwise swipe / tap-edge
    /// to move between slides.
    private func slideGesture(_ size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let p = unit(value.location, size)
                if model.penActive {
                    if model.currentStroke.isEmpty { model.beginStroke(at: p) }
                    else { model.extendStroke(to: p) }
                } else if model.laserActive {
                    model.moveLaser(to: p)
                }
            }
            .onEnded { value in
                if model.penActive {
                    model.endStroke()
                } else if model.laserActive {
                    model.endLaser()
                } else if value.translation.width < -40 {
                    model.next()
                } else if value.translation.width > 40 {
                    model.previous()
                } else {   // a tap: left half = back, right half = forward
                    value.location.x > size.width / 2 ? model.next() : model.previous()
                }
            }
    }

    private func unit(_ p: CGPoint, _ size: CGSize) -> CGPoint {
        CGPoint(x: min(max(0, p.x / size.width), 1),
                y: min(max(0, p.y / size.height), 1))
    }
}

/// A read-only slide for an external (audience) display — no gestures.
/// (Used once external-display support lands; see CHECKLIST.md.)
struct AudienceSlideView: View {
    @ObservedObject var model: PresentationModel

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                Color.black
                PDFPageView(document: model.document, pageIndex: model.index,
                            displayBox: model.slideBox)
                Canvas { ctx, sz in
                    for stroke in model.strokes[model.index] ?? [] {
                        ctx.stroke(path(stroke.points, in: sz),
                                   with: .color(stroke.color),
                                   style: lineStyle(stroke.width * sz.width))
                    }
                }
                .allowsHitTesting(false)
                if let p = model.laserPoint {
                    LaserDot(point: p, in: size)
                }
            }
        }
    }
}

/// A glowing red laser dot positioned at a unit point within `size`.
struct LaserDot: View {
    let point: CGPoint
    let size: CGSize

    init(point: CGPoint, in size: CGSize) {
        self.point = point
        self.size = size
    }

    var body: some View {
        let d = max(14, size.width * 0.018)
        Circle()
            .fill(RadialGradient(
                colors: [.white, .red, .red.opacity(0)],
                center: .center, startRadius: 0, endRadius: d))
            .frame(width: d * 2, height: d * 2)
            .shadow(color: .red.opacity(0.8), radius: d * 0.6)
            .position(x: point.x * size.width, y: point.y * size.height)
            .allowsHitTesting(false)
    }
}

func path(_ points: [CGPoint], in size: CGSize) -> Path {
    var p = Path()
    guard let first = points.first else { return p }
    p.move(to: CGPoint(x: first.x * size.width, y: first.y * size.height))
    for pt in points.dropFirst() {
        p.addLine(to: CGPoint(x: pt.x * size.width, y: pt.y * size.height))
    }
    return p
}

func lineStyle(_ width: CGFloat) -> StrokeStyle {
    StrokeStyle(lineWidth: max(1, width), lineCap: .round, lineJoin: .round)
}

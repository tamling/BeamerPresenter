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
                PDFPageView(document: model.document, pageIndex: model.index)
                inkCanvas
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
                           style: lineStyle(0.004 * sz.width))
            }
        }
        .allowsHitTesting(false)
    }

    /// One gesture for both modes: draw with the pen, otherwise swipe / tap-edge
    /// to move between slides.
    private func slideGesture(_ size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard model.penActive else { return }
                let p = unit(value.location, size)
                if model.currentStroke.isEmpty { model.beginStroke(at: p) }
                else { model.extendStroke(to: p) }
            }
            .onEnded { value in
                if model.penActive {
                    model.endStroke()
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
        ZStack {
            Color.black
            PDFPageView(document: model.document, pageIndex: model.index)
            Canvas { ctx, sz in
                for stroke in model.strokes[model.index] ?? [] {
                    ctx.stroke(path(stroke.points, in: sz),
                               with: .color(stroke.color),
                               style: lineStyle(stroke.width * sz.width))
                }
            }
            .allowsHitTesting(false)
        }
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

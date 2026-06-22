import SwiftUI
import UIKit

/// The current slide at its true aspect ratio, with the ink layer on top and a
/// single gesture that draws when the pen is on, or navigates (tap an edge /
/// swipe) when it's off.
struct SlideView: View {
    @EnvironmentObject var model: PresentationModel
    @AppStorage("pencilOnly") private var pencilOnly = false
    @State private var moveStart: CGPoint?      // item centre (unit) at drag start
    @State private var resizeStart: CGFloat?    // item width at pinch start
    @State private var keyboardTop: CGFloat = .infinity   // global Y of the keyboard top

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                if model.isBoardActive, let board = model.activeBoard {
                    BoardCanvas(board: board, liveStroke: model.boardStroke,
                                liveColor: model.penColor, liveWidth: model.penWidth,
                                liveWidths: model.boardStrokeWidths, style: model.boardStyle)
                    // Pen → Apple-Pencil-aware overlay; otherwise laser / item handling.
                    if model.penActive {
                        InkingOverlay(pencilOnly: pencilOnly, baseWidth: model.penWidth,
                            onBegin: { p, w in model.boardBeginStroke(at: p, width: w) },
                            onMove: { p, w in model.boardExtendStroke(to: p, width: w) },
                            onEnd: { model.boardEndStroke() })
                    } else {
                        Color.clear.contentShape(Rectangle()).gesture(boardGesture(size))
                    }
                    boardHandles(size)
                    if let p = model.laserPoint { LaserDot(point: p, in: size) }
                } else {
                    Color.black
                    PDFPageView(document: model.document, pageIndex: model.index,
                                displayBox: model.slideBox)
                    inkCanvas
                    if let p = model.laserPoint {
                        LaserDot(point: p, in: size)
                    }
                    if model.penActive {
                        InkingOverlay(pencilOnly: pencilOnly, baseWidth: model.penWidth,
                            onBegin: { p, w in model.beginStroke(at: p, width: w) },
                            onMove: { p, w in model.extendStroke(to: p, width: w) },
                            onEnd: { model.endStroke() })
                    } else {
                        Color.clear.contentShape(Rectangle()).gesture(slideGesture(size))
                    }
                }
                if model.blackout {
                    Color.black.opacity(0.35).allowsHitTesting(false)
                    VStack {
                        Label("Audience screen blacked out", systemImage: "eye.slash.fill")
                            .font(.callout.weight(.semibold))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(.top, 16)
                        Spacer()
                    }
                    .allowsHitTesting(false)
                }
            }
            .coordinateSpace(name: "board")
            .offset(y: -keyboardShift(geo.frame(in: .global), size))
            .animation(.easeOut(duration: 0.25), value: keyboardTop)
            .slideSwitch(index: model.index, forward: model.forward)
            .onReceive(NotificationCenter.default.publisher(
                for: UIResponder.keyboardWillChangeFrameNotification)) { note in
                if let f = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                    keyboardTop = f.minY
                }
            }
            .onReceive(NotificationCenter.default.publisher(
                for: UIResponder.keyboardWillHideNotification)) { _ in
                keyboardTop = .infinity
            }
        }
    }

    /// How far to lift the board so the selected table's cells clear the keyboard.
    private func keyboardShift(_ globalFrame: CGRect, _ size: CGSize) -> CGFloat {
        guard keyboardTop.isFinite, model.isBoardActive,
              let item = model.selectedItem(), item.kind == .table else { return 0 }
        let rows = max(1, item.text.split(separator: "\n", omittingEmptySubsequences: false).count)
        let fontSize = max(6, item.fontScale * size.width)
        let tableHeight = CGFloat(rows) * fontSize * 1.7
        let tableBottom = globalFrame.minY + item.center.y * size.height + tableHeight / 2
        return max(0, tableBottom - (keyboardTop - 16))
    }

    // MARK: - Board interaction

    /// Laser on the board (pen is handled by the overlay); tapping empty space
    /// deselects the current item.
    private func boardGesture(_ size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if model.laserActive { model.moveLaser(to: unit(value.location, size)) }
            }
            .onEnded { _ in
                if model.laserActive { model.endLaser() }
                else { model.selectedItemID = nil }
            }
    }

    /// Move / resize / delete handles for items, shown when neither pen nor laser
    /// is the active tool.
    @ViewBuilder
    private func boardHandles(_ size: CGSize) -> some View {
        if !model.penActive, !model.laserActive, let board = model.activeBoard {
            ForEach(board.items) { item in
                let center = CGPoint(x: item.center.x * size.width, y: item.center.y * size.height)
                let half = item.width * size.width / 2
                let w = max(72, item.width * size.width)
                let h = max(58, item.width * size.width * 0.55)
                let selected = model.selectedItemID == item.id

                if selected && item.kind == .table {
                    // Editable cells: tap a cell and type. Move via the grip handle.
                    TableEditor(text: item.text,
                                width: max(8, item.width * size.width),
                                fontSize: max(6, item.fontScale * size.width),
                                onChange: { model.updateItemText(item.id, $0) })
                        .id(item.id)
                        .position(center)
                    moveGrip(item, at: CGPoint(x: center.x - half - 20, y: center.y - h / 2 - 4), size: size)
                } else {
                    // Grab the item itself: drag to move, pinch to resize, tap to select.
                    Rectangle()
                        .fill(Color.white.opacity(0.001))
                        .frame(width: w, height: h)
                        .overlay {
                            if selected {
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(Color.accentColor, lineWidth: 2)
                            }
                        }
                        .contentShape(Rectangle())
                        .position(center)
                        .onTapGesture { model.selectedItemID = item.id }
                        .gesture(moveDrag(item, size))
                        .simultaneousGesture(pinch(item))
                }

                // Big delete button at the top-right corner.
                Button { model.deleteItem(item.id) } label: {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white).frame(width: 36, height: 36)
                        .background(Circle().fill(Color.red))
                }
                .position(x: center.x + max(half, w / 2) + 20, y: center.y - h / 2 - 4)

                // Big corner resize handle (drag), when selected.
                if selected {
                    RoundedRectangle(cornerRadius: 8).fill(Color.accentColor)
                        .overlay(Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 13, weight: .bold)).foregroundStyle(.white))
                        .frame(width: 36, height: 36)
                        .position(x: center.x + max(half, w / 2) + 20, y: center.y + h / 2 + 4)
                        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("board"))
                            .onChanged { v in
                                let dx = abs(v.location.x - center.x)
                                model.setItemWidth(item.id, (dx * 2) / max(size.width, 1))
                            })
                }
            }
        }
    }

    /// Translation-based move (no jump regardless of where the item is grabbed).
    private func moveDrag(_ item: BoardItem, _ size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("board"))
            .onChanged { v in
                model.selectedItemID = item.id
                let base = moveStart ?? item.center
                if moveStart == nil { moveStart = base }
                model.moveItem(item.id, to: CGPoint(
                    x: base.x + v.translation.width / size.width,
                    y: base.y + v.translation.height / size.height))
            }
            .onEnded { _ in moveStart = nil }
    }

    /// Pinch to resize the item (scales from the width at gesture start).
    private func pinch(_ item: BoardItem) -> some Gesture {
        MagnificationGesture()
            .onChanged { scale in
                model.selectedItemID = item.id
                let base = resizeStart ?? item.width
                if resizeStart == nil { resizeStart = base }
                model.setItemWidth(item.id, base * scale)
            }
            .onEnded { _ in resizeStart = nil }
    }

    /// A draggable grip used to move a table while its cells stay editable.
    private func moveGrip(_ item: BoardItem, at p: CGPoint, size: CGSize) -> some View {
        RoundedRectangle(cornerRadius: 8).fill(Color.accentColor)
            .overlay(Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                .font(.system(size: 13, weight: .bold)).foregroundStyle(.white))
            .frame(width: 36, height: 36)
            .position(p)
            .gesture(moveDrag(item, size))
    }

    private var inkCanvas: some View {
        Canvas { ctx, sz in
            for stroke in model.strokes[model.index] ?? [] {
                drawStroke(ctx, points: stroke.points, widths: stroke.pointWidths,
                           baseWidth: stroke.width, color: stroke.color, in: sz)
            }
            drawStroke(ctx, points: model.currentStroke, widths: model.currentWidths,
                       baseWidth: model.penWidth, color: model.penColor, in: sz)
        }
        .allowsHitTesting(false)
    }

    /// Navigation / laser when the pen is off (pen is handled by the overlay):
    /// swipe or tap an edge to move between slides.
    private func slideGesture(_ size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if model.laserActive { model.moveLaser(to: unit(value.location, size)) }
            }
            .onEnded { value in
                if model.laserActive {
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
                if model.mentiActive, let url = model.mentiPresentURL {
                    MentiAudienceView(url: url)
                } else if let board = model.activeBoard {
                    BoardCanvas(board: board, style: model.boardStyle)
                } else {
                    Color.black
                    PDFPageView(document: model.document, pageIndex: model.index,
                                displayBox: model.slideBox)
                    Canvas { ctx, sz in
                        for stroke in model.strokes[model.index] ?? [] {
                            drawStroke(ctx, points: stroke.points, widths: stroke.pointWidths,
                                       baseWidth: stroke.width, color: stroke.color, in: sz)
                        }
                    }
                    .allowsHitTesting(false)
                }
                if let p = model.laserPoint {
                    LaserDot(point: p, in: size)
                }
                if model.blackout {
                    BlackoutView(model: model)
                }
            }
            .slideSwitch(index: model.index, forward: model.forward)
        }
    }
}

/// A small switch animation when the slide index changes: the new slide nudges
/// in from the side (direction of travel) with a brief fade.
private struct SlideSwitch: ViewModifier {
    let index: Int
    let forward: Bool
    @State private var offset: CGFloat = 0
    @State private var opacity: Double = 1

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .opacity(opacity)
            .onChange(of: index) { _ in
                offset = forward ? 34 : -34
                opacity = 0.55
                withAnimation(.easeOut(duration: 0.28)) {
                    offset = 0
                    opacity = 1
                }
            }
    }
}

extension View {
    func slideSwitch(index: Int, forward: Bool) -> some View {
        modifier(SlideSwitch(index: index, forward: forward))
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

/// Draws an ink stroke into a `GraphicsContext`. With per-point widths (Apple
/// Pencil pressure) each segment is stroked at the mean of its endpoints'
/// widths; otherwise the whole polyline is stroked at `baseWidth`.
func drawStroke(_ ctx: GraphicsContext, points: [CGPoint], widths: [CGFloat],
                baseWidth: CGFloat, color: Color, in size: CGSize) {
    guard points.count > 1 else { return }
    if widths.count == points.count {
        for i in 1..<points.count {
            var seg = Path()
            seg.move(to: CGPoint(x: points[i - 1].x * size.width, y: points[i - 1].y * size.height))
            seg.addLine(to: CGPoint(x: points[i].x * size.width, y: points[i].y * size.height))
            ctx.stroke(seg, with: .color(color),
                       style: lineStyle((widths[i - 1] + widths[i]) / 2 * size.width))
        }
    } else {
        ctx.stroke(path(points, in: size), with: .color(color),
                   style: lineStyle(baseWidth * size.width))
    }
}

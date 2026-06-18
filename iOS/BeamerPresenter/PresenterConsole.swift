import SwiftUI

/// The macOS-style presenter console used on a wide (landscape / regular-width)
/// iPad: the current slide on the left, and a resizable right column with the
/// **next** slide on top, the **speaker notes** below it, and your **own notes**
/// at the bottom. All three dividers are draggable and the sizes persist.
struct PresenterConsole: View {
    @EnvironmentObject var model: PresentationModel

    @AppStorage("consoleSidebarWidth") private var sidebarWidth: Double = 380
    @AppStorage("consoleNotesFraction") private var notesFraction: Double = 0.5

    @State private var sidebarStart: Double?
    @State private var notesStart: Double?

    private let sidebarRange = 280.0...760.0
    private let notesRange = 0.15...0.85

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Current slide").font(.mono(9)).textCase(.uppercase).tracking(1.6)
                        .foregroundStyle(Theme.textMuted)
                    Spacer()
                    LivePill()
                }
                SlideView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(8)
                    .background(Theme.stage)
                    .clipShape(RoundedRectangle(cornerRadius: 11))
                    .overlay(RoundedRectangle(cornerRadius: 11).stroke(Theme.hairline, lineWidth: 1))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Drag to resize the side column (it's to the right, so dragging right shrinks it).
            ResizeHandle(axis: .horizontal) { t in
                let start = sidebarStart ?? sidebarWidth
                sidebarStart = start
                sidebarWidth = (start - Double(t)).clamped(to: sidebarRange)
            } onEnded: { sidebarStart = nil }

            sideColumn.frame(width: sidebarWidth)
        }
        .padding(8)
    }

    private var sideColumn: some View {
        GeometryReader { geo in
            let handle: CGFloat = 12
            let avail = max(0, geo.size.height - handle)
            let notesH = avail * notesFraction
            let nextH = avail - notesH

            VStack(spacing: 0) {
                // Tap the next-slide preview to advance to it.
                Button { model.next() } label: {
                    pane("Next slide") {
                        StaticSlideView(index: model.index + 1)
                            .opacity(model.index + 1 < model.pageCount ? 1 : 0.25)
                    }
                }
                .buttonStyle(.plain)
                .disabled(model.index + 1 >= model.pageCount)
                .frame(height: nextH)

                ResizeHandle(axis: .vertical) { t in
                    let start = notesStart ?? notesFraction
                    notesStart = start
                    notesFraction = (start - Double(t) / Double(max(avail, 1))).clamped(to: notesRange)
                } onEnded: { notesStart = nil }

                NotesPanel()
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .frame(height: notesH)
            }
        }
    }

    private func pane<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.mono(9)).textCase(.uppercase).tracking(1.6)
                .foregroundStyle(Theme.textMuted)
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(8)
                .background(Theme.stage)
                .clipShape(RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(Theme.hairline, lineWidth: 1))
        }
    }
}

/// A read-only slide at a fixed index (used for the "Next" preview).
struct StaticSlideView: View {
    @EnvironmentObject var model: PresentationModel
    let index: Int

    var body: some View {
        ZStack {
            Color.black
            if index >= 0, index < model.pageCount {
                PDFPageView(document: model.document, pageIndex: index, displayBox: model.slideBox)
            }
        }
    }
}

/// A thin, draggable divider that reports cumulative translation along its axis.
struct ResizeHandle: View {
    enum Axis { case horizontal, vertical }   // horizontal = a vertical bar dragged left/right
    let axis: Axis
    let onChanged: (CGFloat) -> Void
    let onEnded: () -> Void

    private var isHorizontal: Bool { axis == .horizontal }

    var body: some View {
        ZStack {
            Color.clear
            RoundedRectangle(cornerRadius: 2)
                .fill(Theme.hairlineStrong)
                .frame(width: isHorizontal ? 4 : 44, height: isHorizontal ? 44 : 4)
        }
        .frame(width: isHorizontal ? 12 : nil, height: isHorizontal ? nil : 12)
        .frame(maxWidth: isHorizontal ? nil : .infinity,
               maxHeight: isHorizontal ? .infinity : nil)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { onChanged(isHorizontal ? $0.translation.width : $0.translation.height) }
                .onEnded { _ in onEnded() }
        )
    }
}

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

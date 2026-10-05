import SwiftUI
import Combine

/// What the projector/external display shows: the slide full-bleed, the active
/// whiteboard, or — when blacked out (press `B`) — a black screen with an
/// optional centered message, falling back to the clock.
struct AudienceView: View {
    @EnvironmentObject var state: PresentationState
    @AppStorage("blackScreenMessage") private var blackMessage = ""

    var body: some View {
        ZStack {
            Color.black
            if state.mentiActive, let url = state.mentiPresentURL {
                MentiAudienceView(url: url)
            } else if let board = state.activeBoard {
                BoardCanvas(board: board, style: state.boardStyle)
                    .aspectRatio(state.slideAspect, contentMode: .fit)
                    .overlay {
                        if let laser = state.laserPoint {
                            BoardLaserDot(point: laser, color: state.penColor)
                        }
                    }
            } else {
                SlideView(pageIndex: state.index, interactive: false)
            }
            // Black-out is an overlay so `B` also covers a live Mentimeter poll
            // (without tearing down the web view / losing the session underneath).
            if state.blackout {
                BlackScreenView(message: blackMessage)
            }
        }
        .ignoresSafeArea()
    }
}

/// The blacked-out audience screen: an optional background image, an optional
/// centered message, and the clock (large on its own, or smaller beneath the
/// message). Sized relative to the screen so it reads from the back row.
private struct BlackScreenView: View {
    let message: String
    @AppStorage("blackScreenImage") private var imagePath = ""

    @State private var now = Date()
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var trimmed: String { message.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var hasMessage: Bool { !trimmed.isEmpty }

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                Theme.blackout
                if let image = backgroundImage {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                    Color.black.opacity(0.45)   // keep the text legible
                }

                VStack(spacing: s * 0.035) {
                    // Just the quiet pulsing dot — no label.
                    PulsingDot(size: max(7, s * 0.012))
                    if hasMessage {
                        Text(trimmed)
                            .font(.display(s * 0.10))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white)
                    }
                    Text(now, style: .time)
                        .font(.mono(s * (hasMessage ? 0.07 : 0.15), bold: true))
                        .foregroundStyle(Theme.textFaint)
                }
                .padding(s * 0.08)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .onReceive(tick) { now = $0 }
    }

    private var backgroundImage: NSImage? {
        guard !imagePath.isEmpty else { return nil }
        return NSImage(contentsOfFile: imagePath)
    }
}

/// The blackout screen's breathing status dot. Driven by a `TimelineView`
/// computing the opacity from the wall clock, so the pulse stays perfectly
/// smooth no matter how often the surrounding view re-renders (the clock
/// updating every second used to stutter the old `repeatForever` animation).
struct PulsingDot: View {
    var size: CGFloat
    var period: Double = 2.8   // seconds for a full bright-dim-bright cycle

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let phase = (sin(t * 2 * .pi / period) + 1) / 2
            Circle().fill(Theme.statusOk)
                .frame(width: size, height: size)
                .shadow(color: Theme.statusOk.opacity(0.7), radius: 4)
                .opacity(0.2 + 0.8 * phase)
        }
    }
}

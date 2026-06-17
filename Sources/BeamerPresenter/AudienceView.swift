import SwiftUI

/// What the projector/external display shows: the slide full-bleed, the active
/// whiteboard, or — when blacked out (press `B`) — a black screen with an
/// optional centered message, falling back to the clock.
struct AudienceView: View {
    @EnvironmentObject var state: PresentationState
    @AppStorage("blackScreenMessage") private var blackMessage = ""

    var body: some View {
        ZStack {
            Color.black
            if let board = state.activeBoard {
                BoardCanvas(board: board)
                    .aspectRatio(state.slideAspect, contentMode: .fit)
            } else if state.blackout {
                BlackScreenView(message: blackMessage)
            } else {
                SlideView(pageIndex: state.index, interactive: false)
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
                if let image = backgroundImage {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                    Color.black.opacity(0.4)   // keep the text legible
                }

                VStack(spacing: s * 0.04) {
                    if hasMessage {
                        Text(trimmed)
                            .font(.system(size: s * 0.11, weight: .semibold, design: .rounded))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white)
                    }
                    Text(now, style: .time)
                        .font(.system(size: s * (hasMessage ? 0.07 : 0.16),
                                      weight: .light, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white.opacity(hasMessage ? 0.7 : 0.82))
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

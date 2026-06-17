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

/// The blacked-out audience screen: a centered message if one is set, otherwise
/// the current time. Sized relative to the screen so it reads from the back row.
private struct BlackScreenView: View {
    let message: String

    @State private var now = Date()
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var trimmed: String { message.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            Group {
                if trimmed.isEmpty {
                    Text(now, style: .time)
                        .font(.system(size: s * 0.16, weight: .light, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.82))
                } else {
                    Text(trimmed)
                        .font(.system(size: s * 0.11, weight: .semibold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .padding(s * 0.08)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .onReceive(tick) { now = $0 }
    }
}

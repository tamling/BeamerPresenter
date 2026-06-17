import SwiftUI

/// What the projector/external display shows: just the slide, full-bleed, with a
/// black-out toggle (press `B`).
struct AudienceView: View {
    @EnvironmentObject var state: PresentationState

    var body: some View {
        ZStack {
            Color.black
            if let board = state.activeBoard {
                BoardCanvas(board: board)
                    .aspectRatio(state.slideAspect, contentMode: .fit)
            } else if !state.blackout {
                SlideView(pageIndex: state.index, interactive: false)
            }
        }
        .ignoresSafeArea()
    }
}

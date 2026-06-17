import SwiftUI

/// A compact stopwatch (start / pause / reset) plus the wall clock, refreshed
/// every second via `TimelineView` so the rest of the UI isn't re-rendered.
struct TimerControls: View {
    @EnvironmentObject var model: PresentationModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            HStack(spacing: 10) {
                Button { model.toggleTimer() } label: {
                    Image(systemName: model.timerRunning ? "pause.fill" : "play.fill")
                }
                Text(Self.elapsedString(model.elapsed))
                    .font(.headline.monospacedDigit())
                    .frame(minWidth: 64)
                Button { model.resetTimer() } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                Divider().frame(height: 18)
                Text(Self.clockString())
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    static func elapsedString(_ t: TimeInterval) -> String {
        let s = max(0, Int(t))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec)
                     : String(format: "%02d:%02d", m, sec)
    }

    static func clockString() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: Date())
    }
}

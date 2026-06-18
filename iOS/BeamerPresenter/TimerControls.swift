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
                    .lineLimit(1).fixedSize()
                    .frame(minWidth: 64)
                Button { model.resetTimer() } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                Divider().frame(height: 18)
                Text(Self.clockString())
                    .font(.subheadline.monospacedDigit())
                    .lineLimit(1).fixedSize()
                    .foregroundStyle(.secondary)
                if let remaining = model.remaining {
                    Divider().frame(height: 18)
                    Image(systemName: "hourglass").font(.caption2).foregroundStyle(.secondary)
                    Text(Self.remainingString(remaining))
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .lineLimit(1).fixedSize()
                        .foregroundStyle(remaining < 0 ? .red : (remaining <= 300 ? .orange : .secondary))
                }
            }
        }
    }

    static func elapsedString(_ t: TimeInterval) -> String {
        let s = max(0, Int(t))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec)
                     : String(format: "%02d:%02d", m, sec)
    }

    /// Countdown form: time left ("MM:SS"), or "+MM:SS" once the target is passed.
    static func remainingString(_ t: TimeInterval) -> String {
        let over = t < -0.5
        let s = abs(Int(t.rounded()))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        let body = h > 0 ? String(format: "%d:%02d:%02d", h, m, sec)
                         : String(format: "%02d:%02d", m, sec)
        return (over ? "+" : "") + body
    }

    static func clockString() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: Date())
    }
}

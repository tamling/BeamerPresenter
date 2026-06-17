import SwiftUI

/// The audience black-out screen: solid black with an optional centred message
/// and a quiet clock. Shown on the external display (and as the presenter's
/// overlay) while `model.blackout` is on.
struct BlackoutView: View {
    @ObservedObject var model: PresentationModel

    var body: some View {
        ZStack {
            Color.black
            VStack(spacing: 24) {
                if !model.blackoutMessage.isEmpty {
                    Text(model.blackoutMessage)
                        .font(.system(size: 64, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 40)
                }
                if model.blackoutShowClock {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text(Self.clock())
                            .font(.system(size: model.blackoutMessage.isEmpty ? 96 : 44,
                                          weight: .light).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
            }
        }
        .ignoresSafeArea()
    }

    static func clock() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: Date())
    }

    /// Quick away-messages, mirroring the macOS black-screen presets.
    static let presets = ["Be right back", "Break", "Questions?",
                          "Please wait", "Thank you"]
}

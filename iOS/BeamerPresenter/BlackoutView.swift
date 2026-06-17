import SwiftUI

/// The audience black-out screen: solid black with an optional centred message
/// and a quiet clock. Shown on the external display (and as the presenter's
/// overlay) while `model.blackout` is on.
struct BlackoutView: View {
    @ObservedObject var model: PresentationModel

    @AppStorage("blackoutMessage") private var message = ""
    @AppStorage("blackoutShowClock") private var showClock = true
    @AppStorage("blackoutImagePath") private var imagePath = ""

    var body: some View {
        ZStack {
            Color.black
            if let image = backgroundImage {
                Image(uiImage: image).resizable().scaledToFit()
            }
            VStack(spacing: 24) {
                if !message.isEmpty {
                    Text(message)
                        .font(.system(size: 64, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 40)
                        .shadow(radius: 8)
                }
                if showClock {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text(Self.clock())
                            .font(.system(size: message.isEmpty ? 96 : 44,
                                          weight: .light).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.85))
                            .shadow(radius: 8)
                    }
                }
            }
        }
        .ignoresSafeArea()
    }

    private var backgroundImage: UIImage? {
        imagePath.isEmpty ? nil : UIImage(contentsOfFile: imagePath)
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

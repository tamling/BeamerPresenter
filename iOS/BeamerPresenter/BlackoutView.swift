import SwiftUI

/// The audience black-out screen: solid black with an optional centred message
/// and a quiet clock. Shown on the external display (and as the presenter's
/// overlay) while `model.blackout` is on.
struct BlackoutView: View {
    @ObservedObject var model: PresentationModel

    @AppStorage("blackoutMessage") private var message = ""
    @AppStorage("blackoutShowClock") private var showClock = true
    @AppStorage("blackoutImagePath") private var imagePath = ""
    @State private var dotOn = true

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                Theme.blackout
                if let image = backgroundImage {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height).clipped()
                    Color.black.opacity(0.45)
                }
                VStack(spacing: s * 0.035) {
                    // Just the quiet pulsing dot — no label.
                    Circle().fill(Theme.statusOk)
                        .frame(width: max(7, s * 0.012), height: max(7, s * 0.012))
                        .shadow(color: Theme.statusOk.opacity(0.7), radius: 4)
                        .opacity(dotOn ? 1 : 0.2)
                        .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: dotOn)
                        .onAppear { dotOn.toggle() }
                    if !message.isEmpty {
                        Text(message)
                            .font(.display(s * 0.10))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 40)
                    }
                    if showClock {
                        TimelineView(.periodic(from: .now, by: 1)) { _ in
                            Text(Self.clock())
                                .font(.mono(s * (message.isEmpty ? 0.15 : 0.07), bold: true))
                                .foregroundStyle(Theme.textFaint)
                        }
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
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
    static let presets = ["Back in 5 minutes", "Back in 10 minutes",
                          "Back in 15 minutes", "Short break",
                          "Lunch break", "Back soon"]
}

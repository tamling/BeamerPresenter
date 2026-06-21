import SwiftUI

/// Turns this device (e.g. an iPhone) into a remote for a presenting iPad on the
/// same Wi-Fi: big previous/next, the current slide number and speaker note, and
/// black-out / timer controls — discovered and connected automatically.
struct RemoteView: View {
    @StateObject private var link = RemoteLink(role: .remote)
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""

    var body: some View {
        NavigationStack {
            Group {
                if link.connected {
                    if let state = link.presenterState {
                        connected(state)
                    } else {
                        waiting("Connecting…")
                    }
                } else if link.foundPresenter {
                    pairing
                } else {
                    searching
                }
            }
            .navigationTitle("Remote")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { link.start() }
        .onDisappear { link.stop() }
    }

    private var searching: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
            Text("Looking for a presentation…").font(.headline)
            Text("Open a deck in BeamerPresenter on your iPad, on the same Wi-Fi.")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(40)
    }

    private func waiting(_ text: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
            Text(text).font(.headline)
            Spacer()
        }
        .padding(40)
    }

    /// Presenter found: ask for the 4-digit code shown on the iPad before connecting.
    private var pairing: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "lock.shield").font(.system(size: 40, weight: .semibold))
                .foregroundStyle(Color.brand)
            Text("Enter pairing code").font(.headline)
            Text("Type the 4-digit code shown on the iPad.")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            TextField("0000", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .multilineTextAlignment(.center)
                .font(.system(size: 38, design: .rounded).weight(.semibold).monospacedDigit())
                .frame(width: 180)
                .padding(.vertical, 10)
                .background(Color(white: 0.14), in: RoundedRectangle(cornerRadius: 12))
                .onChange(of: code) { newValue in
                    code = String(newValue.filter(\.isNumber).prefix(4))
                    if code.count == 4 { link.connect(code: code) }
                }

            if link.pairingFailed {
                Text("Wrong code — try again.").font(.subheadline).foregroundStyle(.red)
            }

            Button("Connect") { link.connect(code: code) }
                .buttonStyle(.borderedProminent)
                .disabled(code.count != 4)
            Spacer()
        }
        .padding(40)
    }

    private func connected(_ s: PresenterState) -> some View {
        VStack(spacing: 18) {
            VStack(spacing: 4) {
                Text(s.title.isEmpty ? "Presentation" : s.title)
                    .font(.headline).lineLimit(1)
                Text("\(s.index + 1) / \(s.pageCount)")
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold).monospacedDigit())
            }

            // Speaker note for the current slide.
            ScrollView {
                Text(s.note.isEmpty ? "—" : s.note)
                    .font(.title3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(s.note.isEmpty ? .secondary : .primary)
            }
            .frame(maxWidth: .infinity)
            .padding(14)
            .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 12))

            // Big prev / next.
            HStack(spacing: 14) {
                bigButton("chevron.left", "Prev") { link.send(command: .previous) }
                bigButton("chevron.right", "Next") { link.send(command: .next) }
            }

            // Secondary controls.
            HStack(spacing: 14) {
                pill(s.blackout ? "eye.slash.fill" : "eye.slash", "Black-out",
                     active: s.blackout) { link.send(command: .blackout) }
                pill(s.timerRunning ? "pause.fill" : "play.fill",
                     TimerControls.elapsedString(Double(s.elapsed)),
                     active: s.timerRunning) { link.send(command: .toggleTimer) }
                pill("arrow.counterclockwise", "Reset") { link.send(command: .resetTimer) }
            }
        }
        .padding(20)
    }

    private func bigButton(_ icon: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 40, weight: .semibold))
                Text(title).font(.headline)
            }
            .frame(maxWidth: .infinity).frame(height: 130)
            .background(Color.brand.opacity(0.9), in: RoundedRectangle(cornerRadius: 16))
            .foregroundStyle(.white)
        }
    }

    private func pill(_ icon: String, _ title: String, active: Bool = false,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.title3)
                Text(title).font(.caption.monospacedDigit())
            }
            .frame(maxWidth: .infinity).frame(height: 64)
            .background(Color(white: 0.15), in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(active ? Color.accentColor : .primary)
        }
    }
}

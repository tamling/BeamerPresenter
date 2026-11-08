import SwiftUI

/// Turns this device (e.g. an iPhone) into a remote for a presenting iPad on the
/// same Wi-Fi: big previous/next, the current slide number and speaker note, and
/// black-out / timer controls. Nearby iPads are listed; pick one, then enter
/// the code it shows — the code only ever goes to the iPad you picked.
struct RemoteView: View {
    @StateObject private var link = RemoteLink(role: .remote)
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    /// The presenter the user picked from the list; nil shows the list.
    @State private var selected: RemoteLink.FoundPresenter?

    var body: some View {
        NavigationStack {
            Group {
                if link.connected {
                    if let state = link.presenterState {
                        connected(state)
                    } else {
                        waiting("Connecting…")
                    }
                } else if let presenter = selected {
                    pairing(presenter)
                } else if !link.presenters.isEmpty {
                    picker
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
        // The picked iPad went away: back to the list.
        .onChange(of: link.presenters.map(\.id)) { ids in
            if let s = selected, !ids.contains(s.id) { link.cancelPairing(); selected = nil; code = "" }
        }
        .onChange(of: link.pairingFailed) { failed in
            if failed { code = "" }
        }
        // The code is single-use on the iPad; never leave a spent one in the field.
        .onChange(of: link.connected) { isConnected in
            if isConnected { code = "" }
        }
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

    /// Presenters found: let the user pick which iPad to pair with.
    private var picker: some View {
        List(link.presenters) { p in
            Button {
                code = ""
                selected = p
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.name).font(.headline)
                    if let title = p.title, !title.isEmpty {
                        Text(title).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        }
    }

    /// Presenter picked: ask for the 6-digit code shown on that iPad before connecting.
    private func pairing(_ presenter: RemoteLink.FoundPresenter) -> some View {
        VStack(spacing: 18) {
            HStack {
                Button { link.cancelPairing(); selected = nil; code = "" } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                Spacer()
            }
            Spacer()
            Image(systemName: "lock.shield").font(.system(size: 40, weight: .semibold))
                .foregroundStyle(Color.brand)
            Text("Enter pairing code").font(.headline)
            Text("Type the 6-digit code shown on \(presenter.name).")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            TextField("000000", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .multilineTextAlignment(.center)
                .font(.system(size: 38, design: .rounded).weight(.semibold).monospacedDigit())
                .frame(width: 180)
                .padding(.vertical, 10)
                .background(Color(white: 0.14), in: RoundedRectangle(cornerRadius: 12))
                .onChange(of: code) { newValue in
                    let digits = String(newValue.filter { $0.isASCII && $0.isNumber }.prefix(PairingCode.length))
                    // Rewriting the field re-runs onChange; connect only on the clean pass.
                    guard digits == newValue else { code = digits; return }
                    if digits.count == PairingCode.length { link.connect(to: presenter, code: digits) }
                }

            if link.pairingFailed {
                Text("Wrong code — try again.").font(.subheadline).foregroundStyle(.red)
            }

            Button("Connect") { link.connect(to: presenter, code: code) }
                .buttonStyle(.borderedProminent)
                .disabled(code.count != PairingCode.length || link.isInviting)
            Spacer()
        }
        .padding(40)
    }

    private func connected(_ state: PresenterState) -> some View {
        // Clamp again here so the label math can never overflow or go out of range.
        let s = state.sanitized()
        return VStack(spacing: 18) {
            VStack(spacing: 4) {
                Text(s.title.isEmpty ? "Presentation" : s.title)
                    .font(.headline).lineLimit(1)
                Text(s.pageCount == 0 ? "– / –" : "\(s.index + 1) / \(s.pageCount)")
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

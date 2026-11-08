import Foundation
import UIKit
import MultipeerConnectivity

/// Peer-to-peer link between an iPhone remote and the presenting iPad, built on
/// MultipeerConnectivity (Wi-Fi / Bluetooth, no server, auto-discovery,
/// encrypted). One instance acts either as the **presenter** (advertises, shows
/// a pairing code, accepts only a remote that sends the matching code, applies
/// its commands, pushes state) or the **remote** (browses for presenters, lets
/// the user pick one, asks for its code, sends commands, shows the pushed state).
///
/// Pairing: the presenter generates a random 6-digit code and shows it on its
/// screen. The remote must send that exact code in the invitation `context`;
/// the advertiser rejects any invitation whose code does not match. A code is
/// single-use (rotated after every successful pairing), five wrong codes in a
/// row rotate it and lock pairing for 30 s, and the presenter stops advertising
/// while a remote is connected. The remote only ever sends the code to the one
/// presenter the user picked, so a rogue advertiser cannot harvest it.
@MainActor
final class RemoteLink: NSObject, ObservableObject {
    enum Role { case presenter, remote }

    /// Remote side: a presenter seen while browsing, for the picker.
    struct FoundPresenter: Identifiable {
        let peerID: MCPeerID
        let name: String
        let title: String?
        var id: ObjectIdentifier { ObjectIdentifier(peerID) }
    }

    @Published private(set) var connected = false
    @Published private(set) var peerName: String?
    @Published private(set) var presenterState: PresenterState?   // remote side

    /// Presenter side: the 6-digit code to show on screen; the remote must enter it.
    @Published private(set) var pairingCode = ""
    /// Presenter side: too many wrong codes — pairing is paused for a moment.
    @Published private(set) var lockedOut = false
    /// Remote side: presenters discovered nearby; the user picks one.
    @Published private(set) var presenters: [FoundPresenter] = []
    /// Remote side: the last pairing attempt was rejected (wrong code) — let the user retry.
    @Published private(set) var pairingFailed = false

    /// Presenter side: called when a command arrives from the remote.
    var onCommand: ((RemoteCommand) -> Void)?

    private let role: Role
    private let serviceType = "bp-remote"
    private let myPeerID = MCPeerID(displayName: String(UIDevice.current.name.prefix(60)))
    private lazy var session: MCSession = {
        let s = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        s.delegate = self
        return s
    }()
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    // Presenter side: lockout bookkeeping. `isStarted` keeps a late delegate
    // callback from re-advertising after stop().
    private static let maxFailedAttempts = 5
    private static let lockoutSeconds: UInt64 = 30
    private var isStarted = false
    private var failedAttempts = 0
    private var lockoutTask: Task<Void, Never>?
    private var isAdvertising = false

    // Remote side: the presenter we invited, and a counter so a stale timeout
    // task cannot flag a later attempt as failed.
    private var invitedPeer: MCPeerID?
    private var inviteGeneration = 0

    init(role: Role) { self.role = role; super.init() }

    func start(title: String = "") {
        isStarted = true
        switch role {
        case .presenter:
            pairingCode = PairingCode.make()
            let info = title.isEmpty ? nil : ["title": String(title.prefix(60))]
            let a = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: info, serviceType: serviceType)
            a.delegate = self
            advertiser = a
            startAdvertising()
        case .remote:
            let b = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
            b.delegate = self
            b.startBrowsingForPeers()
            browser = b
        }
    }

    func stop() {
        isStarted = false
        lockoutTask?.cancel(); lockoutTask = nil
        stopAdvertising(); advertiser = nil
        browser?.stopBrowsingForPeers(); browser = nil
        session.disconnect()
        connected = false; peerName = nil; presenterState = nil
        pairingCode = ""; lockedOut = false; failedAttempts = 0
        presenters.removeAll(); pairingFailed = false
        invitedPeer = nil; inviteGeneration &+= 1
    }

    // MARK: Presenter side

    private func startAdvertising() {
        guard isStarted, !lockedOut, !connected, !isAdvertising, let advertiser else { return }
        advertiser.startAdvertisingPeer()
        isAdvertising = true
    }

    private func stopAdvertising() {
        guard isAdvertising else { return }
        advertiser?.stopAdvertisingPeer()
        isAdvertising = false
    }

    private func rotateCode() { pairingCode = PairingCode.make() }

    /// Decides one invitation. Returns whether to accept it.
    private func shouldAccept(context: Data?) -> Bool {
        guard role == .presenter, isStarted, !lockedOut,
              !connected, session.connectedPeers.isEmpty else { return false }
        // A 6-digit code is 6 bytes; refuse anything bigger before decoding it.
        guard let context, context.count <= 16,
              let sent = String(data: context, encoding: .utf8) else { return registerFailure() }
        guard !pairingCode.isEmpty, PairingCode.matches(sent, pairingCode) else { return registerFailure() }
        failedAttempts = 0
        rotateCode()        // the code is consumed by this pairing
        stopAdvertising()   // one remote at a time
        return true
    }

    /// Counts a wrong code; after `maxFailedAttempts` in a row rotates the code
    /// and pauses pairing for `lockoutSeconds`. Always returns false.
    private func registerFailure() -> Bool {
        failedAttempts += 1
        guard failedAttempts >= Self.maxFailedAttempts else { return false }
        failedAttempts = 0
        rotateCode()
        lockedOut = true
        stopAdvertising()
        lockoutTask?.cancel()
        lockoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.lockoutSeconds * 1_000_000_000)
            guard let self, !Task.isCancelled, self.isStarted else { return }
            self.lockedOut = false
            self.lockoutTask = nil
            self.startAdvertising()
        }
        return false
    }

    // MARK: Remote side

    /// Remote side: try to pair with the presenter the user picked, using `code`.
    /// The code is sent to that one peer only — never broadcast to every advertiser.
    func connect(to presenter: FoundPresenter, code: String) {
        let trimmed = code.trimmingCharacters(in: .whitespaces)
        guard role == .remote, PairingCode.isWellFormed(trimmed),
              presenters.contains(where: { $0.peerID == presenter.peerID }) else { return }
        pairingFailed = false
        inviteGeneration &+= 1
        let generation = inviteGeneration
        invitedPeer = presenter.peerID
        browser?.invitePeer(presenter.peerID, to: session, withContext: Data(trimmed.utf8), timeout: 12)
        // A declined invitation gives no browser callback, so flag a wrong code by timeout.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 13_000_000_000)
            guard let self, self.inviteGeneration == generation,
                  self.invitedPeer != nil, !self.connected else { return }
            self.pairingFailed = true
            self.invitedPeer = nil
        }
    }

    // MARK: Sending

    func send(command: RemoteCommand) { send(.command(command)) }

    func send(state: PresenterState) {
        let s = state.sanitized()
        // If the note still does not fit (heavy JSON escaping), send the state
        // without it rather than leaving the remote on a stale slide and timer.
        guard let data = RemotePacket.state(s).encoded() ?? {
            var bare = s; bare.note = ""
            return RemotePacket.state(bare).encoded()
        }() else { return }
        send(data: data)
    }

    private func send(_ packet: RemotePacket) {
        guard let data = packet.encoded() else { return }
        send(data: data)
    }

    private func send(data: Data) {
        guard !session.connectedPeers.isEmpty else { return }
        try? session.send(data, toPeers: session.connectedPeers, with: .reliable)
    }
}

extension RemoteLink: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            switch state {
            case .connecting:
                self.pairingFailed = false
            case .connected:
                self.connected = true
                self.peerName = peerID.displayName
                self.pairingFailed = false
                self.invitedPeer = nil
                if self.role == .presenter { self.stopAdvertising() }
            case .notConnected:
                if self.session.connectedPeers.isEmpty {
                    self.connected = false; self.peerName = nil; self.presenterState = nil
                    // Remote: the peer we invited dropping back to notConnected
                    // (without ever connecting) means the code was rejected.
                    if self.role == .remote, let invited = self.invitedPeer, invited == peerID {
                        self.pairingFailed = true
                        self.invitedPeer = nil
                    }
                    // Presenter: open for a new pairing (with the already-rotated
                    // code) unless stopped or locked out — startAdvertising checks.
                    if self.role == .presenter { self.startAdvertising() }
                }
            @unknown default: break
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let packet = RemotePacket.decode(data) else { return }
        Task { @MainActor in
            // Each side only accepts the packet kind the other side may send.
            switch (packet, self.role) {
            case (.command(let c), .presenter): self.onCommand?(c)
            case (.state(let s), .remote): self.presenterState = s
            default: break
            }
        }
    }

    nonisolated func session(_ s: MCSession, didReceive stream: InputStream, withName: String, fromPeer: MCPeerID) {}
    nonisolated func session(_ s: MCSession, didStartReceivingResourceWithName: String, fromPeer: MCPeerID, with: Progress) {}
    nonisolated func session(_ s: MCSession, didFinishReceivingResourceWithName: String, fromPeer: MCPeerID, at: URL?, withError: Error?) {}
}

extension RemoteLink: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                                didReceiveInvitationFromPeer peerID: MCPeerID,
                                withContext context: Data?,
                                invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        Task { @MainActor in
            // The handler is called exactly once, on every path.
            let ok = self.shouldAccept(context: context)
            invitationHandler(ok, ok ? self.session : nil)
        }
    }
}

extension RemoteLink: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID,
                             withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor in
            // List it for the user to pick — no automatic invitation.
            let entry = FoundPresenter(peerID: peerID, name: peerID.displayName,
                                       title: info?["title"].map { String($0.prefix(60)) })
            if let i = self.presenters.firstIndex(where: { $0.peerID == peerID }) {
                self.presenters[i] = entry
            } else {
                self.presenters.append(entry)
            }
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in
            self.presenters.removeAll { $0.peerID == peerID }
        }
    }
}

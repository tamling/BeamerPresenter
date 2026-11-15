import Foundation
import UIKit
import CryptoKit
import MultipeerConnectivity

/// Peer-to-peer link between an iPhone remote and the presenting iPad, built on
/// MultipeerConnectivity (Wi-Fi / Bluetooth, no server, auto-discovery). One
/// instance acts either as the **presenter** (advertises, shows a pairing code,
/// admits one remote that proves it knows the code, applies its commands, pushes
/// state) or the **remote** (browses for a presenter, asks for the code, sends
/// commands, shows the pushed state). The session data channel is encrypted;
/// discovery is not, so nothing private goes into `discoveryInfo`.
///
/// Pairing (protocol 7, mutual): the presenter shows a random 4-digit code and
/// advertises a random nonce. The remote sends HMAC-SHA256 over that nonce and
/// one of its own, keyed by the code, as the invitation `context` — the code
/// itself never travels — and the presenter proves the same secret back over the
/// session before the remote trusts it, so a rogue advertiser cannot pose as the
/// talk. Only one remote is admitted at a time, further invitations are
/// declined, and the code is re-rolled when that remote drops and after a few
/// bad attempts, so a code that leaked or is being guessed at does not stay
/// valid. Everything a peer sends is ignored until it is the verified peer.
@MainActor
final class RemoteLink: NSObject, ObservableObject {
    enum Role { case presenter, remote }

    /// Remote side: why the last pairing attempt failed.
    enum PairingFailure { case wrongCode, unreachable }

    @Published private(set) var connected = false
    @Published private(set) var peerName: String?
    @Published private(set) var presenterState: PresenterState?   // remote side

    /// Presenter side: the 4-digit code to show on screen; the remote must enter it.
    @Published private(set) var pairingCode = ""
    /// Presenter side: invitations declined for a bad code since the last pairing.
    @Published private(set) var rejectedAttempts = 0
    /// Remote side: a presenter has been discovered nearby (prompt for the code).
    @Published private(set) var foundPresenter = false
    /// Remote side: why the last pairing attempt failed, `nil` while none has.
    @Published private(set) var pairingFailure: PairingFailure?

    /// Remote side: the last pairing attempt failed — let the user retry.
    var pairingFailed: Bool { pairingFailure != nil }

    /// Presenter side: called when a command arrives from the remote.
    var onCommand: ((RemoteCommand) -> Void)?

    private static let protocolVersion = 7
    private static let codeDigits = 4
    private static let nonceBytes = 16
    private static let nonceKey = "n"
    /// Declined codes before the presenter re-rolls (a 4-digit space is small).
    private static let rejectsBeforeReroll = 5
    /// An accepted invitation that never connects must not block pairing.
    private static let pendingTimeout: TimeInterval = 20

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

    // The one peer whose packets count, on either side, plus (presenter side) the
    // invitation that has been accepted but has not connected yet.
    private var verifiedPeer: MCPeerID?
    private var pendingPeer: MCPeerID?
    private var pendingNonce = Data()
    private var pendingSince = Date.distantPast

    // Presenter side: the nonce published alongside the code.
    private var pairingNonce = Data()

    // Remote side: presenters seen while browsing (with their nonce), the code
    // the user typed, and the nonce sent to each invited presenter.
    private var foundPeers: [MCPeerID: Data] = [:]
    private var remoteCode = ""
    private var invitedNonces: [MCPeerID: Data] = [:]
    private var reachedConnecting = false
    private var attempt = 0
    private var pairingTimeout: Task<Void, Never>?

    init(role: Role) { self.role = role; super.init() }

    /// `title` is deliberately not advertised: `discoveryInfo` is readable by any
    /// unpaired browser, so the deck name only travels inside `PresenterState`.
    func start(title: String = "") {
        switch role {
        case .presenter:
            startAdvertising()
        case .remote:
            let b = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
            b.delegate = self
            b.startBrowsingForPeers()
            browser = b
        }
    }

    func stop() {
        pairingTimeout?.cancel(); pairingTimeout = nil
        advertiser?.stopAdvertisingPeer(); advertiser = nil
        browser?.stopBrowsingForPeers(); browser = nil
        session.disconnect()
        connected = false; peerName = nil; presenterState = nil
        pairingCode = ""; pairingNonce = Data(); rejectedAttempts = 0
        foundPresenter = false; pairingFailure = nil
        verifiedPeer = nil; pendingPeer = nil; pendingNonce = Data()
        foundPeers.removeAll(); invitedNonces.removeAll()
        remoteCode = ""; reachedConnecting = false
    }

    /// Presenter side: advertise a fresh code and nonce. Called on start and on
    /// every re-roll, so neither a leaked code nor a partly-enumerated one lives
    /// longer than the pairing it was shown for.
    private func startAdvertising() {
        guard role == .presenter else { return }
        advertiser?.stopAdvertisingPeer()
        pairingCode = Self.makeCode()
        pairingNonce = Self.makeNonce()
        let info = [Self.nonceKey: pairingNonce.base64EncodedString()]
        let a = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: info, serviceType: serviceType)
        a.delegate = self
        a.startAdvertisingPeer()
        advertiser = a
    }

    /// Remote side: try to pair with the discovered presenter(s) using `code`.
    func connect(code: String) {
        let trimmed = code.trimmingCharacters(in: .whitespaces)
        guard role == .remote, trimmed.count == Self.codeDigits else { return }
        remoteCode = trimmed
        pairingFailure = nil
        attempt += 1
        invitedNonces.removeAll()
        reachedConnecting = false
        inviteFoundPeers()
    }

    private func inviteFoundPeers() {
        guard role == .remote, !connected, !remoteCode.isEmpty, !foundPeers.isEmpty else { return }
        for (peer, presenterNonce) in foundPeers where invitedNonces[peer] == nil {
            let nonce = Self.makeNonce()
            let request = PairingRequest(bpPairing: Self.protocolVersion, nonce: nonce,
                                         proof: Self.proof("remote", code: remoteCode,
                                                           presenterNonce: presenterNonce,
                                                           remoteNonce: nonce))
            guard let data = try? JSONEncoder().encode(request) else { continue }
            invitedNonces[peer] = nonce
            browser?.invitePeer(peer, to: session, withContext: data, timeout: 12)
        }
        startPairingTimeout()
    }

    /// Remote side: a declined invitation gives no callback, so report a failed
    /// attempt by timeout — one task per attempt, cancelled once it pairs, so a
    /// stale attempt can never flag a newer one.
    private func startPairingTimeout() {
        pairingTimeout?.cancel()
        let generation = attempt
        pairingTimeout = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 13_000_000_000)
            guard let self, !Task.isCancelled,
                  self.attempt == generation, !self.connected else { return }
            // Reaching .connecting means the presenter accepted the proof, so the
            // code was right and the link, not the code, is what failed.
            self.pairingFailure = self.reachedConnecting ? .unreachable : .wrongCode
        }
    }

    /// Presenter side: the invited remote connected — prove the code back to it,
    /// then treat it as the one authorised peer.
    private func admit(_ peerID: MCPeerID) {
        guard role == .presenter, peerID == pendingPeer else { return }
        sendPairingProof(to: peerID, remoteNonce: pendingNonce)
        pendingPeer = nil
        verifiedPeer = peerID
        peerName = peerID.displayName
        rejectedAttempts = 0
        connected = true
    }

    /// Remote side: accept the link only once the presenter has proved the code
    /// too — a rogue advertiser accepts every invitation but cannot do this.
    private func verifyPresenterProof(_ frame: PairingFrame, from peerID: MCPeerID) {
        guard role == .remote, verifiedPeer == nil,
              frame.bpPairing == Self.protocolVersion,
              let presenterNonce = foundPeers[peerID],
              let remoteNonce = invitedNonces[peerID],
              Self.isValidProof(frame.proof, "presenter", code: remoteCode,
                                presenterNonce: presenterNonce, remoteNonce: remoteNonce) else { return }
        pairingTimeout?.cancel(); pairingTimeout = nil
        verifiedPeer = peerID
        peerName = peerID.displayName
        pairingFailure = nil
        connected = true
    }

    private func sendPairingProof(to peer: MCPeerID, remoteNonce: Data) {
        let frame = PairingFrame(bpPairing: Self.protocolVersion,
                                 proof: Self.proof("presenter", code: pairingCode,
                                                   presenterNonce: pairingNonce,
                                                   remoteNonce: remoteNonce))
        guard let data = try? JSONEncoder().encode(frame) else { return }
        try? session.send(data, toPeers: [peer], with: .reliable)
    }

    /// Presenter side: a bad code. Count it, and re-roll code and nonce every few
    /// attempts so the 4-digit space cannot be enumerated.
    private func noteRejectedInvitation() {
        rejectedAttempts += 1
        if rejectedAttempts % Self.rejectsBeforeReroll == 0 { startAdvertising() }
    }

    private static func makeCode() -> String { String(format: "%04d", Int.random(in: 0...9999)) }

    private static func makeNonce() -> Data {
        SymmetricKey(size: .bits128).withUnsafeBytes { Data($0) }
    }

    private static func proofMessage(_ label: String, _ presenterNonce: Data, _ remoteNonce: Data) -> Data {
        var m = Data(label.utf8)
        m.append(presenterNonce)
        m.append(remoteNonce)
        return m
    }

    private static func proof(_ label: String, code: String,
                              presenterNonce: Data, remoteNonce: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(
            for: proofMessage(label, presenterNonce, remoteNonce),
            using: SymmetricKey(data: Data(code.utf8))))
    }

    private static func isValidProof(_ proof: Data, _ label: String, code: String,
                                     presenterNonce: Data, remoteNonce: Data) -> Bool {
        guard !code.isEmpty else { return false }
        return HMAC<SHA256>.isValidAuthenticationCode(
            proof,
            authenticating: proofMessage(label, presenterNonce, remoteNonce),
            using: SymmetricKey(data: Data(code.utf8)))
    }

    /// A peer's state is untrusted input: clamp it into ranges the UI can render.
    /// Unbounded `Int`s trap in `index + 1` and in the timer formatters, and an
    /// unbounded note wedges the main thread in the SwiftUI text.
    private static func sanitized(_ s: PresenterState) -> PresenterState {
        var out = s
        out.title = String(s.title.prefix(200))
        out.note = String(s.note.prefix(20_000))
        out.pageCount = min(max(s.pageCount, 0), 100_000)
        out.index = min(max(s.index, 0), max(out.pageCount - 1, 0))
        out.elapsed = min(max(s.elapsed, 0), 24 * 3600)
        return out
    }

    func send(command: RemoteCommand) { send(.command(command)) }
    func send(state: PresenterState) { send(.state(state)) }

    private func send(_ packet: RemotePacket) {
        guard let peer = verifiedPeer,
              let data = try? JSONEncoder().encode(packet) else { return }
        try? session.send(data, toPeers: [peer], with: .reliable)
    }

    /// The remote's proof of the code, carried in the invitation `context`.
    private struct PairingRequest: Codable {
        var bpPairing: Int
        var nonce: Data
        var proof: Data
    }

    /// The presenter's proof of the code, sent over the session once connected.
    /// Separate from `RemotePacket`, so an unverified peer can send nothing else.
    private struct PairingFrame: Codable {
        var bpPairing: Int
        var proof: Data
    }
}

extension RemoteLink: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            switch state {
            case .connecting:
                if self.role == .remote { self.reachedConnecting = true }
            case .connected:
                // Presenter: admit the remote it accepted. Remote: stay untrusted
                // until the presenter's proof arrives and verifies.
                self.admit(peerID)
            case .notConnected:
                if peerID == self.verifiedPeer {
                    // A paired peer dropping is not a pairing failure.
                    self.verifiedPeer = nil
                    self.invitedNonces[peerID] = nil
                    self.connected = false; self.peerName = nil; self.presenterState = nil
                    // Presenter: show a fresh code, so the old one cannot be reused.
                    if self.role == .presenter { self.startAdvertising() }
                } else {
                    if peerID == self.pendingPeer { self.pendingPeer = nil }
                    // Remote: an invitation that came back without pairing failed;
                    // the framework gives no reason, so fall back to the heuristic.
                    if self.role == .remote, self.verifiedPeer == nil,
                       self.invitedNonces[peerID] != nil {
                        self.pairingFailure = self.reachedConnecting ? .unreachable : .wrongCode
                    }
                }
            @unknown default: break
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        if let frame = try? JSONDecoder().decode(PairingFrame.self, from: data) {
            Task { @MainActor in self.verifyPresenterProof(frame, from: peerID) }
            return
        }
        guard let packet = try? JSONDecoder().decode(RemotePacket.self, from: data) else { return }
        Task { @MainActor in
            guard peerID == self.verifiedPeer else { return }
            switch packet {
            case .command(let c): if self.role == .presenter { self.onCommand?(c) }
            case .state(let s):   if self.role == .remote { self.presenterState = Self.sanitized(s) }
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
            // Drop an accepted invitation that never connected, then take one
            // remote at a time: decline while a remote is pending or paired.
            if let pending = self.pendingPeer,
               Date().timeIntervalSince(self.pendingSince) > Self.pendingTimeout,
               !self.session.connectedPeers.contains(pending) {
                self.pendingPeer = nil
            }
            guard self.verifiedPeer == nil, self.pendingPeer == nil else {
                invitationHandler(false, nil); return
            }
            // Not a BeamerPresenter 7 remote at all — not a guess at the code.
            guard let data = context,
                  let request = try? JSONDecoder().decode(PairingRequest.self, from: data),
                  request.bpPairing == Self.protocolVersion,
                  request.nonce.count == Self.nonceBytes else {
                invitationHandler(false, nil); return
            }
            // Accept only a proof of the code we are showing, never the code itself.
            guard Self.isValidProof(request.proof, "remote", code: self.pairingCode,
                                    presenterNonce: self.pairingNonce,
                                    remoteNonce: request.nonce) else {
                invitationHandler(false, nil)
                self.noteRejectedInvitation()
                return
            }
            self.pendingPeer = peerID
            self.pendingNonce = request.nonce
            self.pendingSince = Date()
            invitationHandler(true, self.session)
        }
    }
}

extension RemoteLink: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID,
                             withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor in
            // Only a BeamerPresenter 7 presenter advertises a pairing nonce.
            guard let encoded = info?[Self.nonceKey],
                  let nonce = Data(base64Encoded: encoded),
                  nonce.count == Self.nonceBytes else { return }
            self.foundPeers[peerID] = nonce
            self.foundPresenter = true
            // If the user already entered a code, invite this freshly-found peer too.
            if !self.remoteCode.isEmpty { self.inviteFoundPeers() }
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in
            self.foundPeers[peerID] = nil
            self.invitedNonces[peerID] = nil
            self.foundPresenter = !self.foundPeers.isEmpty
        }
    }
}

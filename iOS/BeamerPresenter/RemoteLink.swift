import Foundation
import UIKit
import MultipeerConnectivity

/// Peer-to-peer link between an iPhone remote and the presenting iPad, built on
/// MultipeerConnectivity (Wi-Fi / Bluetooth, no server, auto-discovery,
/// encrypted). One instance acts either as the **presenter** (advertises, shows
/// a pairing code, accepts only a remote that sends the matching code, applies
/// its commands, pushes state) or the **remote** (browses for a presenter, asks
/// for the code, sends commands, shows the pushed state).
///
/// Pairing: the presenter generates a random 4-digit code and shows it on its
/// screen. The remote must send that exact code in the invitation `context`;
/// the advertiser rejects any invitation whose code does not match. This stops
/// an unknown device on the same Wi-Fi/Bluetooth from silently taking over the
/// talk — auto-accept is gone.
@MainActor
final class RemoteLink: NSObject, ObservableObject {
    enum Role { case presenter, remote }

    @Published private(set) var connected = false
    @Published private(set) var peerName: String?
    @Published private(set) var presenterState: PresenterState?   // remote side

    /// Presenter side: the 4-digit code to show on screen; the remote must enter it.
    @Published private(set) var pairingCode = ""
    /// Remote side: a presenter has been discovered nearby (prompt for the code).
    @Published private(set) var foundPresenter = false
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

    // Remote side: presenters seen while browsing, and the code the user typed.
    private var foundPeers: [MCPeerID] = []
    private var remoteCode = ""
    private var didAttemptInvite = false

    init(role: Role) { self.role = role; super.init() }

    func start(title: String = "") {
        switch role {
        case .presenter:
            pairingCode = Self.makeCode()
            let info = title.isEmpty ? nil : ["title": String(title.prefix(60))]
            let a = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: info, serviceType: serviceType)
            a.delegate = self
            a.startAdvertisingPeer()
            advertiser = a
        case .remote:
            let b = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
            b.delegate = self
            b.startBrowsingForPeers()
            browser = b
        }
    }

    func stop() {
        advertiser?.stopAdvertisingPeer(); advertiser = nil
        browser?.stopBrowsingForPeers(); browser = nil
        session.disconnect()
        connected = false; peerName = nil; presenterState = nil
        pairingCode = ""; foundPresenter = false; pairingFailed = false
        foundPeers.removeAll(); remoteCode = ""; didAttemptInvite = false
    }

    /// Remote side: try to pair with the discovered presenter(s) using `code`.
    func connect(code: String) {
        let trimmed = code.trimmingCharacters(in: .whitespaces)
        guard role == .remote, trimmed.count == 4 else { return }
        remoteCode = trimmed
        pairingFailed = false
        inviteFoundPeers()
    }

    private func inviteFoundPeers() {
        guard role == .remote, !foundPeers.isEmpty, let data = remoteCode.data(using: .utf8) else { return }
        for peer in foundPeers {
            didAttemptInvite = true
            browser?.invitePeer(peer, to: session, withContext: data, timeout: 12)
        }
        // A declined invitation gives no browser callback, so flag a wrong code by timeout.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 13_000_000_000)
            if !self.connected, self.didAttemptInvite {
                self.pairingFailed = true
                self.didAttemptInvite = false
            }
        }
    }

    private static func makeCode() -> String { String(format: "%04d", Int.random(in: 0...9999)) }

    func send(command: RemoteCommand) { send(.command(command)) }
    func send(state: PresenterState) { send(.state(state)) }

    private func send(_ packet: RemotePacket) {
        guard !session.connectedPeers.isEmpty,
              let data = try? JSONEncoder().encode(packet) else { return }
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
                self.didAttemptInvite = false
            case .notConnected:
                if self.session.connectedPeers.isEmpty {
                    self.connected = false; self.peerName = nil; self.presenterState = nil
                    // Remote: a peer dropping back to notConnected after we invited it
                    // (without ever connecting) means the code was rejected.
                    if self.role == .remote, self.didAttemptInvite {
                        self.pairingFailed = true
                        self.didAttemptInvite = false
                    }
                }
            @unknown default: break
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let packet = try? JSONDecoder().decode(RemotePacket.self, from: data) else { return }
        Task { @MainActor in
            switch packet {
            case .command(let c): self.onCommand?(c)
            case .state(let s): self.presenterState = s
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
            // Accept only if the remote sent the exact 4-digit code we are showing.
            let sent = context.flatMap { String(data: $0, encoding: .utf8) }
            let ok = !self.pairingCode.isEmpty && sent == self.pairingCode
            invitationHandler(ok, ok ? self.session : nil)
        }
    }
}

extension RemoteLink: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID,
                             withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor in
            if !self.foundPeers.contains(peerID) { self.foundPeers.append(peerID) }
            self.foundPresenter = true
            // If the user already entered a code, invite this freshly-found peer too.
            if !self.remoteCode.isEmpty { self.inviteFoundPeers() }
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in
            self.foundPeers.removeAll { $0 == peerID }
            self.foundPresenter = !self.foundPeers.isEmpty
        }
    }
}

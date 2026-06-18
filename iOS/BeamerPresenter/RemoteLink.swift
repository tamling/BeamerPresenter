import Foundation
import UIKit
import MultipeerConnectivity

/// Peer-to-peer link between an iPhone remote and the presenting iPad, built on
/// MultipeerConnectivity (Wi-Fi / Bluetooth, no server, auto-discovery,
/// encrypted). One instance acts either as the **presenter** (advertises and
/// accepts a remote, applies its commands, pushes state) or the **remote**
/// (browses for a presenter, sends commands, shows the pushed state).
@MainActor
final class RemoteLink: NSObject, ObservableObject {
    enum Role { case presenter, remote }

    @Published private(set) var connected = false
    @Published private(set) var peerName: String?
    @Published private(set) var presenterState: PresenterState?   // remote side

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

    init(role: Role) { self.role = role; super.init() }

    func start(title: String = "") {
        switch role {
        case .presenter:
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
    }

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
            case .connected:
                self.connected = true
                self.peerName = peerID.displayName
            case .notConnected:
                if self.session.connectedPeers.isEmpty {
                    self.connected = false; self.peerName = nil; self.presenterState = nil
                }
            default: break
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
        Task { @MainActor in invitationHandler(true, self.session) }   // auto-accept
    }
}

extension RemoteLink: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID,
                             withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor in
            browser.invitePeer(peerID, to: self.session, withContext: nil, timeout: 12)
        }
    }
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}
}

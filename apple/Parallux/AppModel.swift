import Foundation
import Observation
import ParalluxKit

/// The objects every window shares, and the one place that decides how to
/// connect (panel switch, right-click menu and overview all call here).
@MainActor @Observable
final class AppModel {
    let tunnel = TunnelController()
    let profiles = ProfileService()
    let settings = SettingsModel()
    let defaultLink = DefaultLinkMonitor()
    private(set) var lastError: String?

    var session: CoreSession { tunnel.session }

    var isOn: Bool { tunnel.isConnected || tunnel.vpnStatus == .connecting || tunnel.vpnStatus == .reasserting }

    func start() {
        profiles.startAutoUpdate()
        Task { await tunnel.load() }
    }

    func setOn(_ on: Bool) async {
        if on { await connect() } else { await tunnel.disconnect() }
    }

    /// Uses the selected profile; before any profile exists, the bundled sample.
    func connect() async {
        lastError = nil
        if tunnel.phase != .ready { await tunnel.install() }
        guard tunnel.phase == .ready else { return }
        var content = SampleProfile.content
        if let profile = profiles.store.selected {
            do { content = try await profiles.content(of: profile) } catch {
                lastError = error.localizedDescription
                return
            }
        }
        let settings = settings.value
        await tunnel.connect(settings.startOptions(content: content),
                             onDemand: (settings.onDemandEnabled, settings.onDemandRules))
    }

    /// Switching profile while connected restarts the tunnel with it.
    func select(profile id: UUID) async {
        try? profiles.store.select(id)
        if tunnel.isConnected {
            await tunnel.disconnect()
            await connectWhenStopped()
        }
    }

    private func connectWhenStopped() async {
        // Why 5 s: stopping a tunnel takes well under a second; the bound
        // only keeps a stuck stop from looping forever.
        for _ in 0..<50 where tunnel.vpnStatus != .disconnected && tunnel.vpnStatus != .invalid {
            try? await Task.sleep(for: .milliseconds(100))
        }
        await connect()
    }

    var statusLine: String {
        let setup: StatusLine.Setup = switch tunnel.phase {
        case .awaitingApproval: .awaitingApproval
        case let .failed(message): .failed(message)
        default: .ready
        }
        let state: StatusLine.Tunnel = switch tunnel.vpnStatus {
        case .connected: .connected
        case .connecting, .reasserting: .connecting
        case .disconnecting: .disconnecting
        default: .disconnected
        }
        return StatusLine.text(setup: setup, tunnel: state, actionError: lastError,
                               coreError: session.lastError, linkKind: defaultLink.link?.kind)
    }

    var menuBarState: MenuBarIcon.State {
        guard tunnel.isConnected else { return .disconnected }
        if case .failed = tunnel.phase { return .degraded }
        if session.lastError != nil { return .degraded }
        // Until M3 there is one link and no aggregation; show plain lines.
        return .balance
    }
}

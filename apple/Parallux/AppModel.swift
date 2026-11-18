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
    let links = LinkMonitor()
    let linkSettings = LinkSettingsModel()
    let linkStats = LinkStatsPoller()
    @ObservationIgnored private let notifier = LinkNotifier()
    let servers = AggregationServersModel()
    let remote = RemoteControlModel()

    /// The multipath outbound for 叠加: the chosen server over the two top links.
    func bondProvider(_ settings: LinkSettings) -> ProfileComposer.Bond? {
        guard let id = settings.bondServerID, let server = servers.servers.first(where: { $0.id == id }),
              let psk = servers.psk(for: id) else { return nil }
        return server.bond(links: enabledLinks, psk: psk)
    }

    /// "东京 VPS · 12 ms" for the panel and menu.
    var bondServerSummary: String? { servers.summary(linkSettings.value.bondServerID) }
    private(set) var lastError: String?
    /// The profile content the running tunnel was started with, before composing.
    @ObservationIgnored private var runningContent: String?

    var session: CoreSession { tunnel.session }

    var isOn: Bool { tunnel.isConnected || tunnel.vpnStatus == .connecting || tunnel.vpnStatus == .reasserting }

    /// Local-only controls (tunnel switch, links, mode, system proxy) are off while viewing a remote device.
    var controlsLocalCore: Bool { !remote.isRemote }

    func start() {
        profiles.startAutoUpdate()
        Task { await tunnel.load() }
        observeTunnel()
        observeLinkHealth()
    }

    private func observeLinkHealth() {
        withObservationTracking {
            _ = linkStats.groups
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.notifier.update(groups: self.linkStats.groups, links: self.links.links, enabled: self.settings.value.notifyLinkChanges)
                self.observeLinkHealth()
            }
        }
    }

    /// Starts and stops the per-link poller with the tunnel.
    private func observeTunnel() {
        withObservationTracking {
            _ = tunnel.vpnStatus
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.tunnel.isConnected { self.linkStats.start() } else { self.linkStats.stop() }
                self.observeTunnel()
            }
        }
    }

    /// Enabled links in priority order.
    var enabledLinks: [LinkInterface] { linkSettings.value.preferences.enabled(links.links) }

    /// The aggregation mode actually in effect: needs two links, and 叠加 needs a server.
    var effectiveMode: AggregationMode? {
        guard enabledLinks.count >= 2 else { return nil }
        let mode = linkSettings.value.mode
        if mode == .bond, bondProvider(linkSettings.value) == nil { return .failover }
        return mode
    }

    func compose(_ content: String) throws -> String {
        let settings = linkSettings.value
        return try ProfileComposer.compose(content, links: enabledLinks, backup: settings.preferences.backup,
                                           mode: settings.mode, bond: bondProvider(settings))
    }

    /// Applies link or mode changes to a running tunnel without disconnecting.
    func applyLinkChanges() async {
        guard tunnel.isConnected, let runningContent else { return }
        do {
            try await tunnel.reload(settings.value.startOptions(content: try compose(runningContent)))
            lastError = nil
        } catch {
            lastError = "线路设置未生效：\(error.localizedDescription)"
        }
    }

    func setMode(_ mode: AggregationMode) async {
        linkSettings.value.mode = mode
        await applyLinkChanges()
    }

    func setOn(_ on: Bool) async {
        if on { await connect() } else { await tunnel.disconnect() }
    }

    /// Uses the selected profile; before any profile exists, the bundled sample.
    /// `overrideContent` (diagnostics' probe profile) replaces both and
    /// restarts a running tunnel.
    func connect(overrideContent: String? = nil) async {
        lastError = nil
        if overrideContent != nil, tunnel.vpnStatus != .disconnected, tunnel.vpnStatus != .invalid {
            await tunnel.disconnect()
            await waitUntilStopped()
        }
        if tunnel.phase != .ready { await tunnel.install() }
        guard tunnel.phase == .ready else { return }
        var content = SampleProfile.content
        if let overrideContent {
            content = overrideContent
        } else if let profile = profiles.store.selected {
            do { content = try await profiles.content(of: profile) } catch {
                lastError = error.localizedDescription
                return
            }
        }
        let composed: String
        do { composed = try compose(content) } catch {
            lastError = "配置不是有效的 JSON，无法加入线路"
            return
        }
        runningContent = content
        let settings = settings.value
        await tunnel.connect(settings.startOptions(content: composed),
                             onDemand: (settings.onDemandEnabled, settings.onDemandRules))
    }

    /// Switching profile while connected restarts the tunnel with it.
    func select(profile id: UUID) async {
        try? profiles.store.select(id)
        if tunnel.isConnected {
            await tunnel.disconnect()
            await waitUntilStopped()
            await connect()
        }
    }

    private func waitUntilStopped() async {
        // Why 5 s: stopping a tunnel takes well under a second; the bound
        // only keeps a stuck stop from looping forever.
        for _ in 0..<50 where tunnel.vpnStatus != .disconnected && tunnel.vpnStatus != .invalid {
            try? await Task.sleep(for: .milliseconds(100))
        }
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
        let linkText: String? = enabledLinks.count >= 2
            ? "\(effectiveMode?.title ?? "") · \(enabledLinks.count) 条线路"
            : defaultLink.link?.kind
        return StatusLine.text(setup: setup, tunnel: state, actionError: lastError,
                               coreError: session.lastError, linkKind: linkText)
    }

    var menuBarState: MenuBarIcon.State {
        guard tunnel.isConnected else { return .disconnected }
        if case .failed = tunnel.phase { return .degraded }
        if session.lastError != nil { return .degraded }
        // A link the aggregate considers down is the design's 「线路异常」.
        if linkStats.groups.contains(where: { $0.links.contains { !$0.healthy } }) { return .degraded }
        switch effectiveMode {
        case .bond: return .bond
        case .failover: return .failover
        default: return .balance
        }
    }
}

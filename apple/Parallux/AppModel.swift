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
    let routeOverrides = RouteOverrideStore()
    /// A target the connections inspector asked 路由 › 试一下 to explain; consumed by RoutingView.
    var pendingExplainTarget: String?
    /// A sidebar page the panel asked the main window to show; consumed by MainWindow.
    var pendingSidebar: SidebarItem?

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
    /// The running content is diagnostics' probe profile (never made direct).
    @ObservationIgnored private var runningProbe = false

    var session: CoreSession { tunnel.session }

    var isOn: Bool { tunnel.isConnected || tunnel.vpnStatus == .connecting || tunnel.vpnStatus == .reasserting }

    /// Local-only controls (tunnel switch, links, mode, system proxy) are off while viewing a remote device.
    var controlsLocalCore: Bool { !remote.isRemote }

    func start() {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "ParalluxPreview") { session.loadPreview() }
        #endif
        profiles.startAutoUpdate()
        Task {
            await tunnel.load()
            await upgradeStaleExtension()
        }
        observeTunnel()
        observeLinkHealth()
        observeLinkSet(previous: links.links)
    }

    /// 「自动加入新线路」: a link plugged in or pulled out while connected
    /// recomposes the profile (fix-new-links-recompose).
    private func observeLinkSet(previous: [LinkInterface]) {
        withObservationTracking {
            _ = links.links
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                let current = self.links.links
                if self.linkSettings.value.preferences.needsRecomposition(from: previous, to: current) {
                    await self.applyLinkChanges()
                }
                self.observeLinkSet(previous: current)
            }
        }
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

    /// Enabled links in priority order (the links page's choice).
    var enabledLinks: [LinkInterface] { linkSettings.value.preferences.enabled(links.links) }

    /// 聚合 / 代理 as the switches show them (feat-split-switches).
    var switches: ConnectionSwitches { ConnectionSwitches.shown(linkSettings.value.switches, running: isOn) }

    /// The links traffic actually uses: the enabled ones with 聚合 on; with it
    /// off, the one macOS routes through by default.
    var activeLinks: [LinkInterface] {
        if linkSettings.value.switches.aggregation { return enabledLinks }
        let name = defaultLink.link?.name
        return links.links.first { $0.name == name }.map { [$0] } ?? Array(enabledLinks.prefix(1))
    }

    /// The note under the aggregation picker, when the chosen mode is not the one running.
    var aggregationNotice: String? {
        AggregationNotice.text(chosen: linkSettings.value.mode, effective: effectiveMode, proxy: linkSettings.value.switches.proxy)
    }

    /// The aggregation mode actually in effect: needs 聚合 on and two links, and 叠加 needs a server.
    var effectiveMode: AggregationMode? {
        guard linkSettings.value.switches.aggregation, enabledLinks.count >= 2 else { return nil }
        let mode = linkSettings.value.mode
        // 叠加 carries only node traffic; with 代理 off there is none (feat-link-view).
        if mode == .bond, bondProvider(linkSettings.value) == nil || !linkSettings.value.switches.proxy { return .failover }
        return mode
    }

    /// 代理 off swaps the profile for its direct form; route overrides next
    /// (they name the profile's own outbounds), then 聚合 adds the links.
    /// `probe`: diagnostics' own profile, run as given whatever the switches say.
    func compose(_ content: String, probe: Bool = false) throws -> String {
        let settings = linkSettings.value
        let proxy = settings.switches.proxy || probe
        let base = proxy ? content : DirectProfile.make(from: content)
        let rerouted = proxy
            ? RouteOverrides.apply(routeOverrides.overrides(for: profiles.store.selectedID), to: base).config
            : base
        return try ProfileComposer.compose(rerouted, links: settings.switches.aggregation ? enabledLinks : [],
                                           backup: settings.preferences.backup,
                                           mode: settings.mode, bond: bondProvider(settings))
    }

    /// Applies link or mode changes to a running tunnel without disconnecting.
    func applyLinkChanges() async {
        guard tunnel.isConnected, let runningContent else { return }
        do {
            try await tunnel.reload(settings.value.startOptions(content: try compose(runningContent, probe: runningProbe)))
            lastError = nil
        } catch {
            lastError = "线路设置未生效：\(error.localizedDescription)"
        }
    }

    func setMode(_ mode: AggregationMode) async {
        linkSettings.value.mode = mode
        await applyLinkChanges()
    }

    /// After an app update the running extension is the old build, whose Mach
    /// service this app cannot reach; replace it, and bring a tunnel that was
    /// on back up (fix-stale-extension-on-launch).
    private func upgradeStaleExtension() async {
        let signed = AppGroup.identifier() != nil
        guard signed, tunnel.hasConfiguration else { return }
        let status: LaunchUpgrade.Status = switch tunnel.vpnStatus {
        case .connected: .connected
        case .connecting: .connecting
        case .reasserting: .reasserting
        case .disconnecting: .disconnecting
        default: .disconnected
        }
        let stale = await tunnel.needsActivation()
        switch LaunchUpgrade.action(signed: signed, status: status, stale: stale) {
        case .none:
            return
        case .replace:
            await tunnel.install()
        case .replaceAndReconnect:
            await tunnel.disconnect()
            await waitUntilStopped()
            await tunnel.install()
            if tunnel.phase == .ready { await connect() }
        }
    }

    /// The power button, the menu's 启动 / 停止 and URLs: start with the last
    /// combination of switches (decision 21).
    func setOn(_ on: Bool) async {
        if on {
            linkSettings.value.switches = ConnectionSwitches.forStart(linkSettings.value.switches)
            await connect()
        } else {
            await tunnel.disconnect()
        }
    }

    /// One of the two switches (panel, overview, menu).
    func setSwitch(_ which: ConnectionSwitches.Which, on: Bool) async {
        let (next, action) = ConnectionSwitches.toggle(linkSettings.value.switches, running: isOn, which, on: on)
        linkSettings.value.switches = next
        switch action {
        case .connect: await connect()
        case .reload: await applyLinkChanges()
        case .disconnect: await tunnel.disconnect()
        case .nothing: break
        }
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
        // Every connect checks the extension's version, not just the first:
        // a new build must replace the old extension (fix-tunnel-start-sandbox).
        var stale = false
        if tunnel.phase == .ready, AppGroup.identifier() != nil { stale = await tunnel.needsActivation() }
        if tunnel.phase != .ready || stale { await tunnel.install() }
        if tunnel.phase == .awaitingApproval {
            // Show where to approve, then carry on by itself once the user
            // switches Parallux on in System Settings (feat-setup-approval).
            SetupLinks.open(.systemExtension)
            guard await tunnel.completeApproval() else { return }
        }
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
        do { composed = try compose(content, probe: overrideContent != nil) } catch {
            lastError = "配置不是有效的 JSON，无法加入线路"
            return
        }
        runningContent = content
        runningProbe = overrideContent != nil
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
        let linkText: String? = effectiveMode != nil
            ? "\(effectiveMode?.title ?? "") · \(activeLinks.count) 条线路"
            : defaultLink.link?.kind
        return StatusLine.text(setup: setup, tunnel: state, actionError: lastError ?? tunnel.startError,
                               coreError: session.lastError, linkKind: linkText)
    }

    var menuBarState: MenuBarIcon.State {
        guard tunnel.isConnected else { return .disconnected }
        if case .failed = tunnel.phase { return .degraded }
        if session.lastError != nil { return .degraded }
        // A link the aggregate considers down is the design's 「线路异常」.
        if linkStats.states.values.contains(where: { !$0.healthy }) { return .degraded }
        switch effectiveMode {
        case .bond: return .bond
        case .failover: return .failover
        default: return .balance
        }
    }
}

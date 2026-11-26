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
    let relays = RelayLinksModel()
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

    /// The ids on the aggregation server list, as the mode rules take them.
    private var serverIDs: [UUID] { servers.servers.map(\.id) }
    var hasAggregationServer: Bool { !servers.servers.isEmpty }
    /// 叠加 was asked for while there was no aggregation server; adding one
    /// finishes the switch. Not saved: it is something asked for in this run.
    private(set) var bondAwaitsServer = false
    /// How many mode choices were refused. The mode controls take it as their
    /// identity: a segmented control goes on showing the segment that was
    /// clicked until its view is redrawn, and a refused choice changes nothing
    /// else that would redraw it. Assumed from how the controls update, not
    /// seen in the installed app.
    private(set) var refusedModeChoices = 0
    /// Brings the main window forward; set by AppDelegate, which owns it.
    @ObservationIgnored var showMainWindow: () -> Void = {}
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
        // Settings saved by a build that let 叠加 be chosen without a server.
        linkSettings.value.serversChanged(serverIDs)
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
        linkStats.relayCarriers = { [weak self] in self?.relayCarrierTags ?? [:] }
        Task { await refreshRelayCarriers() }
    }

    /// 「自动加入新线路」: a link plugged in or pulled out while connected
    /// recomposes the profile.
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
                // Afterwards, so the search (seconds, when an interface does
                // not answer) never delays taking a pulled link out: a relay
                // whose carrier was unplugged looks for another way to its host.
                if await self.relays.detectCarriers(physical: current) {
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
                self.notifier.update(groups: self.linkStats.groups, links: self.allLinks, enabled: self.settings.value.notifyLinkChanges)
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

    /// Every link the links page lists: this Mac's interfaces, then the
    /// relay links.
    var allLinks: [LinkInterface] { links.links + relays.links }

    /// Enabled links in priority order (the links page's choice). A relay
    /// link counts only while it can be used: it has its key, and its
    /// carrier is one of the enabled physical links.
    var enabledLinks: [LinkInterface] {
        let enabled = linkSettings.value.preferences.enabled(allLinks)
        let physical = enabled.filter { $0.kind != .relay }.map(\.name)
        return enabled.filter { link in
            guard link.kind == .relay, let relay = relays.relay(named: link.name) else { return link.kind != .relay }
            return relay.blocker(hasKey: relays.keyed.contains(relay.id), enabledPhysical: physical) == nil
        }
    }

    /// Why an enabled relay link is not carrying anything; nil for physical
    /// links, switched-off relays and relays in use.
    func relayBlocker(_ link: LinkInterface) -> RelayLink.Blocker? {
        guard link.kind == .relay, let relay = relays.relay(named: link.name) else { return nil }
        let physical = linkSettings.value.preferences.enabled(links.links).map(\.name)
        return relay.blocker(hasKey: relays.keyed.contains(relay.id), enabledPhysical: physical)
    }

    /// The second line of a link row: the interface for a physical link,
    /// the carrier (or what is missing) for a relay link.
    func linkDetail(_ link: LinkInterface) -> String {
        guard link.kind == .relay, let relay = relays.relay(named: link.name) else { return "\(link.displayName) · \(link.name)" }
        if relays.detecting.contains(relay.id) { return "\(link.kind.title) · 检测中..." }
        guard let carrier = relay.carrier else { return "\(link.kind.title) · 无承载线路" }
        let name = links.links.first { $0.name == carrier }.map { "\($0.kind.title)（\(carrier)）" } ?? carrier
        return "\(link.kind.title) · 经\(name)"
    }

    /// Relay link tag → carrier link tag, for the per-link rates (RelayRates).
    var relayCarrierTags: [String: String] {
        var result: [String: String] = [:]
        for link in enabledLinks where link.kind == .relay {
            if let carrier = relays.relay(named: link.name)?.carrier {
                result[ProfileComposer.linkTag(link.name)] = ProfileComposer.linkTag(carrier)
            }
        }
        return result
    }

    /// The enabled relay links as the composer takes them. Keys are read
    /// from the Keychain here and nowhere else.
    private var composedRelays: [ProfileComposer.Relay] {
        enabledLinks.filter { $0.kind == .relay }.compactMap { link in
            guard let relay = relays.relay(named: link.name), let key = relays.key(for: relay.id) else { return nil }
            return relay.composed(key: key)
        }
    }

    /// Looks for relay carriers (`force`: again for every relay) and applies
    /// the result to a running tunnel.
    func refreshRelayCarriers(force: Bool = false) async {
        if await relays.detectCarriers(physical: links.links, force: force) { await applyLinkChanges() }
    }

    /// Adds the relay links pasted into the links page, then finds their carriers.
    func addRelays(_ text: String) async throws {
        _ = try relays.add(text: text)
        _ = await relays.detectCarriers(physical: links.links)
        await applyLinkChanges()
    }

    func removeRelay(_ link: LinkInterface) async {
        guard let relay = relays.relay(named: link.name) else { return }
        relays.remove(relay.id)
        // Its place in the order and its switches go with it.
        linkSettings.value.preferences.order.removeAll { $0 == link.name }
        linkSettings.value.preferences.disabled.remove(link.name)
        linkSettings.value.preferences.backup.remove(link.name)
        await applyLinkChanges()
    }

    /// 聚合 / 代理 as the switches show them.
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
        AggregationNotice.text(chosen: linkSettings.value.mode, effective: effectiveMode,
                               physicalLinks: enabledLinks.filter { $0.kind != .relay }.count)
    }

    /// The aggregation mode actually in effect: needs 聚合 on and two links.
    var effectiveMode: AggregationMode? {
        guard linkSettings.value.switches.aggregation, enabledLinks.count >= 2 else { return nil }
        let mode = linkSettings.value.mode
        // 叠加 cannot be chosen without a server (setMode). What can still
        // leave it without a transport is found only while running: one
        // physical link left, or the server's key gone from the Keychain.
        if mode == .bond, bondProvider(linkSettings.value) == nil { return .failover }
        return mode
    }

    /// 代理 off swaps the profile for its direct form; route overrides next
    /// (they name the profile's own outbounds), then the route modes, then
    /// 聚合 adds the links.
    /// `probe`: diagnostics' own profile, run as given whatever the switches say.
    func compose(_ content: String, probe: Bool = false) throws -> String {
        let settings = linkSettings.value
        let proxy = settings.switches.proxy || probe
        let base = proxy ? content : DirectProfile.make(from: content)
        let rerouted = proxy
            ? RouteOverrides.apply(routeOverrides.overrides(for: profiles.store.selectedID), to: base).config
            : base
        // 规则 / 全局 / 直连 for a profile that defines no modes (RouteModes).
        // After the overrides, which go by rule index; before the links, so
        // direct mode uses the aggregate. Not with 代理 off (everything is
        // direct already) and not for the probe profile (run as given).
        let withModes = settings.switches.proxy && !probe ? RouteModes.add(to: rerouted) : rerouted
        return try ProfileComposer.compose(withModes, links: settings.switches.aggregation ? enabledLinks : [],
                                           backup: settings.preferences.backup,
                                           mode: settings.mode, bond: bondProvider(settings),
                                           relays: settings.switches.aggregation ? composedRelays : [])
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

    /// The one way the mode changes (the panel, the overview, settings, the
    /// menu and Shortcuts all come here). 叠加 with no aggregation server is
    /// refused and the main window shows where to add one.
    @discardableResult
    func setMode(_ mode: AggregationMode) async -> LinkSettings.ModeChange {
        let change = linkSettings.value.choose(mode, servers: serverIDs)
        bondAwaitsServer = change == .needsServer
        guard change == .applied else {
            refusedModeChoices += 1
            pendingSidebar = .aggregationServer
            showMainWindow()
            return change
        }
        await applyLinkChanges()
        return change
    }

    /// Adds the server a link describes. The first one becomes the server in
    /// use, and finishes a switch to 叠加 that was waiting for it.
    @discardableResult
    func addAggregationServer(link: String) async throws -> AggregationServer {
        let server = try servers.add(link: link)
        linkSettings.value.serversChanged(serverIDs, awaitingBond: bondAwaitsServer)
        bondAwaitsServer = false
        await applyLinkChanges()
        return server
    }

    /// Removes a server. Another one takes over if it was in use; with none
    /// left, 叠加 becomes 分流 (the page asks before that happens).
    func removeAggregationServer(_ id: UUID) async {
        servers.remove(id)
        linkSettings.value.serversChanged(serverIDs)
        await applyLinkChanges()
    }

    func useAggregationServer(_ id: UUID) async {
        linkSettings.value.useServer(id, servers: serverIDs)
        await applyLinkChanges()
    }

    /// After an app update the running extension is the old build, whose Mach
    /// service this app cannot reach; replace it, and bring a tunnel that was
    /// on back up.
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
        // a new build must replace the old extension.
        var stale = false
        if tunnel.phase == .ready, AppGroup.identifier() != nil { stale = await tunnel.needsActivation() }
        if tunnel.phase != .ready || stale { await tunnel.install() }
        if tunnel.phase == .awaitingApproval {
            // Show where to approve, then carry on by itself once the user
            // switches Parallux on in System Settings.
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

    private var displayedTunnel: StatusLine.Tunnel {
        switch tunnel.vpnStatus {
        case .connected: .connected
        case .connecting, .reasserting: .connecting
        case .disconnecting: .disconnecting
        default: .disconnected
        }
    }

    var statusLine: String {
        let setup: StatusLine.Setup = switch tunnel.phase {
        case .awaitingApproval: .awaitingApproval
        case let .failed(message): .failed(message)
        default: .ready
        }
        let linkText: String? = effectiveMode != nil
            ? "\(effectiveMode?.title ?? "") · \(activeLinks.count) 条线路"
            : defaultLink.link?.kind
        return StatusLine.text(setup: setup, tunnel: displayedTunnel, actionError: lastError ?? tunnel.startError ?? session.actionError,
                               coreError: session.lastError, linkKind: linkText)
    }

    var menuBarState: MenuBarIcon.State {
        let state = displayedTunnel
        let setupFailed = if case .failed = tunnel.phase { true } else { false }
        // The menu item belongs to this Mac even when the inspector follows a remote core.
        let localError = state == .connected ? controlsLocalCore && session.lastError != nil : tunnel.startError != nil
        let unhealthyLink = state == .connected && switches.aggregation && enabledLinks.contains {
            linkStats.link(ProfileComposer.linkTag($0.name))?.healthy == false
        }
        return .resolve(tunnel: state, switches: switches, effectiveMode: state == .connected ? effectiveMode : nil,
                        serviceError: setupFailed || lastError != nil || localError, linkError: unhealthyLink)
    }
}

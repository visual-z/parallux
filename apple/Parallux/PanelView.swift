import ParalluxKit
import SwiftUI

/// The menu bar panel (left click), laid out as design v0.2: switch, mini
/// flow, links, aggregation mode, exit, footer. It answers "which links am I
/// on, do I want another node". Nothing displays simulated data.
struct PanelView: View {
    let app: AppModel
    let openMainWindow: () -> Void
    let openSettings: () -> Void

    var body: some View {
        NavigationStack {
            PanelHome(app: app, openMainWindow: openMainWindow, openSettings: openSettings)
                .navigationDestination(for: PanelRoute.self) { route in
                    switch route {
                    case .nodes: PanelNodesView(session: app.session)
                    }
                }
        }
        .frame(width: 340)
        .environment(app.session)
        .onAppear { app.session.retainConnections() }
        .onDisappear { app.session.releaseConnections() }
    }
}

enum PanelRoute: Hashable { case nodes }

private struct PanelHome: View {
    let app: AppModel
    let openMainWindow: () -> Void
    let openSettings: () -> Void

    private func switchBinding(_ which: ConnectionSwitches.Which) -> Binding<Bool> {
        Binding(get: { which == .aggregation ? app.switches.aggregation : app.switches.proxy },
                set: { on in Task { await app.setSwitch(which, on: on) } })
    }

    var body: some View {
        // Design v0.2's panel: flat rows under small section titles, parted
        // by hairlines (docs/tasks/fix-panel-design-parity.md). System
        // controls throughout, apart from the round link switch.
        VStack(alignment: .leading, spacing: 0) {
            header.padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 8)
            if let server = app.remote.active {
                Label("\(server.name) · 远程", systemImage: "desktopcomputer").font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 16).padding(.bottom, 6)
            }
            if app.tunnel.isConnected { strip.padding(.horizontal, 12) }
            switches.padding(.horizontal, 16).padding(.top, 8)
            PanelSeparator()
            PanelSection(title: "线路") { links }
            PanelSeparator()
            PanelSection(title: "聚合方式") { aggregation }
            PanelSeparator()
            PanelSection(title: "出口") { exit }
            footer.padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 12)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Parallux").font(.headline)
                Text(app.statusLine).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
        }
    }

    /// 聚合 and 代理, the two switches of decision 21; both off disconnects.
    /// They took the place of the design's single switch in the header.
    @ViewBuilder private var switches: some View {
        let busy = app.tunnel.isBusy || !app.controlsLocalCore
        PanelSwitchRow(symbol: "point.3.connected.trianglepath.dotted", title: "聚合",
                       detail: app.enabledLinks.count < 2 ? "不可用" : "\(app.linkSettings.value.mode.title) · \(app.enabledLinks.count) 条线路",
                       isOn: switchBinding(.aggregation))
            .disabled(busy || app.enabledLinks.count < 2)
        PanelSwitchRow(symbol: "globe", title: "代理", detail: app.profiles.store.selected?.name ?? "无配置",
                       isOn: switchBinding(.proxy))
            .disabled(busy)
    }

    private var strip: some View {
        let diagram = FlowModel.diagram(app)
        return PanelStrip(download: RateFormat.bitsPerSecond(app.session.status?.downlink ?? 0),
                          upload: RateFormat.bitsPerSecond(app.session.status?.uplink ?? 0), action: openMainWindow) {
            FlowDiagram(links: diagram.links, exits: diagram.exits, capacity: diagram.capacity, isCompact: true)
        }
    }

    /// Every link in priority order, each with its round switch (on = takes
    /// part in aggregation).
    @ViewBuilder private var links: some View {
        let prefs = app.linkSettings.value.preferences
        let ordered = app.links.links.sorted { a, b in
            let ia = prefs.order.firstIndex(of: a.name) ?? Int.max
            let ib = prefs.order.firstIndex(of: b.name) ?? Int.max
            return ia != ib ? ia < ib : a.name < b.name
        }
        let unhealthy = Set(app.activeLinks.map(\.name).filter { app.linkStats.link(ProfileComposer.linkTag($0))?.healthy == false })
        let standings = LinkStanding.all(enabled: app.activeLinks.map(\.name), backup: prefs.backup, unhealthy: unhealthy, mode: app.effectiveMode)
        if ordered.isEmpty {
            Text("不可用").foregroundStyle(.secondary).frame(minHeight: 30)
        }
        ForEach(ordered) { link in
            // Enabled but not in use (聚合 is off): no standing, nothing to report.
            let standing = standings[link.name] ?? (prefs.disabled.contains(link.name) ? .disabled : nil)
            PanelLinkRow(symbol: link.kind.symbol, name: link.kind.title, badge: standing?.badge,
                         detail: "\(link.displayName) · \(link.name)", trailing: carried(link, standing),
                         color: LinkColors.color(for: link, in: app.links.links),
                         isOn: Binding(
                             get: { !app.linkSettings.value.preferences.disabled.contains(link.name) },
                             set: { on in
                                 if on { app.linkSettings.value.preferences.disabled.remove(link.name) } else { app.linkSettings.value.preferences.disabled.insert(link.name) }
                                 Task { await app.applyLinkChanges() }
                             }
                         ))
        }
    }

    /// The right-hand side of a link row: 已停用, 不可用, 待命 or the live rate.
    private func carried(_ link: LinkInterface, _ standing: LinkStanding?) -> String {
        guard let standing else { return "" }
        if standing == .disabled { return OverviewCopy.linkDetail(enabled: false, standby: false, rate: 0) }
        guard app.tunnel.isConnected else { return "" }
        let tag = ProfileComposer.linkTag(link.name)
        if let stat = app.linkStats.link(tag), !stat.healthy { return "不可用" }
        return OverviewCopy.linkDetail(enabled: true, standby: standing == .standby, rate: app.linkStats.rates[tag]?.total ?? 0)
    }

    @ViewBuilder private var aggregation: some View {
        let modes = AggregationMode.allCases
        FillSegmentedControl(labels: modes.map(\.title), selection: Binding(
            get: { modes.firstIndex(of: app.linkSettings.value.mode) ?? -1 },
            set: { index in if modes.indices.contains(index) { Task { await app.setMode(modes[index]) } } }
        ))
        .accessibilityLabel("聚合方式")
        .disabled(app.enabledLinks.count < 2 || !app.controlsLocalCore)
        if let notice = app.aggregationNotice {
            Text(notice).font(.caption).foregroundStyle(.secondary).padding(.top, 4)
        }
        // Only 叠加 goes through a server (design: the row is hidden otherwise).
        if app.linkSettings.value.mode == .bond {
            PanelRow(title: "聚合服务器") {
                // A Menu, not a decorative chevron: pick the server or open the page.
                Menu(app.bondServerSummary ?? "无服务器") {
                    ForEach(app.servers.servers) { server in
                        Toggle(server.name, isOn: Binding(
                            get: { app.linkSettings.value.bondServerID == server.id },
                            set: { on in
                                app.linkSettings.value.bondServerID = on ? server.id : nil
                                Task { await app.applyLinkChanges() }
                            }
                        ))
                    }
                    if !app.servers.servers.isEmpty { Divider() }
                    Button("新建服务器…") { openMainWindow(); app.pendingSidebar = .aggregationServer }
                }
                .menuStyle(.borderlessButton).fixedSize()
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder private var exit: some View {
        let session = app.session
        PanelRow(title: "路由") {
            Picker("路由模式", selection: Binding(get: { session.routeMode ?? "" }, set: { session.setRouteMode($0) })) {
                ForEach(session.routeModes, id: \.self) { Text(RouteMode.title($0)).tag($0) }
            }
            .labelsHidden().pickerStyle(.menu).fixedSize()
            .disabled(session.routeModes.isEmpty)
        }
        PanelRow(title: "节点") {
            NavigationLink(value: PanelRoute.nodes) {
                HStack(spacing: 4) {
                    if let group = session.groups.first(where: \.selectable) {
                        let delay = group.items.first { $0.tag == group.selected }?.delay ?? 0
                        Text(delay > 0 ? "\(group.selected) · \(delay) ms" : group.selected).lineLimit(1).monospacedDigit()
                    } else {
                        Text("暂无可用代理组")
                    }
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(session.groups.isEmpty)
        }
    }

    private var footer: some View {
        HStack {
            Button("打开主窗口", action: openMainWindow).buttonBorderShape(.capsule)
            Spacer()
            Menu("更多", systemImage: "ellipsis") {
                Button("设置…", action: openSettings)
                Divider()
                Button("退出 Parallux") { NSApp.terminate(nil) }
            }
            .labelStyle(.iconOnly).menuIndicator(.hidden).buttonBorderShape(.circle).fixedSize()
        }
    }
}

/// Drill-down from the panel: pick a node, search, test delays.
private struct PanelNodesView: View {
    let session: CoreSession
    @State private var search = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // A popover has no toolbar, so back, title and search live in the content.
            HStack(spacing: 6) {
                Button("返回", systemImage: "chevron.backward") { dismiss() }
                    .labelStyle(.iconOnly).buttonStyle(.borderless)
                    .keyboardShortcut(.cancelAction)
                Text("节点").font(.headline)
            }
            TextField("搜索", text: $search, prompt: Text("搜索"))
                .textFieldStyle(.roundedBorder)
            List {
                ForEach(session.groups.filter(\.selectable)) { group in
                    Section {
                        ForEach(group.items.filter { search.isEmpty || $0.tag.localizedCaseInsensitiveContains(search) }) { item in
                            Button {
                                session.select(group: group.tag, outbound: item.tag)
                            } label: {
                                LabeledContent {
                                    let grade = LatencyGrade(milliseconds: item.delay)
                                    Text(verbatim: item.delay > 0 ? "\(item.delay) ms" : "—").monospacedDigit().foregroundStyle(grade.color)
                                } label: {
                                    // Checkmark only on the pick, blank space elsewhere (menu convention).
                                    Label {
                                        Text(item.tag)
                                    } icon: {
                                        Image(systemName: "checkmark").opacity(item.tag == group.selected ? 1 : 0)
                                    }
                                    .foregroundStyle(item.tag == group.selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        HStack {
                            Text(group.tag)
                            Spacer()
                            Button("延迟测试", systemImage: "bolt") { session.urlTest(group: group.tag) }
                                .labelStyle(.iconOnly).buttonStyle(.borderless)
                                .disabled(session.testing.contains(group.tag))
                        }
                    }
                }
            }
            .listStyle(.inset)
            .frame(height: 360)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .navigationBarBackButtonHidden(true)
    }
}

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
        VStack(alignment: .leading, spacing: 10) {
            header
            if let server = app.remote.active {
                Label("\(server.name) · 远程", systemImage: "desktopcomputer").font(.caption).foregroundStyle(.secondary)
            }
            if app.tunnel.isConnected { miniFlow }
            // A grouped Form, so rows get the system's label/control layout
            // (control trailing, subtitle under the title) instead of hand-made HStacks.
            Form {
                Section { switches }
                Section("线路") { links }
                Section("聚合方式") { aggregation }
                Section("出口") { exit }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .scrollContentBackground(.hidden)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, -14)
            footer
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Parallux").font(.headline)
                Text(app.statusLine).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
        }
    }

    /// 聚合 and 代理, the two switches of decision 21; both off disconnects.
    @ViewBuilder private var switches: some View {
        let busy = app.tunnel.isBusy || !app.controlsLocalCore
        Toggle(isOn: switchBinding(.aggregation)) {
            Label {
                Text("聚合")
                Text(app.enabledLinks.count < 2 ? "不可用" : "\(app.linkSettings.value.mode.title) · \(app.enabledLinks.count) 条线路")
            } icon: {
                Image(systemName: "point.3.connected.trianglepath.dotted")
            }
        }
        .disabled(busy || app.enabledLinks.count < 2)
        Toggle(isOn: switchBinding(.proxy)) {
            Label {
                Text("代理")
                Text(app.profiles.store.selected?.name ?? "无配置")
            } icon: {
                Image(systemName: "globe")
            }
        }
        .disabled(busy)
    }

    private var miniFlow: some View {
        Button(action: openMainWindow) {
            HStack(spacing: 10) {
                FlowDiagram(links: FlowModel.links(app), exits: FlowModel.exits(app), showsLabels: false)
                    .frame(height: 44)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(RateFormat.bitsPerSecond(app.session.status?.downlink ?? 0)).font(.callout.weight(.semibold))
                    Text("↑ " + RateFormat.bitsPerSecond(app.session.status?.uplink ?? 0)).font(.caption2).foregroundStyle(.secondary)
                }
                .monospacedDigit()
                .frame(width: 84, alignment: .trailing)
            }
            .padding(8)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .help("打开主窗口")
    }

    /// Each link is a system Toggle row (on = takes part in aggregation).
    @ViewBuilder private var links: some View {
        if app.links.links.isEmpty {
            Text("不可用").foregroundStyle(.secondary)
        }
        ForEach(app.links.links) { link in
            let tag = ProfileComposer.linkTag(link.name)
            Toggle(isOn: Binding(
                get: { !app.linkSettings.value.preferences.disabled.contains(link.name) },
                set: { on in
                    if on { app.linkSettings.value.preferences.disabled.remove(link.name) } else { app.linkSettings.value.preferences.disabled.insert(link.name) }
                    Task { await app.applyLinkChanges() }
                }
            )) {
                Label {
                    Text(link.kind.title)
                    Text(linkDetail(link, tag: tag))
                } icon: {
                    Image(systemName: link.kind.symbol).foregroundStyle(LinkColors.color(for: link, in: app.links.links))
                }
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
    }

    private func linkDetail(_ link: LinkInterface, tag: String) -> String {
        if let stat = app.linkStats.link(tag), !stat.healthy { return "\(link.name) · 不可用" }
        if let rate = app.linkStats.rates[tag] { return "\(link.name) · \(RateFormat.bitsPerSecond(rate.total))" }
        return "\(link.displayName) · \(link.name)"
    }

    @ViewBuilder private var aggregation: some View {
        Picker("聚合方式", selection: Binding(get: { app.linkSettings.value.mode }, set: { mode in Task { await app.setMode(mode) } })) {
            ForEach(AggregationMode.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented).labelsHidden()
        .frame(maxWidth: .infinity)
        .disabled(app.enabledLinks.count < 2)
        if let notice = app.aggregationNotice {
            Text(notice).font(.caption).foregroundStyle(.secondary)
        }
        // A Menu, not a decorative chevron: pick the server or open the page.
        LabeledContent("聚合服务器") {
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
    }

    @ViewBuilder private var exit: some View {
        let session = app.session
        LabeledContent("模式") {
            Picker("模式", selection: Binding(get: { session.routeMode ?? "" }, set: { session.setRouteMode($0) })) {
                ForEach(session.routeModes, id: \.self) { Text(RouteMode.title($0)).tag($0) }
            }
            .labelsHidden().pickerStyle(.menu).fixedSize()
            .disabled(session.routeModes.isEmpty)
        }
        LabeledContent("节点") {
            NavigationLink(value: PanelRoute.nodes) {
                if let group = session.groups.first(where: \.selectable) {
                    let delay = group.items.first { $0.tag == group.selected }?.delay ?? 0
                    Text(delay > 0 ? "\(group.selected) · \(delay) ms" : group.selected)
                } else {
                    Text("暂无可用代理组")
                }
            }
            .disabled(session.groups.isEmpty)
        }
    }

    private var footer: some View {
        HStack {
            Button("打开主窗口", action: openMainWindow)
            Spacer()
            Menu("更多", systemImage: "ellipsis") {
                Button("设置…", action: openSettings)
                Divider()
                Button("退出 Parallux") { NSApp.terminate(nil) }
            }
            .labelStyle(.iconOnly).menuIndicator(.hidden).menuStyle(.borderlessButton).fixedSize()
        }
        .controlSize(.small)
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            content()
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

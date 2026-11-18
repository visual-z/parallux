import ParalluxKit
import SwiftUI

/// The menu bar panel (left click), laid out as design v0.2: switch, mini
/// flow, links, aggregation mode, exit, footer. It answers "which links am I
/// on, do I want another node". Controls that need M3/M4 are shown disabled
/// with their milestone; nothing displays simulated data.
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

    private var isOn: Binding<Bool> {
        Binding(get: { app.isOn }, set: { on in Task { await app.setOn(on) } })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if app.tunnel.isConnected { miniFlow }
            section("线路") { links }
            Divider()
            section("聚合方式") { aggregation }
            Divider()
            section("出口") { exit }
            footer
        }
        .padding(14)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Parallux").font(.headline)
                Text(app.statusLine).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            Toggle("开启 Parallux", isOn: isOn).toggleStyle(.switch).labelsHidden()
                .disabled(app.tunnel.isBusy)
        }
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
        .help("打开主窗口概览")
    }

    @ViewBuilder private var links: some View {
        if let link = app.defaultLink.link {
            HStack(spacing: 10) {
                Image(systemName: link.symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 26, height: 26).background(FlowModel.linkColors[0], in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(link.kind)
                    Text(link.name).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let status = app.session.status {
                    Text(RateFormat.bitsPerSecond(status.downlink + status.uplink)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            Text("其他线路的发现与开关在 M3 接入。").font(.caption2).foregroundStyle(.tertiary)
        } else {
            Text("没有可用的网络").font(.callout).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var aggregation: some View {
        Picker("聚合方式", selection: .constant(app.settings.value.defaultAggregationMode)) {
            ForEach(AggregationMode.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented).labelsHidden()
        .disabled(true)
        .help("需要两条以上线路，M3 接入")
        HStack {
            Text("聚合服务器")
            Spacer()
            Text("M4 接入").foregroundStyle(.tertiary)
        }
        .font(.callout)
    }

    @ViewBuilder private var exit: some View {
        let session = app.session
        HStack {
            Text("路由")
            Spacer()
            if session.routeModes.isEmpty {
                Text("—").foregroundStyle(.tertiary)
            } else {
                RouteModeMenu().fixedSize()
            }
        }
        .font(.callout)
        NavigationLink(value: PanelRoute.nodes) {
            HStack {
                Text("节点")
                Spacer()
                if let group = session.groups.first(where: \.selectable) {
                    let delay = group.items.first { $0.tag == group.selected }?.delay ?? 0
                    Text(group.selected).foregroundStyle(.secondary)
                    if delay > 0 {
                        Text("· \(delay) ms").foregroundStyle(DelayGrade(milliseconds: delay).color)
                    }
                } else {
                    Text("—").foregroundStyle(.tertiary)
                }
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .font(.callout)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(session.groups.isEmpty)
    }

    private var footer: some View {
        HStack {
            Button("打开主窗口", action: openMainWindow).buttonStyle(.bordered).controlSize(.small)
            Spacer()
            Menu {
                Button("设置…", action: openSettings)
                Divider()
                Button("退出 Parallux") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.button).menuIndicator(.hidden).buttonStyle(.bordered).controlSize(.small).fixedSize()
            .help("更多")
        }
        .padding(.top, 2)
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            content()
        }
    }
}

/// Drill-down from the panel: pick a node, search, test delays.
private struct PanelNodesView: View {
    let session: CoreSession
    @State private var search = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("搜索节点", text: $search).textFieldStyle(.roundedBorder)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(session.groups.filter(\.selectable)) { group in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(group.tag).font(.caption.weight(.semibold))
                                Spacer()
                                Button("测速", systemImage: "bolt") { session.urlTest(group: group.tag) }
                                    .labelStyle(.iconOnly).buttonStyle(.borderless)
                                    .disabled(session.testing.contains(group.tag))
                            }
                            ForEach(group.items.filter { search.isEmpty || $0.tag.localizedCaseInsensitiveContains(search) }) { item in
                                Button {
                                    session.select(group: group.tag, outbound: item.tag)
                                } label: {
                                    HStack {
                                        Image(systemName: item.tag == group.selected ? "checkmark" : "")
                                            .frame(width: 14)
                                        Text(item.tag)
                                        Spacer()
                                        let grade = DelayGrade(milliseconds: item.delay)
                                        Text(grade == .untested ? "—" : "\(item.delay) ms").foregroundStyle(grade.color).monospacedDigit()
                                    }
                                    .font(.callout)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 360)
        }
        .padding(14)
        .navigationTitle("节点")
    }
}

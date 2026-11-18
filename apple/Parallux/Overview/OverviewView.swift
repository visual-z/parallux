import Charts
import ParalluxKit
import SwiftUI

/// 主窗口「概览」：流向图、流量曲线、路由模式与系统代理、配置卡片（设计稿 v0.2）。
struct OverviewView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let session = app.session
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !session.deprecatedNotes.isEmpty, !app.settings.value.hideDeprecatedNotes {
                    DeprecationBanner(notes: session.deprecatedNotes) { app.settings.value.hideDeprecatedNotes = true }
                }
                Text("宽度 = 实时速率。左边每条线路一股，中间是汇总，右边是流量的去向。")
                    .font(.caption).foregroundStyle(.secondary)
                Group {
                    let columns = FlowModel.columns(app)
                    if session.isRunning, !columns.links.isEmpty, !columns.exits.isEmpty {
                        FlowDiagram(links: columns.links, exits: columns.exits,
                                    centerLabel: "\(app.effectiveMode?.title ?? "汇总") · " + RateFormat.bitsPerSecond((session.status?.downlink ?? 0) + (session.status?.uplink ?? 0)))
                    } else {
                        ContentUnavailableView(session.isRunning ? "暂无流量" : "未连接", systemImage: "point.3.connected.trianglepath.dotted",
                                               description: Text(session.isRunning ? "有连接产生流量时显示流向。" : "开启 Parallux 后显示实时流向。"))
                    }
                }
                .frame(height: 280)
                .frame(maxWidth: .infinity)

                HStack(alignment: .top, spacing: 12) {
                    ForEach(app.settings.value.dashboard.visible) { card in
                        switch card {
                        case .traffic: TrafficCard(session: session)
                        case .routeMode: RouteCard(app: app)
                        case .profile: ProfileCard(app: app)
                        }
                    }
                }
                .contextMenu { DashboardMenu(app: app) }
            }
            .padding(20)
        }
        .navigationSubtitle(app.statusLine)
        .onAppear { session.retainConnections() }
        .onDisappear { session.releaseConnections() }
    }
}

/// Right-click on the cards: show or hide each, move, reset (SFM #34).
private struct DashboardMenu: View {
    let app: AppModel
    var body: some View {
        ForEach(DashboardCard.allCases) { card in
            Toggle(card.title, isOn: Binding(
                get: { !app.settings.value.dashboard.hidden.contains(card) },
                set: { show in
                    if show { app.settings.value.dashboard.hidden.remove(card) } else { app.settings.value.dashboard.hidden.insert(card) }
                }
            ))
        }
        Divider()
        ForEach(Array(app.settings.value.dashboard.order.enumerated()), id: \.element) { index, card in
            if index > 0 {
                Button("把「\(card.title)」左移") { app.settings.value.dashboard.move(fromOffsets: [index], toOffset: index - 1) }
            }
        }
        Divider()
        Button("恢复默认卡片") { app.settings.value.dashboard.reset() }
    }
}

/// The running configuration's deprecation notes (SFM #76), dismissable for good.
private struct DeprecationBanner: View {
    let notes: [String]
    let hide: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("当前配置用到了 sing-box 弃用的写法", systemImage: "exclamationmark.triangle").font(.callout.weight(.medium))
            ForEach(notes, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
            Button("不再提示", action: hide).controlSize(.small)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct Card<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct TrafficCard: View {
    let session: CoreSession
    var body: some View {
        Card(title: "流量") {
            let status = session.status
            Text(RateFormat.bitsPerSecond((status?.downlink ?? 0) + (status?.uplink ?? 0)))
                .font(.title2.weight(.semibold)).monospacedDigit()
            let points = Array(session.rateHistory.elements.enumerated())
            Chart(points, id: \.offset) { index, point in
                AreaMark(x: .value("t", index), y: .value("速率", point.downlink + point.uplink))
                    .foregroundStyle(.blue.opacity(0.25))
                LineMark(x: .value("t", index), y: .value("速率", point.downlink + point.uplink))
                    .foregroundStyle(.blue)
            }
            .chartXAxis(.hidden).chartYAxis(.hidden)
            .chartXScale(domain: 0...max(CoreSession.rateHistoryCapacity - 1, 1))
            .frame(height: 44)
            Text("本次会话 ↓ \(RateFormat.bytes(status?.downlinkTotal ?? 0)) · ↑ \(RateFormat.bytes(status?.uplinkTotal ?? 0))")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct RouteCard: View {
    let app: AppModel
    var body: some View {
        @Bindable var settings = app.settings
        let session = app.session
        Card(title: "路由模式") {
            if session.routeModes.isEmpty {
                Text(session.isRunning ? "配置没有定义路由模式" : "连接后可选").font(.callout).foregroundStyle(.secondary)
            } else {
                Picker("路由模式", selection: Binding(get: { session.routeMode ?? "" }, set: { session.setRouteMode($0) })) {
                    ForEach(session.routeModes, id: \.self) { Text(RouteMode.title($0)).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden()
            }
            Toggle("系统 HTTP 代理", isOn: $settings.value.tunnel.systemProxyEnabled)
                .toggleStyle(.switch).font(.callout)
                .help("只在配置的 tun 入站开了 platform.http_proxy 时有效；下次连接生效")
        }
    }
}

private struct ProfileCard: View {
    let app: AppModel
    var body: some View {
        Card(title: "配置") {
            if let profile = app.profiles.store.selected {
                Text(profile.name).font(.headline)
                Text(ProfileDescription.detail(profile, now: Date())).font(.caption).foregroundStyle(.secondary)
            } else {
                Text("示例配置").font(.headline)
                Text("还没有配置；在「配置」页添加").font(.caption).foregroundStyle(.secondary)
            }
            if let status = app.session.status {
                Text("连接 \(status.connections) · 内存 \(RateFormat.bytes(status.memory))").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

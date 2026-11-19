import Charts
import ParalluxKit
import SwiftUI

/// 主窗口「概览」：流向图、流量曲线、路由模式与系统代理、配置卡片（设计稿 v0.2）。
struct OverviewView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let session = app.session
        if !session.isRunning && (!app.tunnel.hasConfiguration || app.tunnel.phase == .awaitingApproval) {
            // First run: the checklist replaces the empty state until the
            // extension and VPN configuration exist.
            Form { SetupSection() }
                .formStyle(.grouped)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
                .navigationSubtitle(app.statusLine)
        } else if !session.isRunning {
            ContentUnavailableView {
                Label("未连接", systemImage: "point.3.connected.trianglepath.dotted")
            } description: {
                Text(app.profiles.store.selected?.name ?? "")
            } actions: {
                Button("连接") { Task { await app.setOn(true) } }.buttonStyle(.borderedProminent)
                    .disabled(!app.controlsLocalCore || app.tunnel.isBusy)
                SwitchesForm(app: app).frame(width: 320)
            }
            .navigationSubtitle(app.statusLine)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !session.deprecatedNotes.isEmpty, !app.settings.value.hideDeprecatedNotes {
                        DeprecationBanner(notes: session.deprecatedNotes) { app.settings.value.hideDeprecatedNotes = true }
                    }
                    HeldFlowDiagram(app: app)
                    .frame(height: 240)
                    .padding(12)
                    .background(.fill.quinary, in: RoundedRectangle(cornerRadius: 12))

                    // Cards wrap to fewer columns in a narrow window.
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12, alignment: .top)], spacing: 12) {
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
                .padding(16)
            }
            .navigationSubtitle(app.statusLine)
            .onAppear { session.retainConnections() }
            .onDisappear { session.releaseConnections() }
        }
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
                Button("上移「\(card.title)」") { app.settings.value.dashboard.move(fromOffsets: [index], toOffset: index - 1) }
            }
        }
        Divider()
        Button("重置为默认值") { app.settings.value.dashboard.reset() }
    }
}

/// The running configuration's deprecation notes (SFM #76), dismissable for good.
private struct DeprecationBanner: View {
    let notes: [String]
    let hide: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("弃用警告", systemImage: "exclamationmark.triangle").font(.callout.weight(.medium))
            ForEach(notes, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
            Button("禁用弃用警告", action: hide).controlSize(.small)
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
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.fill.quinary, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct TrafficCard: View {
    let session: CoreSession
    var body: some View {
        Card(title: "速率") {
            let status = session.status
            Text(RateFormat.bitsPerSecond((status?.downlink ?? 0) + (status?.uplink ?? 0)))
                .font(.title2.weight(.semibold)).monospacedDigit()
            let points = Array(session.rateHistory.elements.enumerated())
            if points.count > 1 {
            Chart(points, id: \.offset) { index, point in
                AreaMark(x: .value("t", index), y: .value("速率", point.downlink + point.uplink))
                    .foregroundStyle(.blue.opacity(0.25))
                LineMark(x: .value("t", index), y: .value("速率", point.downlink + point.uplink))
                    .foregroundStyle(.blue)
            }
            .chartXAxis(.hidden).chartYAxis(.hidden)
            .chartXScale(domain: 0...max(CoreSession.rateHistoryCapacity - 1, 1))
            .frame(height: 44)
            }
            Text("流量 ↓ \(RateFormat.bytes(status?.downlinkTotal ?? 0)) · ↑ \(RateFormat.bytes(status?.uplinkTotal ?? 0))")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct RouteCard: View {
    let app: AppModel
    var body: some View {
        @Bindable var settings = app.settings
        let session = app.session
        Card(title: "模式") {
            if !session.routeModes.isEmpty {
                Picker("路由模式", selection: Binding(get: { session.routeMode ?? "" }, set: { session.setRouteMode($0) })) {
                    ForEach(session.routeModes, id: \.self) { Text(RouteMode.title($0)).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden()
            }
            // Decision 21: the two switches sit with the other mode controls.
            Toggle("聚合", isOn: Binding(get: { app.switches.aggregation }, set: { on in Task { await app.setSwitch(.aggregation, on: on) } }))
                .toggleStyle(.switch).font(.callout)
                .disabled(app.tunnel.isBusy || !app.controlsLocalCore || app.enabledLinks.count < 2)
            Toggle("代理", isOn: Binding(get: { app.switches.proxy }, set: { on in Task { await app.setSwitch(.proxy, on: on) } }))
                .toggleStyle(.switch).font(.callout)
                .disabled(app.tunnel.isBusy || !app.controlsLocalCore)
            Toggle("系统代理", isOn: $settings.value.tunnel.systemProxyEnabled)
                .toggleStyle(.switch).font(.callout)
                .help("修改操作系统的代理设置")
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
                Text("无配置").font(.headline).foregroundStyle(.secondary)
            }
            if let status = app.session.status {
                LabeledContent("连接", value: "\(status.connections)").font(.caption)
                LabeledContent("内存", value: RateFormat.bytes(status.memory)).font(.caption)
            }
        }
    }
}

/// 聚合 and 代理 on the overview (decision 21): off, both show off and
/// turning one on connects with just that one.
struct SwitchesForm: View {
    let app: AppModel

    private func binding(_ which: ConnectionSwitches.Which) -> Binding<Bool> {
        Binding(get: { which == .aggregation ? app.switches.aggregation : app.switches.proxy },
                set: { on in Task { await app.setSwitch(which, on: on) } })
    }

    var body: some View {
        let busy = app.tunnel.isBusy || !app.controlsLocalCore
        Form {
            Section {
                Toggle("聚合", isOn: binding(.aggregation)).disabled(busy || app.enabledLinks.count < 2)
                Toggle("代理", isOn: binding(.proxy)).disabled(busy)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .scrollContentBackground(.hidden)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// The overview's diagram, held through idle seconds (FlowHold) so it does
/// not blink between bursts of traffic (feat-link-view).
private struct HeldFlowDiagram: View {
    let app: AppModel
    @State private var held: [FlowNode] = []
    @State private var heldLinks: [FlowNode] = []
    @State private var heldAt: Date?

    var body: some View {
        let session = app.session
        let columns = FlowModel.columns(app)
        let hold = FlowHold.next(current: columns.exits, last: held, lastAt: heldAt, now: Date())
        let links = columns.exits.isEmpty ? heldLinks : columns.links
        Group {
            if !links.isEmpty, !hold.shown.isEmpty {
                FlowDiagram(links: links, exits: hold.shown,
                            centerLabel: "\(app.effectiveMode?.title ?? "") " + RateFormat.bitsPerSecond((session.status?.downlink ?? 0) + (session.status?.uplink ?? 0)))
            } else {
                ContentUnavailableView("暂无流量", systemImage: "point.3.connected.trianglepath.dotted")
            }
        }
        // Once a second while shown, like the status stream it follows.
        .task {
            while !Task.isCancelled {
                let now = FlowModel.columns(app)
                let next = FlowHold.next(current: now.exits, last: held, lastAt: heldAt, now: Date())
                held = next.last
                heldAt = next.lastAt
                if !now.exits.isEmpty { heldLinks = now.links }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

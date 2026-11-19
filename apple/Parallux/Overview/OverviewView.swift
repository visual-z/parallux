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
                VStack(alignment: .leading, spacing: 10) {
                    if !session.deprecatedNotes.isEmpty, !app.settings.value.hideDeprecatedNotes {
                        DeprecationBanner(notes: session.deprecatedNotes) { app.settings.value.hideDeprecatedNotes = true }
                    }
                    // Design v0.2: the diagram sits straight on the content
                    // layer, 330 pt tall, no box around it.
                    HeldFlowDiagram(app: app)
                        .frame(height: 330)
                    OverviewCardRow {
                        ForEach(app.settings.value.dashboard.visible) { card in
                            switch card {
                            case .traffic: trafficCard
                            case .routeMode: routeModeCard
                            case .profile: profileCard
                            }
                        }
                    }
                    .contextMenu { DashboardMenu(app: app) }
                }
                .padding(.horizontal, 16).padding(.bottom, 16)
            }
            .navigationSubtitle(OverviewCopy.subtitle(links: app.activeLinks.count, mode: app.effectiveMode, server: bondServerName, problem: problem))
            .toolbar {
                // Design v0.2: the aggregation mode is switched from the
                // overview's toolbar, next to the power button.
                ToolbarItem {
                    Picker("聚合方式", selection: Binding(get: { app.linkSettings.value.mode }, set: { mode in Task { await app.setMode(mode) } })) {
                        ForEach(AggregationMode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .disabled(app.enabledLinks.count < 2 || !app.controlsLocalCore)
                    .help("聚合方式")
                }
            }
            .onAppear { session.retainConnections() }
            .onDisappear { session.releaseConnections() }
        }
    }

    /// What the status line would say instead of 「已连接 · …」: a failed
    /// action, an extension that needs approval or failed, or a core the app
    /// cannot read. The same conditions StatusLine.text puts first.
    private var problem: String? {
        let setupNeedsAttention = switch app.tunnel.phase {
        case .awaitingApproval, .failed: true
        default: false
        }
        let any = setupNeedsAttention || app.lastError != nil || app.tunnel.startError != nil || app.session.lastError != nil
        return any ? app.statusLine : nil
    }

    /// The server 叠加 goes through, when 叠加 is what is in effect.
    private var bondServerName: String? {
        guard app.effectiveMode == .bond else { return nil }
        return app.servers.servers.first { $0.id == app.linkSettings.value.bondServerID }?.name
    }

    private var trafficCard: some View {
        let status = app.session.status
        return TrafficCard(rate: (status?.downlink ?? 0) + (status?.uplink ?? 0),
                           history: app.session.rateHistory.elements.map { $0.downlink &+ $0.uplink },
                           window: CoreSession.rateHistoryCapacity,
                           downlinkTotal: status?.downlinkTotal ?? 0, uplinkTotal: status?.uplinkTotal ?? 0)
    }

    private var routeModeCard: some View {
        @Bindable var settings = app.settings
        let session = app.session
        return RouteModeCard(modes: session.routeModes,
                             mode: Binding(get: { session.routeMode ?? "" }, set: { session.setRouteMode($0) }),
                             topRule: OverviewCopy.topRule(session.connections),
                             aggregation: Binding(get: { app.switches.aggregation }, set: { on in Task { await app.setSwitch(.aggregation, on: on) } }),
                             aggregationDisabled: app.tunnel.isBusy || !app.controlsLocalCore || app.enabledLinks.count < 2,
                             proxy: Binding(get: { app.switches.proxy }, set: { on in Task { await app.setSwitch(.proxy, on: on) } }),
                             proxyDisabled: app.tunnel.isBusy || !app.controlsLocalCore,
                             systemProxy: $settings.value.tunnel.systemProxyEnabled,
                             systemProxyDisabled: !app.controlsLocalCore)
    }

    private var profileCard: some View {
        let profile = app.profiles.store.selected
        let status = app.session.status
        return ProfileCard(name: profile?.name, detail: profile.map { ProfileDescription.detail($0, now: Date()) } ?? "",
                           connections: status.map { Int($0.connections) }, memory: status?.memory)
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
/// not fall back to bare nodes between bursts of traffic (feat-link-view).
/// The whole last picture is kept: links, exits, label and scale together.
private struct HeldFlowDiagram: View {
    let app: AppModel
    @State private var held: FlowModel.Diagram?
    @State private var heldAt: Date?

    var body: some View {
        let current = FlowModel.diagram(app)
        let hold = FlowHold.next(current: current.exits, last: held?.exits ?? [], lastAt: heldAt, now: Date())
        let shown = current.exits.isEmpty && !hold.shown.isEmpty ? held ?? current : current
        FlowDiagram(links: shown.links, exits: shown.exits, centerLabel: shown.centre, capacity: shown.capacity)
            // Once a second while shown, like the status stream it follows.
            .task {
                while !Task.isCancelled {
                    let now = FlowModel.diagram(app)
                    if !now.exits.isEmpty {
                        held = now
                        heldAt = Date()
                    }
                    try? await Task.sleep(for: .seconds(1))
                }
            }
    }
}

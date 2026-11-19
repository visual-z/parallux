import ParalluxKit
import SwiftUI

/// The main window: a NavigationSplitView with the standard (Liquid Glass)
/// sidebar. Glass is left to the system components; content stays opaque.
struct MainWindow: View {
    static let id = "main"
    /// Receives SwiftUI's scene actions; environment values are only reachable
    /// from a view, and the status item (AppKit) needs them.
    var onSceneActionsAvailable: (SceneActions) -> Void = { _ in }

    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @Environment(AppModel.self) private var app
    @State private var selection: SidebarItem? = .overview

    var body: some View {
        NavigationSplitView {
            SidebarList(selection: $selection, badge: badge(for:))
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
            .safeAreaInset(edge: .bottom) { uptime }
        } detail: {
            let item = selection ?? .overview
            Group {
                switch item {
                case .overview: OverviewView()
                case .connections: ConnectionsView()
                case .logs: LogsView()
                case .links: LinksView()
                case .aggregationServer: AggregationServersView()
                case .diagnostics: DiagnosticsView()
                case .profiles: ProfilesView()
                case .routing: RoutingView()
                }
            }
            .navigationTitle(item.title)
            .safeAreaInset(edge: .top) {
                if let server = app.remote.active {
                    HStack {
                        Label("远程 · \(server.name)", systemImage: "desktopcomputer")
                        Spacer()
                        Button("本机") { app.remote.activate(nil, session: app.session, localConnected: app.tunnel.isConnected) }
                    }
                    .font(.callout)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(.tint.opacity(0.15))
                }
            }
            // Design v0.2: the power button is the last item, right of the page's
            // own controls. A toolbar's items come in the order of the views
            // that declare them, and only an overlay comes after the page
            // itself: rendered four ways on 2026-11-20, `.primaryAction`, a
            // plain item and a background all put the button first
            // (docs/tasks/fix-ui-details.md).
            .overlay {
                Color.clear.allowsHitTesting(false).toolbar {
                    ToolbarSpacer(.fixed)
                    ToolbarItem {
                        // A plain button tinted while Parallux is on; not a
                        // toggle with a filled "selected" background.
                        Button {
                            Task { await app.setOn(!app.isOn) }
                        } label: {
                            Label(app.isOn ? "关闭 Parallux" : "开启 Parallux", systemImage: "power")
                                .foregroundStyle(app.isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        }
                        .disabled(app.tunnel.isBusy || !app.controlsLocalCore)
                        .help(app.isOn ? "关闭 Parallux" : "开启 Parallux")
                    }
                }
            }
        }
        // copy-and-style.md: minimum 760×520; pages fold to one column below that.
        .frame(minWidth: 760, minHeight: 520)
        .onAppear { onSceneActionsAvailable(SceneActions(openWindow: openWindow, openSettings: openSettings)) }
        .onReceive(NotificationCenter.default.publisher(for: .explainRoute)) { _ in selection = .routing }
        // onAppear too: the window may be created after the panel set it.
        .onAppear { if let item = app.pendingSidebar { selection = item; app.pendingSidebar = nil } }
        .onChange(of: app.pendingSidebar) { _, item in
            if let item { selection = item; app.pendingSidebar = nil }
        }
    }

    private func badge(for item: SidebarItem) -> Int {
        switch item {
        case .connections: Int(app.session.status?.connections ?? 0)
        case .profiles: app.profiles.store.profiles.count
        case .links: app.enabledLinks.count
        default: 0
        }
    }

    /// "已运行 2:14:07" at the bottom of the sidebar.
    private var uptime: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 6) {
                Circle().fill(app.tunnel.isConnected ? .green : .secondary).frame(width: 7, height: 7)
                if let started = app.tunnel.connectedDate, app.tunnel.isConnected {
                    Text("已运行 " + Self.duration(context.date.timeIntervalSince(started)))
                } else {
                    Text("未连接")
                }
            }
            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
    }
}

/// SwiftUI scene actions captured for AppKit callers.
struct SceneActions {
    let openWindow: OpenWindowAction
    let openSettings: OpenSettingsAction
}

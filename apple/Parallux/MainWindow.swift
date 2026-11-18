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
            List(selection: $selection) {
                ForEach(SidebarSection.allCases) { section in
                    if let title = section.title {
                        Section(title) { rows(section) }
                    } else {
                        Section { rows(section) }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
            .safeAreaInset(edge: .bottom) { uptime }
        } detail: {
            let item = selection ?? .overview
            Group {
                switch item {
                case .overview: OverviewView()
                case .connections: ConnectionsView()
                case .logs: LogsView()
                case .links:
                    ContentUnavailableView("线路", systemImage: item.symbol,
                                           description: Text("线路发现、开关、排序与逐线路统计在 M3 接入；先等 research-sysext-bind-interface 的实测结论。"))
                case .aggregationServer:
                    ContentUnavailableView("聚合服务器", systemImage: item.symbol,
                                           description: Text("叠加所需的聚合服务器与一键部署在 M4 接入。"))
                case .diagnostics: DiagnosticsView()
                case .profiles: ProfilesView()
                case .outbounds: OutboundsView()
                case .rules: RulesView()
                }
            }
            .navigationTitle(item.title)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Toggle(isOn: Binding(get: { app.isOn }, set: { on in Task { await app.setOn(on) } })) {
                        Label(app.isOn ? "关闭 Parallux" : "开启 Parallux", systemImage: "power")
                    }
                    .disabled(app.tunnel.isBusy)
                    .help(app.isOn ? "关闭 Parallux" : "开启 Parallux")
                }
            }
        }
        .onAppear { onSceneActionsAvailable(SceneActions(openWindow: openWindow, openSettings: openSettings)) }
    }

    private func rows(_ section: SidebarSection) -> some View {
        ForEach(section.items) { item in
            Label(item.title, systemImage: item.symbol)
                .badge(badge(for: item))
                .tag(item)
        }
    }

    private func badge(for item: SidebarItem) -> Int {
        switch item {
        case .connections: Int(app.session.status?.connections ?? 0)
        case .profiles: app.profiles.store.profiles.count
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

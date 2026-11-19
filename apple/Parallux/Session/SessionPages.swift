import AppKit
import Libbox
import ParalluxKit
import SwiftUI

/// Shown on pages that read the running core while the tunnel is off.
struct NotConnectedView: View {
    let title: String
    let symbol: String
    var body: some View {
        ContentUnavailableView(title, systemImage: symbol, description: Text("服务未启动"))
    }
}

/// Route-mode menu shared by the toolbar of several pages ("路由：规则").
struct RouteModeMenu: View {
    @Environment(CoreSession.self) private var session
    var body: some View {
        if !session.routeModes.isEmpty {
            Menu(RouteMode.title(session.routeMode ?? "")) {
                ForEach(session.routeModes, id: \.self) { mode in
                    Button {
                        session.setRouteMode(mode)
                    } label: {
                        if mode == session.routeMode {
                            Label(RouteMode.title(mode), systemImage: "checkmark")
                        } else {
                            Text(RouteMode.title(mode))
                        }
                    }
                }
            }
            .help("路由模式")
        }
    }
}

extension DelayGrade {
    var color: Color {
        switch self {
        case .untested: .secondary
        case .fast: .green
        case .slow: .red
        }
    }
}

// MARK: 连接

struct ConnectionsView: View {
    @Environment(CoreSession.self) private var session
    @State private var search = ""
    @State private var selection: ConnectionRow.ID?
    @State private var showInspector = false
    @AppStorage("connections.state") private var state: ConnectionState = .active
    @AppStorage("connections.sort") private var sort: ConnectionSort = .date
    @AppStorage("connections.hideDNS") private var hideDNS = false

    private var rows: [ConnectionRow] {
        ConnectionQuery.apply(session.connections, state: state, sort: sort, hideDNS: hideDNS, text: search)
    }

    var body: some View {
        Group {
            if !session.isRunning {
                NotConnectedView(title: "未连接", symbol: "arrow.left.arrow.right")
            } else if rows.isEmpty {
                if !search.isEmpty {
                    ContentUnavailableView.search(text: search)
                } else {
                    ContentUnavailableView(state == .closed ? "暂无已关闭连接" : state == .active ? "暂无活动连接" : "暂无连接",
                                           systemImage: "arrow.left.arrow.right")
                }
            } else {
                // Column titles: Clash Verge Rev connections.fields.*
                Table(rows, selection: $selection) {
                    TableColumn("主机") { row in
                        Text(row.destination).lineLimit(1).truncationMode(.middle).foregroundStyle(row.isClosed ? .secondary : .primary)
                    }
                    .width(min: 140, ideal: 240)
                    TableColumn("进程") { Text($0.process.isEmpty ? "—" : $0.process).lineLimit(1) }
                        .width(min: 60, ideal: 90)
                    TableColumn("规则") { row in
                        Text(row.rule.isEmpty ? "MATCH" : row.rule).font(.callout.monospaced()).lineLimit(1).truncationMode(.middle)
                    }
                    .width(min: 80, ideal: 180)
                    TableColumn("链路") { row in
                        Text(row.chain.isEmpty ? row.outbound : row.chain.joined(separator: " › ")).lineLimit(1)
                    }
                    .width(min: 70, ideal: 140)
                    TableColumn("下载速度") { row in
                        Text(row.isClosed ? "—" : RateFormat.bitsPerSecond(row.downlink)).monospacedDigit()
                    }
                    .width(min: 60, ideal: 80)
                    TableColumn("流量") { row in
                        Text(RateFormat.bytes(row.downlinkTotal + row.uplinkTotal)).monospacedDigit()
                    }
                    .width(min: 56, ideal: 72)
                }
                .tableStyle(.inset(alternatesRowBackgrounds: false))
                .onChange(of: selection) { _, new in if new != nil { showInspector = true } }
            }
        }
        .navigationSubtitle(session.isRunning ? "\(session.connections.filter { !$0.isClosed }.count) 个活跃" : "")
        .searchable(text: $search, placement: .toolbar, prompt: "搜索")
        .inspector(isPresented: $showInspector) {
            ConnectionInspector(row: session.connections.first { $0.id == selection })
                .inspectorColumnWidth(min: 240, ideal: 280)
        }
        .toolbar {
            ToolbarItem {
                Menu("排序", systemImage: "line.3.horizontal.decrease") {
                    Picker("状态", selection: $state) { ForEach(ConnectionState.allCases) { Text($0.title).tag($0) } }
                    Picker("排序", selection: $sort) { ForEach(ConnectionSort.allCases) { Text($0.title).tag($0) } }
                    Toggle("隐藏 DNS", isOn: $hideDNS)
                }
                .help("排序")
            }
            ToolbarItem {
                Button("关闭所有连接", systemImage: "xmark.circle") { session.closeAllConnections() }
                    .disabled(session.connections.isEmpty)
                    .help("关闭所有连接")
            }
            ToolbarItem {
                Button("检查器", systemImage: "sidebar.trailing") { showInspector.toggle() }
            }
        }
        .onAppear { session.retainConnections() }
        .onDisappear { session.releaseConnections() }
    }
}

private struct ConnectionInspector: View {
    let row: ConnectionRow?
    @Environment(CoreSession.self) private var session
    @Environment(AppModel.self) private var app

    var body: some View {
        if let row {
            Form {
                Section {
                    LabeledContent("目标地址", value: row.destination)
                    LabeledContent("进程", value: row.process.isEmpty ? "—" : row.process)
                    LabeledContent("网络", value: row.network.uppercased())
                    LabeledContent("连接时间", value: row.createdAt.formatted(date: .omitted, time: .standard))
                }
                Section {
                    LabeledContent("规则", value: row.rule.isEmpty ? "MATCH" : row.rule)
                    LabeledContent("链路", value: row.chain.isEmpty ? row.outbound : row.chain.joined(separator: " › "))
                    Button("评估连接") {
                        app.pendingExplainTarget = ExplainView.host(row.destination)
                        NotificationCenter.default.post(name: .explainRoute, object: nil)
                    }
                }
                Section {
                    LabeledContent("下载", value: RateFormat.bytes(row.downlinkTotal))
                    LabeledContent("上传", value: RateFormat.bytes(row.uplinkTotal))
                }
                Button("关闭连接", role: .destructive) { session.closeConnection(row.id) }
            }
            .formStyle(.grouped)
        } else {
            ContentUnavailableView("无数据", systemImage: "sidebar.trailing")
        }
    }
}

// MARK: 日志

struct LogsView: View {
    @Environment(CoreSession.self) private var session
    @State private var search = ""
    @State private var level: LogLevel = .info

    var body: some View {
        @Bindable var session = session
        let entries = LogQuery.filter(session.logs.elements, level: level, text: search)
        Group {
            if !session.isRunning && session.logs.isEmpty {
                NotConnectedView(title: "未连接", symbol: "doc.plaintext")
            } else if entries.isEmpty {
                if search.isEmpty { ContentUnavailableView("无日志", systemImage: "doc.plaintext") } else { ContentUnavailableView.search(text: search) }
            } else {
                ScrollViewReader { proxy in
                    List(entries) { entry in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(entry.level.title).font(.caption2.monospaced().weight(.semibold))
                                .foregroundStyle(entry.level <= .error ? .red : entry.level == .warn ? .orange : .secondary)
                                .frame(width: 44, alignment: .leading)
                            Text(entry.message).font(.callout.monospaced()).textSelection(.enabled)
                        }
                        .id(entry.id)
                        .listRowSeparator(.hidden)
                    }
                    .listStyle(.plain)
                    .environment(\.defaultMinListRowHeight, 18)
                    .onChange(of: entries.last?.id) { _, last in
                        if let last, !session.logsPaused { proxy.scrollTo(last, anchor: .bottom) }
                    }
                }
            }
        }
        .navigationSubtitle(entries.isEmpty ? "" : "\(entries.count)")
        .searchable(text: $search, placement: .toolbar, prompt: "搜索")
        .toolbar {
            ToolbarItem {
                Picker("日志级别", selection: $level) {
                    ForEach(LogLevel.allCases.filter { $0 >= .error }) { Text($0.title).tag($0) }
                }
                .help("日志级别")
            }
            ToolbarItem {
                Toggle(isOn: $session.logsPaused) {
                    Label(session.logsPaused ? "恢复" : "暂停", systemImage: session.logsPaused ? "play" : "pause")
                }
                .help(session.logsPaused ? "恢复" : "暂停")
            }
            ToolbarItem {
                Button("导出", systemImage: "square.and.arrow.up") { export(entries) }
                    .disabled(entries.isEmpty)
                    .help("导出")
            }
            ToolbarItem {
                Button("清除日志", systemImage: "trash") { session.clearLogs() }.help("清除日志")
            }
        }
        .onAppear { session.retainLogs() }
        .onDisappear { session.releaseLogs() }
    }
}

extension LogsView {
    /// Redacted with the core's own redact.Text (core/internal/redact), never a Swift copy.
    func export(_ entries: [LogEntry]) {
        let text = entries.map { "\($0.level.title) \($0.message)" }.joined(separator: "\n")
        let redacted = PxbridgeRedactText(text)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "parallux-\(Date().formatted(.iso8601.year().month().day()))-logs.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? Data(redacted.utf8).write(to: url, options: .atomic)
    }
}

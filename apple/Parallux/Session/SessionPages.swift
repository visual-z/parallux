import AppKit
import Libbox
import ParalluxKit
import SwiftUI

/// Shown on pages that read the running core while the tunnel is off.
struct NotConnectedView: View {
    let title: String
    let symbol: String
    var body: some View {
        ContentUnavailableView(title, systemImage: symbol, description: Text("连接后显示运行中内核的数据。"))
    }
}

/// Route-mode menu shared by the toolbar of several pages ("路由：规则").
struct RouteModeMenu: View {
    @Environment(CoreSession.self) private var session
    var body: some View {
        if !session.routeModes.isEmpty {
            Menu("路由：\(RouteMode.title(session.routeMode ?? ""))") {
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
                NotConnectedView(title: "连接", symbol: "arrow.left.arrow.right")
            } else {
                Table(rows, selection: $selection) {
                    TableColumn("进程") { Text($0.process.isEmpty ? "—" : $0.process) }
                        .width(min: 60, ideal: 90)
                    TableColumn("目标") { Text($0.destination).lineLimit(1) }
                        .width(min: 120, ideal: 220)
                    TableColumn("规则") { row in
                        Text(row.rule.isEmpty ? "final" : row.rule)
                            .font(.caption.monospaced()).lineLimit(1)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                    }
                    .width(min: 80, ideal: 160)
                    TableColumn("出站") { Text($0.outbound) }.width(min: 60, ideal: 100)
                    TableColumn("↓") { row in
                        Text(RateFormat.bytes(row.downlinkTotal)).monospacedDigit().foregroundStyle(row.isClosed ? .secondary : .primary)
                    }
                    .width(min: 50, ideal: 70)
                }
                .onChange(of: selection) { _, new in if new != nil { showInspector = true } }
            }
        }
        .navigationSubtitle("\(session.connections.filter { !$0.isClosed }.count) 条活跃")
        .searchable(text: $search, placement: .toolbar, prompt: "搜索")
        .inspector(isPresented: $showInspector) {
            ConnectionInspector(row: session.connections.first { $0.id == selection })
                .inspectorColumnWidth(min: 240, ideal: 280)
        }
        .toolbar {
            ToolbarItem {
                Menu("筛选", systemImage: "line.3.horizontal.decrease") {
                    Picker("状态", selection: $state) { ForEach(ConnectionState.allCases) { Text($0.title).tag($0) } }
                    Picker("排序", selection: $sort) { ForEach(ConnectionSort.allCases) { Text($0.title).tag($0) } }
                    Toggle("隐藏 DNS 连接", isOn: $hideDNS)
                }
                .help("筛选与排序")
            }
            ToolbarItem {
                Button("全部关闭", systemImage: "xmark.circle") { session.closeAllConnections() }
                    .disabled(session.connections.isEmpty)
                    .help("关闭全部连接")
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
                Section("连接") {
                    LabeledContent("目标", value: row.destination)
                    LabeledContent("进程", value: row.process.isEmpty ? "—" : row.process)
                    LabeledContent("网络", value: row.network.uppercased())
                    LabeledContent("开始", value: row.createdAt.formatted(date: .omitted, time: .standard))
                }
                Section("路由") {
                    LabeledContent("规则", value: row.rule.isEmpty ? "final" : row.rule)
                    LabeledContent("出站链", value: row.chain.isEmpty ? row.outbound : row.chain.joined(separator: " → "))
                    Button("这条为什么走这里") {
                        app.pendingExplainTarget = ExplainView.host(row.destination)
                        NotificationCenter.default.post(name: .explainRoute, object: nil)
                    }
                }
                Section("流量") {
                    LabeledContent("↓ 下行", value: RateFormat.bytes(row.downlinkTotal))
                    LabeledContent("↑ 上行", value: RateFormat.bytes(row.uplinkTotal))
                }
                Button("关闭连接", role: .destructive) { session.closeConnection(row.id) }
            }
            .formStyle(.grouped)
        } else {
            ContentUnavailableView("选择一条连接", systemImage: "sidebar.trailing")
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
                NotConnectedView(title: "日志", symbol: "doc.plaintext")
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
                    }
                    .onChange(of: entries.last?.id) { _, last in
                        if let last, !session.logsPaused { proxy.scrollTo(last, anchor: .bottom) }
                    }
                }
            }
        }
        .navigationSubtitle("\(entries.count) 行")
        .searchable(text: $search, placement: .toolbar, prompt: "搜索")
        .toolbar {
            ToolbarItem {
                Picker("级别", selection: $level) {
                    ForEach(LogLevel.allCases.filter { $0 >= .error }) { Text($0.title).tag($0) }
                }
                .help("显示不低于此级别的日志")
            }
            ToolbarItem {
                Toggle(isOn: $session.logsPaused) {
                    Label(session.logsPaused ? "继续" : "暂停", systemImage: session.logsPaused ? "play" : "pause")
                }
                .help(session.logsPaused ? "继续" : "暂停")
            }
            ToolbarItem {
                Button("导出", systemImage: "square.and.arrow.up") { export(entries) }
                    .disabled(entries.isEmpty)
                    .help("导出当前显示的日志，订阅地址里的 token 与密码会被脱敏")
            }
            ToolbarItem {
                Button("清空", systemImage: "trash") { session.clearLogs() }.help("清空日志")
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

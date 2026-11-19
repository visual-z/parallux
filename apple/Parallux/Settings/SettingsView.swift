import Libbox
import ParalluxKit
import SwiftUI

/// The Settings window (⌘,): one tab per SettingsTab (design v0.2). Labels
/// follow SFM's zh-Hans strings (docs/design/copy-and-style.md). Width is
/// fixed like System Settings panes; height follows each tab's content up to
/// a cap, so short tabs do not leave an empty lower half.
struct SettingsView: View {
    /// Why 560: the narrowest width that keeps every LabeledContent on one
    /// line. Height cap 620 fits a 13" display with menu bar and Dock.
    static let width: CGFloat = 560

    var body: some View {
        TabView {
            ForEach(SettingsTab.allCases) { tab in
                Tab(tab.title, systemImage: tab.symbol) {
                    content(for: tab)
                        .frame(width: Self.width)
                        .frame(minHeight: 200, idealHeight: 420, maxHeight: 620)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder private func content(for tab: SettingsTab) -> some View {
        switch tab {
        case .general: GeneralSettings()
        case .aggregation: AggregationSettings()
        case .tunnel: TunnelSettingsView()
        case .onDemand: OnDemandSettings()
        case .core: CoreSettings()
        case .remoteControl: RemoteControlSettings()
        case .about: AboutSection()
        }
    }
}

private struct GeneralSettings: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        @Bindable var settings = app.settings
        Form {
            Section {
                Toggle("登录时启动", isOn: $settings.launchAtLogin)
                if let error = settings.loginItemError { Text(error).font(.caption).foregroundStyle(.red) }
                Toggle(isOn: $settings.value.keepInMenuBarAfterClose) {
                    Text("关闭窗口后保留在菜单栏")
                    Text("主窗口关闭时，Parallux 继续在后台运行")
                }
                Toggle("菜单栏显示实时速率", isOn: $settings.value.showRateInMenuBar)
            }
            UpdateSection()
        }
        .formStyle(.grouped)
    }
}

private struct AggregationSettings: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        @Bindable var settings = app.settings
        Form {
            Section {
                Picker("默认聚合方式", selection: Binding(get: { app.linkSettings.value.mode }, set: { mode in Task { await app.setMode(mode) } })) {
                    ForEach(AggregationMode.allCases) { Text($0.title).tag($0) }
                }
                Toggle("线路掉线时通知", isOn: $settings.value.notifyLinkChanges)
            }
        }
        .formStyle(.grouped)
    }
}

private struct TunnelSettingsView: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        @Bindable var settings = app.settings
        // Design v0.2: a name for each NEVPNProtocol switch with the property
        // underneath, in the design's order. The three profile overrides below
        // keep SFM's names (ProfileOverrideView.swift): the design draws only
        // one of them and they are distinct behaviours.
        Form {
            Section("数据包隧道") {
                property("包含所有网络", "includeAllNetworks", $settings.value.tunnel.includeAllNetworks)
                property("排除本地网络", "excludeLocalNetworks", $settings.value.tunnel.excludeLocalNetworks)
                property("排除 APNs 路由", "excludeAPNs", $settings.value.tunnel.excludeAPNs)
                property("排除设备间通信", "excludeDeviceCommunication", $settings.value.tunnel.excludeDeviceCommunication)
                property("强制路由", "enforceRoutes", $settings.value.tunnel.enforceRoutes)
            }
            Section("配置覆盖") {
                Toggle("隐藏 VPN 图标", isOn: $settings.value.tunnel.excludeDefaultRoute)
                Toggle("不使用默认路由", isOn: $settings.value.tunnel.autoRouteUseSubRangesByDefault)
                Toggle("系统 HTTP 代理", isOn: $settings.value.tunnel.systemProxyEnabled)
            }
        }
        .formStyle(.grouped)
    }
}

private extension TunnelSettingsView {
    func property(_ title: String, _ name: String, _ isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
            Text(verbatim: name)
        }
    }
}

private struct OnDemandSettings: View {
    @Environment(AppModel.self) private var app
    @State private var adding = false

    var body: some View {
        @Bindable var settings = app.settings
        Form {
            Section {
                Toggle(isOn: $settings.value.onDemandEnabled) {
                    Text("启用按需连接")
                    Text(settings.value.onDemandRules.isEmpty ? "没有规则时，任何网络下都会连接" : "根据规则自动连接或断开")
                }
            }
            Section("规则") {
                ForEach(settings.value.onDemandRules) { rule in
                    HStack {
                        Text(rule.summary)
                        Spacer()
                        Button("删除", systemImage: "minus.circle") {
                            settings.value.onDemandRules.removeAll { $0.id == rule.id }
                        }
                        .labelStyle(.iconOnly).buttonStyle(.borderless)
                    }
                }
                .onMove { settings.value.onDemandRules.move(fromOffsets: $0, toOffset: $1) }
                Button("添加规则…") { adding = true }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $adding) { AddOnDemandRule { settings.value.onDemandRules.append($0) } }
    }
}

private struct AddOnDemandRule: View {
    let add: (OnDemandRuleModel) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var kind = 0
    @State private var text = ""
    @State private var action = OnDemandRuleModel.Action.connect

    private var rule: OnDemandRuleModel {
        let match: OnDemandRuleModel.Match = kind == 0 ? .anyNetwork : kind == 1 ? .wifi(ssid: text) : .probe(url: text)
        return OnDemandRuleModel(match: match, action: action)
    }

    var body: some View {
        Form {
            Picker("接口类型", selection: $kind) {
                Text("任意网络").tag(0)
                Text("SSID").tag(1)
                Text("探测 URL").tag(2)
            }
            if kind == 1 { TextField("SSID", text: $text) }
            if kind == 2 {
                TextField("探测 URL", text: $text, prompt: Text("http://intranet.local"))
                Text("仅当请求此 URL 返回 HTTP 200 时匹配。").font(.caption).foregroundStyle(.secondary)
            }
            Picker("动作", selection: $action) {
                Text("连接").tag(OnDemandRuleModel.Action.connect)
                Text("断开连接").tag(OnDemandRuleModel.Action.disconnect)
            }
            if let problem = rule.problem, !text.isEmpty || kind == 0 {
                Text(problem).font(.caption).foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("完成") { add(rule); dismiss() }.disabled(rule.problem != nil)
            }
        }
    }
}

private struct CoreSettings: View {
    @Environment(AppModel.self) private var app
    @State private var installed: String?
    @State private var busy = false

    var body: some View {
        Form {
            SetupSection()
            Section("系统扩展") {
                LabeledContent("状态", value: installed.map { "已安装 · 版本 \($0)" } ?? "未安装")
                HStack {
                    Button(installed == nil ? "安装系统扩展" : "重新安装") { Task { busy = true; await app.tunnel.install(); await refresh(); busy = false } }
                    if installed != nil {
                        Button("卸载", role: .destructive) { Task { busy = true; await app.tunnel.uninstall(); await refresh(); busy = false } }
                    }
                }
                .disabled(busy)
            }
            Section("内核") {
                LabeledContent("内核版本", value: PxbridgeVersion())
            }
            HelperSettingsSection()
            MemoryLimitSection()
        }
        .formStyle(.grouped)
        .task { await refresh() }
    }

    private func refresh() async {
        installed = await app.tunnel.installedExtensionVersion()
    }
}

/// SFM #105: the extension's memory limit (takes effect on the next connection).
private struct MemoryLimitSection: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        @Bindable var settings = app.settings
        Section {
            Toggle("启用内存限制", isOn: Binding(
                get: { settings.value.memoryLimitMB > 0 },
                set: { settings.value.memoryLimitMB = $0 ? 512 : 0 }
            ))
            if settings.value.memoryLimitMB > 0 {
                Stepper("内存限制 \(settings.value.memoryLimitMB) MB", value: $settings.value.memoryLimitMB, in: 128...4096, step: 128)
            }
        }
    }
}

import Libbox
import ParalluxKit
import SwiftUI

/// The Settings window (⌘,): one tab per SettingsTab (design v0.2). Every
/// control here takes effect; features of later milestones say so instead of
/// showing inert switches.
struct SettingsView: View {
    var body: some View {
        TabView {
            ForEach(SettingsTab.allCases) { tab in
                Tab(tab.title, systemImage: tab.symbol) {
                    content(for: tab)
                }
            }
        }
        .frame(width: 600, height: 480)
    }

    @ViewBuilder private func content(for tab: SettingsTab) -> some View {
        switch tab {
        case .general: GeneralSettings()
        case .aggregation: AggregationSettings()
        case .tunnel: TunnelSettingsView()
        case .onDemand: OnDemandSettings()
        case .core: CoreSettings()
        case .remoteControl:
            ContentUnavailableView("远程控制", systemImage: tab.symbol,
                                   description: Text("查看并控制另一台设备上运行的内核（与 SFM 相同），在 M5 提供。"))
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
            Section {
                Text("语言跟随系统；自动更新在 M6 提供。").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct AggregationSettings: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        @Bindable var settings = app.settings
        Form {
            Picker("聚合方式", selection: Binding(get: { app.linkSettings.value.mode }, set: { mode in Task { await app.setMode(mode) } })) {
                ForEach(AggregationMode.allCases) { Text($0.title).tag($0) }
            }
            Toggle(isOn: $settings.value.notifyLinkChanges) {
                Text("线路掉线时通知")
                Text("线路变为不可用或恢复时发通知")
            }
            Text("线路的启用、排序与「仅备用」在主窗口「线路」页设置；叠加的聚合服务器在「聚合服务器」页。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

private struct TunnelSettingsView: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        @Bindable var settings = app.settings
        Form {
            Section("数据包隧道（与 SFM 相同）") {
                Toggle("包含所有网络", isOn: $settings.value.tunnel.includeAllNetworks).help("includeAllNetworks")
                Toggle("排除本地网络", isOn: $settings.value.tunnel.excludeLocalNetworks).help("excludeLocalNetworks")
                Toggle("排除 APNs 路由", isOn: $settings.value.tunnel.excludeAPNs).help("excludeAPNs")
                Toggle("排除设备间通信", isOn: $settings.value.tunnel.excludeDeviceCommunication).help("excludeDeviceCommunication")
                Toggle("强制路由", isOn: $settings.value.tunnel.enforceRoutes).help("enforceRoutes")
            }
            Section("配置覆盖") {
                Toggle(isOn: $settings.value.tunnel.excludeDefaultRoute) {
                    Text("不添加默认路由")
                    Text("只接管配置里明确列出的地址")
                }
                Toggle("自动路由默认使用子网段", isOn: $settings.value.tunnel.autoRouteUseSubRangesByDefault)
                Toggle("系统 HTTP 代理", isOn: $settings.value.tunnel.systemProxyEnabled)
            }
            Text("改动在下次连接时生效。").font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
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
                    Text("没有规则时不启用；规则按顺序匹配")
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
            Text("改动在下次连接时生效。").font(.caption).foregroundStyle(.secondary)
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
            Picker("条件", selection: $kind) {
                Text("任何网络").tag(0)
                Text("Wi‑Fi 名称").tag(1)
                Text("探测地址").tag(2)
            }
            if kind == 1 { TextField("Wi‑Fi 名称", text: $text) }
            if kind == 2 { TextField("探测地址", text: $text, prompt: Text("http://intranet.local")) }
            Picker("动作", selection: $action) {
                Text("连接").tag(OnDemandRuleModel.Action.connect)
                Text("断开").tag(OnDemandRuleModel.Action.disconnect)
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
                Button("添加") { add(rule); dismiss() }.disabled(rule.problem != nil)
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
            Section("系统扩展") {
                LabeledContent("状态", value: installed.map { "已安装 · 版本 \($0)" } ?? "未安装")
                HStack {
                    Button("重新安装") { Task { busy = true; await app.tunnel.install(); await refresh(); busy = false } }
                    Button("卸载", role: .destructive) { Task { busy = true; await app.tunnel.uninstall(); await refresh(); busy = false } }
                }
                .disabled(busy)
            }
            Section("内核") {
                LabeledContent("内核版本", value: PxbridgeVersion())
                LabeledContent("App Group", value: AppGroup.identifier() ?? "未签名构建，没有 App Group")
            }
            HelperSettingsSection()
        }
        .formStyle(.grouped)
        .task { await refresh() }
    }

    private func refresh() async {
        installed = await app.tunnel.installedExtensionVersion()
    }
}

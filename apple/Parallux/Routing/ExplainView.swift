import ParalluxKit
import SwiftUI

/// 试一下: which rule a target matches, which group, which node, which link.
/// The rule step comes from the core itself (pxbridge.ExplainRoute over XPC).
struct ExplainView: View {
    let model: RoutingModel
    @Binding var target: String
    let reroute: (TrafficClass) -> Void
    @Environment(AppModel.self) private var app
    @State private var result: RouteExplanation?
    @State private var running = false

    private var recentTargets: [String] {
        var seen: [String] = []
        for row in app.session.connections where !seen.contains(Self.host(row.destination)) {
            seen.append(Self.host(row.destination))
            if seen.count == 6 { break }
        }
        return seen
    }

    static func host(_ destination: String) -> String {
        if let colon = destination.lastIndex(of: ":"), !destination.hasSuffix("]") { return String(destination[..<colon]) }
        return destination
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    TextField("域名、IP 或 主机:端口", text: $target)
                        .textFieldStyle(.roundedBorder).font(.body.monospaced())
                        .onSubmit(run)
                    Button("查看路由", action: run).buttonStyle(.borderedProminent).disabled(target.trimmingCharacters(in: .whitespaces).isEmpty || running)
                }
                if !recentTargets.isEmpty {
                    HStack(spacing: 6) {
                        Text("最近连接").font(.caption).foregroundStyle(.secondary)
                        ForEach(recentTargets, id: \.self) { host in
                            Button(host) { target = host; run() }.controlSize(.small)
                        }
                    }
                }
                if running { ProgressView() }
                if let result { Steps(result: result, model: model, reroute: reroute) }
                Text("不发起连接，只让内核按当前配置匹配一遍。依赖嗅探的规则（如按协议）按端口推断：443 视为 TLS，80 视为 HTTP。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // A target set from outside (connections inspector) or typed: explain it
        // once typing pauses. Why 400 ms: one XPC round trip per pause, not per key.
        .task(id: target) {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, result?.target != target, !target.isEmpty, app.session.isRunning else { return }
            run()
        }
    }

    private func run() {
        let value = target.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return }
        running = true
        Task.detached {
            let explanation = CommandXPCDialer.explainRoute(value)
            await MainActor.run {
                result = explanation ?? RouteExplanation(target: value, ruleIndex: -1, error: "网络扩展没有应答")
                running = false
            }
        }
    }
}

private struct Steps: View {
    let result: RouteExplanation
    let model: RoutingModel
    let reroute: (TrafficClass) -> Void
    @Environment(AppModel.self) private var app

    var body: some View {
        if let error = result.error {
            Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
        } else {
            let profile = model.effectiveProfile(app: app)
            let rule = result.ruleIndex >= 0 && result.ruleIndex < profile.rules.count ? profile.rules[result.ruleIndex] : nil
            let map = model.map(app: app)
            let item = map.classes.first { $0.ruleIndex == (result.final == true ? nil : result.ruleIndex) }
            let chain = result.outbound.map { model.chain($0, app: app) }
            VStack(alignment: .leading, spacing: 0) {
                Step(number: 1, title: "规则",
                     value: result.final == true ? "没有规则命中 · route.final" : "第 \(result.ruleIndex + 1) 条 · \(rule.map(TrafficLabel.name) ?? "")",
                     why: result.final == true ? "逐条检查了 \(result.skipped ?? 0) 条规则都不匹配" : "\(result.rule ?? "")\((result.skipped ?? 0) > 0 ? "；前面 \(result.skipped ?? 0) 条不匹配或只附加选项" : "")")
                if let outbound = result.outbound, let chain {
                    let group = app.session.groups.first { $0.tag == outbound }
                    Step(number: 2, title: "出口", value: outbound,
                         why: group.map { $0.type == "urltest" ? "自动选择延迟最低的成员" : "手动选择" } ?? "非分组出站")
                    if chain.hops.count > 1 {
                        Step(number: 3, title: "节点", value: chain.hops.joined(separator: " › "),
                             why: "沿每个分组当前选中的成员展开")
                    }
                    Step(number: chain.hops.count > 1 ? 4 : 3, title: "线路", value: lineText(outbound), why: lineWhy(outbound), last: true)
                } else {
                    Step(number: 2, title: "动作", value: actionTitle(result.action), why: "这类流量不经任何出口", last: true)
                }
                if let item, result.outbound != nil {
                    HStack {
                        Button("改走…") { reroute(item) }
                        if item.connections > 0 { Text("这类流量现在有 \(item.connections) 条连接").font(.caption).foregroundStyle(.secondary) }
                    }
                    .padding(.top, 8)
                }
            }
            .padding(16)
            .background(.background, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.08)))
        }
    }

    private func lineText(_ outbound: String) -> String {
        guard app.enabledLinks.count >= 2, let mode = app.effectiveMode else { return app.links.links.first.map { $0.kind.title } ?? "默认网口" }
        let bonded = mode == .bond && !outbound.hasPrefix("direct")
        return "\(bonded ? "叠加" : outbound.hasPrefix("direct") && mode == .bond ? "主备" : mode.title) · \(app.enabledLinks.prefix(bonded ? 2 : 9).map(\.kind.title).joined(separator: " + "))"
    }

    private func lineWhy(_ outbound: String) -> String {
        guard app.enabledLinks.count >= 2 else { return "只有一条线路" }
        if app.effectiveMode == .bond && !outbound.hasPrefix("direct") { return "经聚合服务器重组后到节点" }
        if outbound.hasPrefix("direct") && app.linkSettings.value.mode == .bond { return "直连不经聚合服务器" }
        return "按连接在线路之间分配"
    }

    private func actionTitle(_ action: String?) -> String {
        switch action {
        case "reject": "拒绝"
        case "hijack-dns": "交给内置 DNS"
        case "bypass": "绕过"
        default: action ?? "—"
        }
    }
}

private struct Step: View {
    let number: Int
    let title: String
    let value: String
    let why: String
    var last = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 0) {
                Text("\(number)").font(.caption.weight(.bold)).foregroundStyle(.tint)
                    .frame(width: 22, height: 22).background(.tint.opacity(0.14), in: Circle())
                if !last { Rectangle().fill(.quaternary).frame(width: 2).frame(maxHeight: .infinity) }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.callout).textSelection(.enabled)
                if !why.isEmpty { Text(why).font(.caption).foregroundStyle(.tertiary).textSelection(.enabled) }
            }
            .padding(.bottom, last ? 0 : 14)
        }
    }
}

/// 改走: send one traffic class to another exit, or rename it. Stored as an
/// override for the selected profile; takes effect when the core reloads.
struct RerouteSheet: View {
    let model: RoutingModel
    let item: TrafficClass
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var target = ""
    @State private var name = ""

    var body: some View {
        let profile = model.profile
        let rule = item.ruleIndex.flatMap { $0 < profile.rules.count ? profile.rules[$0] : nil }
        Form {
            Section {
                LabeledContent("流量", value: item.condition)
                LabeledContent("现在走", value: item.exit)
            }
            if let rule {
                Section {
                    Picker("改走", selection: $target) {
                        Text("配置里的原出站（\(rule.outbound ?? "")）").tag("")
                        ForEach(model.rerouteTargets(groups: app.session.groups).filter { $0 != rule.outbound }, id: \.self) { Text($0).tag($0) }
                    }
                    TextField("名称", text: $name, prompt: Text(TrafficLabel.name(for: rule)))
                } footer: {
                    Text("改动存在 Parallux 里，配置文件不变，订阅更新也不会冲掉；如果这条规则被订阅改掉，覆盖会自动失效。连接中会立即重载内核，正在进行的连接会断开重连。")
                }
            } else {
                Text("「其余流量」由配置的 route.final 决定，暂不支持改走。").foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("应用") {
                    guard let rule, let profileID = app.profiles.store.selectedID else { dismiss(); return }
                    var overrides = app.routeOverrides.overrides(for: profileID)
                    overrides.set(rule: rule, outbound: target.isEmpty ? nil : target, name: name.isEmpty ? nil : name)
                    app.routeOverrides.set(overrides, for: profileID)
                    Task { await app.applyLinkChanges() }
                    dismiss()
                }
                .disabled(rule == nil || app.profiles.store.selectedID == nil)
            }
        }
        .onAppear {
            guard let rule, let profileID = app.profiles.store.selectedID else { return }
            let existing = app.routeOverrides.overrides(for: profileID).items.first { $0.ruleIndex == rule.index }
            target = existing?.outbound ?? ""
            name = existing?.name ?? ""
        }
    }
}

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
                    TextField("主机", text: $target, prompt: Text("example.com"))
                        .textFieldStyle(.roundedBorder).font(.body.monospaced())
                        .onSubmit(run)
                    Button("评估连接", action: run).buttonStyle(.borderedProminent).disabled(target.trimmingCharacters(in: .whitespaces).isEmpty || running)
                }
                if !recentTargets.isEmpty {
                    HStack(spacing: 6) {
                        Text("连接").font(.caption).foregroundStyle(.secondary)
                        ForEach(recentTargets, id: \.self) { host in
                            Button(host) { target = host; run() }.controlSize(.small)
                        }
                    }
                }
                if running { ProgressView() }
                if let result { Steps(result: result, model: model, reroute: reroute) }

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
                result = explanation ?? RouteExplanation(target: value, ruleIndex: -1, error: "内核暂不可用")
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
                     value: result.final == true ? TrafficLabel.finalName : "#\(result.ruleIndex + 1) · \(rule.map(TrafficLabel.name) ?? "")",
                     why: result.final == true ? "匹配所有请求 (MATCH)" : (result.rule ?? ""))
                if let outbound = result.outbound, let chain {
                    let group = app.session.groups.first { $0.tag == outbound }
                    Step(number: 2, title: "代理策略", value: outbound,
                         why: group.map { $0.type == "urltest" ? "根据 URL 测试延迟选择代理" : "手动选择代理" } ?? "")
                    if chain.hops.count > 1 {
                        Step(number: 3, title: "链路", value: chain.hops.joined(separator: " › "),
                             why: "")
                    }
                    Step(number: chain.hops.count > 1 ? 4 : 3, title: "线路", value: lineText(outbound), why: lineWhy(outbound), last: true)
                } else {
                    Step(number: 2, title: "代理策略", value: actionTitle(result.action), why: "", last: true)
                }
                if let item, result.outbound != nil {
                    HStack {
                        Button("编辑规则…") { reroute(item) }
                        if item.connections > 0 { Text("\(item.connections) 个活跃连接").font(.caption).foregroundStyle(.secondary) }
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
        guard app.activeLinks.count >= 2, let mode = app.effectiveMode else { return app.links.links.first.map { $0.kind.title } ?? "—" }
        // Direct traffic is bonded too (feat-bond-direct); the explainer has
        // no IP for a name target, so it does not try to call it LAN here.
        let bonded = mode == .bond
        return "\(mode.title) · \(app.activeLinks.prefix(bonded ? 2 : 9).map(\.kind.title).joined(separator: " + "))"
    }

    private func lineWhy(_ outbound: String) -> String {
        guard app.activeLinks.count >= 2 else { return "" }
        if app.effectiveMode == .bond { return app.bondServerSummary ?? "" }
        return ""
    }

    private func actionTitle(_ action: String?) -> String {
        switch action {
        case "reject": "拦截请求 (REJECT)"
        case "hijack-dns": "DNS"
        case "bypass": "直接连接 (DIRECT)"
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
                    Picker("代理策略", selection: $target) {
                        Text("默认（\(rule.outbound ?? "")）").tag("")
                        ForEach(model.rerouteTargets(groups: app.session.groups).filter { $0 != rule.outbound }, id: \.self) { Text($0).tag($0) }
                    }
                    TextField("名称", text: $name, prompt: Text(TrafficLabel.name(for: rule)))
                } footer: {
                    Text("覆写保存在本机，不修改配置文件")
                }
            } else {
                Text("匹配所有请求 (MATCH)").foregroundStyle(.secondary)
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

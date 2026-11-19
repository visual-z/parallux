import AppKit
import Libbox
import ParalluxKit
import SwiftUI

/// Diagnostics page. User tools first (design v0.2 单线程下载测速; SFM 网络质量,
/// STUN 测试); the per-link bind probe (research-sysext-bind-interface,
/// feat-probe-arms) sits in a collapsed 「接口」 group below. Copy follows
/// docs/design/copy-and-style.md.
///
/// - App 内：the same LinkProbe in the app process. Run it with the tunnel
///   off; that is the control showing each link works at all.
/// - 扩展内：raw IP_BOUND_IF inside the system extension, tunnel up.
/// - sing-box：a throwaway profile with one `direct` + `bind_interface`
///   outbound per link, URL-tested by the core (Decision 13's real path).
struct DiagnosticsView: View {
    @Environment(AppModel.self) private var app
    @State private var local: Arm<[LinkProbeResult]> = .idle
    @State private var tunnel: Arm<[LinkProbeResult]> = .idle
    @State private var probeProfileError: String?
    @State private var usingProbeProfile = false
    @State private var speed = SpeedTestRunner()
    @State private var tools = NetworkToolsRunner()
    @State private var toolOutbound = ""
    @State private var showProbe = false

    enum Arm<Value> {
        case idle, running, done(Value, tunnelWasOn: Bool), failed(String)
    }

    var body: some View {
        Form {
            speedSection
            toolsSection
            EndpointsSection()
            Section {
                DisclosureGroup("接口", isExpanded: $showProbe) {
                    LabeledContent("本机") {
                        Button("开始测试", action: runLocal).disabled(isRunning(local))
                    }
                    results(local)
                    LabeledContent("系统扩展") {
                        Button("开始测试", action: runTunnel).disabled(!app.tunnel.isConnected || isRunning(tunnel))
                    }
                    results(tunnel)
                    LabeledContent("出站") {
                        HStack {
                            Button(usingProbeProfile ? "已连接" : "连接", action: connectProbeProfile).disabled(app.tunnel.isBusy)
                            Button("延迟测试") { app.session.urlTest(group: LinkProbeProfile.groupTag) }
                                .disabled(probeGroup == nil || app.session.testing.contains(LinkProbeProfile.groupTag))
                        }
                    }
                    if let probeProfileError { Text(probeProfileError).foregroundStyle(.red).font(.caption) }
                    if let group = probeGroup {
                        ForEach(group.items) { item in
                            let grade = DelayGrade(milliseconds: item.delay)
                            LabeledContent(item.tag) {
                                Text(grade == .untested ? "超时" : "\(item.delay) ms").foregroundStyle(grade.color).monospacedDigit()
                            }
                        }
                    }
                    Button("复制", action: copyAll)
                }
            }
        }
        .formStyle(.grouped)
    }

    /// 单线程下载测速 (design v0.2): each link alone, then all links bonded,
    /// one bar per path as long as its share of the fastest.
    @ViewBuilder private var speedSection: some View {
        Section {
            let fractions = SpeedTest.fractions(speed.results)
            ForEach(Array(speed.results.enumerated()), id: \.offset) { index, result in
                DesignMeterRow(label: result.label, fraction: index < fractions.count ? fractions[index] : 0, color: barColor(index, result),
                               value: result.rate.map { RateFormat.bitsPerSecond($0) } ?? "失败")
            }
            if let summary = SpeedTest.summary(speed.results) {
                Text(summary).font(.callout.weight(.medium))
            }
            if speed.results.isEmpty, !speed.isRunning {
                Text("尚未测试").foregroundStyle(.secondary)
            }
        } header: {
            HStack(spacing: 8) {
                Text("单线程下载测速")
                Spacer()
                if let current = speed.current {
                    ProgressView().controlSize(.small)
                    Text(current).font(.caption).foregroundStyle(.secondary)
                }
                Button(speed.isRunning ? "检查中..." : "开始测试", systemImage: "bolt") { speed.run(paths: speedPaths) }
                    .designPill(primary: true)
                    .disabled(speed.isRunning || !app.tunnel.isConnected || app.activeLinks.count < 2)
            }
        } footer: {
            // Design v0.2, diagnostics page.
            Text("测速依次只用一条线路，再用全部线路叠加，看叠加到底多出多少。").font(.caption).foregroundStyle(.secondary)
        }
    }

    /// A link's bar in the link's colour; the bonded path in the accent colour.
    private func barColor(_ index: Int, _ result: SpeedTest.Result) -> Color {
        let links = app.activeLinks
        guard !result.isBond, index < links.count else { return .accentColor }
        return LinkColors.color(for: links[index], in: app.links.links)
    }

    /// SFM #97/#98, through any outbound of the running core.
    @ViewBuilder private var toolsSection: some View {
        Section("网络质量") {
            Picker("出站", selection: $toolOutbound) {
                Text("默认").tag("")
                ForEach(toolOutbounds, id: \.self) { Text($0).tag($0) }
            }
            HStack {
                if tools.running != nil { ProgressView().controlSize(.small); Text("检查中...").font(.caption) }
                Spacer()
                Button("网络质量") { tools.runQuality(outbound: toolOutbound) }
                Button("STUN 测试") { tools.runSTUN(outbound: toolOutbound) }
            }
            .disabled(!app.tunnel.isConnected || tools.running != nil)
            if let error = tools.error { Text(error).font(.caption).foregroundStyle(.red) }
            if let q = tools.quality {
                LabeledContent("下载", value: RateFormat.bitsPerSecond(q.download / 8))
                LabeledContent("上传", value: RateFormat.bitsPerSecond(q.upload / 8))
                LabeledContent("下载 RPM", value: "\(q.downloadRPM)")
                LabeledContent("上传 RPM", value: "\(q.uploadRPM)")
                LabeledContent("延迟", value: "\(q.idleLatencyMs) ms")
            }
            if let s = tools.stun {
                LabeledContent("外部地址", value: s.externalAddress)
                LabeledContent("延迟", value: "\(s.latencyMs) ms")
                LabeledContent("NAT 类型检测", value: "\(s.mapping) / \(s.filtering)")
            }
        }
    }

    private var toolOutbounds: [String] {
        var tags = app.activeLinks.map { ProfileComposer.linkTag($0.name) }
        if app.effectiveMode == .bond { tags.append(AggregationServer.bondTag) }
        for group in app.session.groups { tags.append(group.tag) }
        return tags
    }

    private var speedPaths: [(label: String, outbound: String, isBond: Bool)] {
        var paths = app.activeLinks.map { (label: "\($0.kind.title)（\($0.name)）", outbound: ProfileComposer.linkTag($0.name), isBond: false) }
        if app.effectiveMode == .bond {
            paths.append((label: "叠加", outbound: AggregationServer.bondTag, isBond: true))
        }
        return paths
    }

    private var probeGroup: OutboundGroupModel? {
        app.session.groups.first { $0.tag == LinkProbeProfile.groupTag }
    }

    private func isRunning<T>(_ arm: Arm<T>) -> Bool {
        if case .running = arm { return true }
        return false
    }

    @ViewBuilder private func results(_ arm: Arm<[LinkProbeResult]>) -> some View {
        switch arm {
        case .idle:
            EmptyView()
        case .running:
            ProgressView().controlSize(.small)
        case let .failed(message):
            Text(message).foregroundStyle(.red).font(.caption)
        case let .done(rows, tunnelWasOn):
            ForEach(rows, id: \.interface) { row in
                HStack {
                    Text("\(row.interface) #\(row.index)").monospaced()
                    Spacer()
                    Text(row.connected ? "已连接" : "错误").foregroundStyle(row.connected ? .green : .red)
                    Text(row.errno.map { "errno \($0) (\(row.failedCall ?? ""))" } ?? "").monospaced().foregroundStyle(.secondary)
                    Text("\(row.millis) ms").monospacedDigit().foregroundStyle(.secondary)
                    Text(row.egressIP ?? "—").monospaced().textSelection(.enabled)
                }
                .font(.callout)
            }
        }
    }

    private func runLocal() {
        local = .running
        let tunnelOn = app.tunnel.isConnected
        Task.detached {
            let rows = TunnelXPC.runProbes()
            await MainActor.run { local = .done(rows, tunnelWasOn: tunnelOn) }
        }
    }

    private func runTunnel() {
        tunnel = .running
        Task.detached {
            let outcome = Result { try CommandXPCDialer.probeLinks() }
            await MainActor.run {
                switch outcome {
                case let .success(rows): tunnel = .done(rows, tunnelWasOn: true)
                case let .failure(error): tunnel = .failed(error.localizedDescription)
                }
            }
        }
    }

    private func connectProbeProfile() {
        probeProfileError = nil
        guard let content = LinkProbeProfile.make(interfaces: LinkProbe.candidateInterfaces()) else {
            probeProfileError = "不可用"
            return
        }
        var error: NSError?
        LibboxCheckConfig(content, &error)
        if let error {
            probeProfileError = "错误：\(error.localizedDescription)"
            return
        }
        Task {
            await app.connect(overrideContent: content)
            usingProbeProfile = true
        }
    }

    private func copyAll() {
        var text = "Parallux 线路探针 \(Date().formatted(.iso8601))\n"
        func dump(_ name: String, _ arm: Arm<[LinkProbeResult]>) {
            text += "\n[\(name)]\n"
            if case let .done(rows, on) = arm {
                text += "tunnel=\(on ? "on" : "off")\n"
                for row in rows {
                    text += "\(row.interface)#\(row.index) connected=\(row.connected) errno=\(row.errno.map(String.init) ?? "-") call=\(row.failedCall ?? "-") ms=\(row.millis) egress=\(row.egressIP ?? "-")\n"
                }
            } else if case let .failed(message) = arm {
                text += "failed: \(message)\n"
            } else {
                text += "not run\n"
            }
        }
        dump("app", local)
        dump("extension", tunnel)
        text += "\n[sing-box]\n"
        for item in probeGroup?.items ?? [] { text += "\(item.tag) delay=\(item.delay)\n" }
        if probeGroup == nil { text += "not run\n" }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

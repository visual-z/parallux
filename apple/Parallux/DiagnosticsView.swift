import AppKit
import Libbox
import ParalluxKit
import SwiftUI

/// Diagnostics page: the per-link bind probe in three arms
/// (research-sysext-bind-interface, feat-probe-arms). Speed tests and
/// DNS/MTU checks come with M3.
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

    enum Arm<Value> {
        case idle, running, done(Value, tunnelWasOn: Bool), failed(String)
    }

    var body: some View {
        Form {
            speedSection
            Section {
                Text("三组结果一起看：App 内检测在隧道关着时跑，作为对照；扩展内与 sing-box 两组在隧道开着时跑。拷贝全部结果贴回研究卡。")
                    .font(.callout).foregroundStyle(.secondary)
                Button("拷贝全部结果", action: copyAll)
            }
            Section("1 · App 内（对照）") {
                HStack {
                    Text("候选网口：\(LinkProbe.candidateInterfaces().joined(separator: "、"))").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("App 内检测", action: runLocal).disabled(isRunning(local))
                }
                if app.tunnel.isConnected {
                    Label("隧道开着：App 自己的连接也走隧道，这一组不再是对照。", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
                results(local)
            }
            Section("2 · 扩展内原始绑定") {
                HStack {
                    Spacer()
                    Button("扩展内检测", action: runTunnel).disabled(!app.tunnel.isConnected || isRunning(tunnel))
                }
                results(tunnel)
            }
            Section("3 · sing-box direct + bind_interface") {
                HStack {
                    Text(usingProbeProfile ? "正在使用探测配置" : "会断开当前连接，换成探测配置重连")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("探测配置连接", action: connectProbeProfile).disabled(app.tunnel.isBusy)
                    Button("测速") { app.session.urlTest(group: LinkProbeProfile.groupTag) }
                        .disabled(probeGroup == nil || app.session.testing.contains(LinkProbeProfile.groupTag))
                }
                if let probeProfileError { Text(probeProfileError).foregroundStyle(.red).font(.caption) }
                if let group = probeGroup {
                    ForEach(group.items) { item in
                        let grade = DelayGrade(milliseconds: item.delay)
                        LabeledContent(item.tag) {
                            Text(grade == .untested ? "未测或失败" : "\(item.delay) ms").foregroundStyle(grade.color).monospacedDigit()
                        }
                    }
                    Text("失败原因见「日志」页（探测配置的日志级别为 debug）。").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    /// 单线程下载测速 (design): each link alone, then all links bonded.
    @ViewBuilder private var speedSection: some View {
        Section("单线程下载测速") {
            Text("测速依次只用一条线路，再用叠加，看叠加到底多出多少。每条路径一个连接、\(SpeedTestRunner.secondsPerPath) 秒。需要隧道已连接且启用两条以上线路；叠加一项需要聚合服务器。")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                if let current = speed.current { ProgressView().controlSize(.small); Text("正在测 \(current)…").font(.caption) }
                Spacer()
                Button("开始测试") { speed.run(paths: speedPaths) }
                    .disabled(speed.isRunning || !app.tunnel.isConnected || app.enabledLinks.count < 2)
            }
            ForEach(Array(speed.results.enumerated()), id: \.offset) { _, result in
                LabeledContent(result.label) {
                    Text(result.rate.map { RateFormat.bitsPerSecond($0) } ?? "失败").monospacedDigit()
                        .foregroundStyle(result.rate == nil ? .red : .primary)
                }
            }
            if let summary = SpeedTest.summary(speed.results) {
                Text(summary).font(.callout.weight(.medium))
            }
        }
    }

    private var speedPaths: [(label: String, outbound: String, isBond: Bool)] {
        var paths = app.enabledLinks.map { (label: "\($0.kind.title)（\($0.name)）", outbound: ProfileComposer.linkTag($0.name), isBond: false) }
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
            Text(tunnelWasOn ? "跑的时候隧道开着" : "跑的时候隧道关着").font(.caption).foregroundStyle(.secondary)
            ForEach(rows, id: \.interface) { row in
                HStack {
                    Text("\(row.interface) #\(row.index)").monospaced()
                    Spacer()
                    Text(row.connected ? "成功" : "失败").foregroundStyle(row.connected ? .green : .red)
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
            probeProfileError = "没有可探测的网口"
            return
        }
        var error: NSError?
        LibboxCheckConfig(content, &error)
        if let error {
            probeProfileError = "探测配置未通过 libbox 校验：\(error.localizedDescription)"
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

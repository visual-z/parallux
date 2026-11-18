import ParalluxKit
import SwiftUI

/// The menu bar panel (left click). Skeleton of the v0.2 layout: header with
/// the master switch, links, aggregation mode, exit, footer. The switch and
/// the status line are wired to the tunnel (feat-sysext-xpc); the rest
/// arrives with the M2 interface card.
struct PanelView: View {
    let tunnel: TunnelController
    let profiles: ProfileService
    let openMainWindow: () -> Void
    let openSettings: () -> Void

    @State private var mode: AggregationMode = .balance

    private var isOn: Binding<Bool> {
        Binding(
            get: { tunnel.isConnected || tunnel.vpnStatus == .connecting },
            set: { on in
                Task {
                    if on {
                        if tunnel.phase != .ready { await tunnel.install() }
                        if tunnel.phase == .ready {
                            await connectSelectedProfile()
                        }
                    } else {
                        tunnel.disconnect()
                    }
                }
            }
        )
    }

    /// Uses the selected profile; before any profile exists, the bundled sample.
    private func connectSelectedProfile() async {
        var content = SampleProfile.content
        if let profile = profiles.store.selected {
            do { content = try await profiles.content(of: profile) } catch {
                profileError = error.localizedDescription
                return
            }
        }
        profileError = nil
        await tunnel.connect(TunnelStartOptions(configContent: content))
    }

    @State private var profileError: String?

    private var statusLine: String {
        if let profileError { return profileError }
        switch tunnel.phase {
        case .awaitingApproval: return "请在系统设置中允许网络扩展"
        case let .failed(message): return message
        default: break
        }
        switch tunnel.vpnStatus {
        case .connected:
            if let status = tunnel.status.status {
                return "已连接 · ↓ \(RateFormat.bitsPerSecond(status.downlink)) ↑ \(RateFormat.bitsPerSecond(status.uplink))"
            }
            return "已连接"
        case .connecting, .reasserting: return "正在连接…"
        case .disconnecting: return "正在断开…"
        default: return "未连接"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Parallux").font(.headline)
                    Text(statusLine)
                        .font(.caption).foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer()
                Toggle("开启 Parallux", isOn: isOn).toggleStyle(.switch).labelsHidden()
                    .disabled(tunnel.isBusy)
            }
            Divider()
            Text("聚合方式").font(.caption).foregroundStyle(.secondary)
            Picker("聚合方式", selection: $mode) {
                ForEach(AggregationMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Divider()
            HStack {
                Button("打开主窗口", action: openMainWindow)
                Spacer()
                Button("设置", systemImage: "gearshape", action: openSettings)
                    .labelStyle(.iconOnly)
                    .help("设置")
            }
        }
        .padding(16)
        .frame(width: 340)
    }
}

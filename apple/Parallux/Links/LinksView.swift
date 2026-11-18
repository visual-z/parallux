import ParalluxKit
import SwiftUI

/// 主窗口「线路」：每条线路的开关、拖动排序、仅备用，逐线路速率与健康，
/// 以及「同一公网出口」提示（设计稿 v0.2）。
struct LinksView: View {
    @Environment(AppModel.self) private var app

    private var ordered: [LinkInterface] {
        let prefs = app.linkSettings.value.preferences
        return app.links.links.sorted { a, b in
            let ia = prefs.order.firstIndex(of: a.name) ?? Int.max
            let ib = prefs.order.firstIndex(of: b.name) ?? Int.max
            return ia != ib ? ia < ib : a.name < b.name
        }
    }

    var body: some View {
        let links = ordered
        List {
            if links.isEmpty {
                ContentUnavailableView("没有可用的线路", systemImage: "network.slash",
                                       description: Text("连上 Wi‑Fi、插上网线或用 USB 连接开着个人热点的 iPhone。"))
            }
            Section {
                ForEach(links) { link in
                    LinkRow(link: link)
                }
                .onMove { source, destination in
                    var names = links.map(\.name)
                    names.move(fromOffsets: source, toOffset: destination)
                    app.linkSettings.value.preferences.order = names
                    Task { await app.applyLinkChanges() }
                }
            } footer: {
                Text("拖动排序决定主备模式下的优先级。「仅备用」的线路只在其他线路都不可用时使用（比如只让 iPhone 兜底）。改动立即生效，不会断开正在进行的连接。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let warning = SharedEgress.warning(links: app.enabledLinks, egress: app.links.egress) {
                Section {
                    Label(warning, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
            }
            if app.enabledLinks.count < 2 {
                Section {
                    Text("启用两条以上线路后，分流、主备、叠加才会生效；只有一条线路时按普通代理运行。")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .navigationSubtitle("\(links.count) 个网口 · \(app.enabledLinks.count) 条启用")
        .toolbar {
            ToolbarItem {
                Button("刷新", systemImage: "arrow.clockwise") { app.links.refresh() }.help("重新检测网口")
            }
            ToolbarItem {
                Button("检测出口", systemImage: "stethoscope") { detectEgress() }
                    .disabled(!app.tunnel.isConnected)
                    .help("在网络扩展里逐线路探测公网出口，用于「同一出口」提示")
            }
        }
    }

    private func detectEgress() {
        Task.detached {
            let results = (try? CommandXPCDialer.probeLinks()) ?? []
            await MainActor.run {
                var egress: [String: String] = [:]
                for result in results { if let ip = result.egressIP { egress[result.interface] = ip } }
                app.links.egress = egress
            }
        }
    }
}

private struct LinkRow: View {
    let link: LinkInterface
    @Environment(AppModel.self) private var app

    var body: some View {
        let tag = ProfileComposer.linkTag(link.name)
        let rate = app.linkStats.rates[tag]
        let stat = app.linkStats.link(tag)
        let prefs = app.linkSettings.value.preferences
        HStack(spacing: 12) {
            Image(systemName: link.kind.symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 30, height: 30).background(LinkColors.color(for: link, in: app.links.links), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(link.kind.title).font(.headline)
                Text("\(link.displayName) · \(link.name)").font(.caption).foregroundStyle(.secondary)
            }
            .frame(minWidth: 160, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text("IP \(link.address ?? "—")").font(.caption.monospaced())
                if let ip = app.links.egress[link.name] {
                    Text("出口 \(ip)").font(.caption.monospaced()).foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let stat {
                    Text(stat.healthy ? "可用" : "不可用").font(.caption).foregroundStyle(stat.healthy ? .green : .red)
                    Text("\(RateFormat.bitsPerSecond(rate?.total ?? 0)) · \(stat.active) 条连接").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                } else {
                    Text(app.tunnel.isConnected ? "未参与聚合" : "未连接").font(.caption).foregroundStyle(.secondary)
                }
            }
            Toggle("仅备用", isOn: Binding(
                get: { prefs.backup.contains(link.name) },
                set: { on in
                    if on { app.linkSettings.value.preferences.backup.insert(link.name) } else { app.linkSettings.value.preferences.backup.remove(link.name) }
                    Task { await app.applyLinkChanges() }
                }
            ))
            .toggleStyle(.checkbox).font(.caption)
            .disabled(prefs.disabled.contains(link.name))
            Toggle("启用", isOn: Binding(
                get: { !prefs.disabled.contains(link.name) },
                set: { on in
                    if on { app.linkSettings.value.preferences.disabled.remove(link.name) } else { app.linkSettings.value.preferences.disabled.insert(link.name) }
                    Task { await app.applyLinkChanges() }
                }
            ))
            .toggleStyle(.switch).labelsHidden()
        }
        .padding(.vertical, 4)
    }
}

/// Stable per-link colours (design: Wi‑Fi cyan, wired orange, iPhone pink).
enum LinkColors {
    static func color(for link: LinkInterface, in all: [LinkInterface]) -> Color {
        switch link.kind {
        case .wifi: .cyan
        case .ethernet: [Color.orange, .yellow, .brown][min(2, all.filter { $0.kind == .ethernet }.firstIndex(of: link) ?? 0)]
        case .iPhone: .pink
        case .other: [Color.green, .mint, .teal][min(2, all.filter { $0.kind == .other }.firstIndex(of: link) ?? 0)]
        }
    }
}

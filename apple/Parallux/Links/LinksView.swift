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
        if links.isEmpty {
            ContentUnavailableView {
                Label("不可用", systemImage: "network.slash")
            } actions: {
                Button("刷新") { app.links.refresh() }
            }
            .navigationSubtitle("")
        } else {
            content(links)
        }
    }

    private func content(_ links: [LinkInterface]) -> some View {
        List {
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
                // Design v0.2, links page.
                Text("拖动排序决定主备模式下的优先级。").font(.caption).foregroundStyle(.secondary)
            }
            if let warning = SharedEgress.warning(links: app.enabledLinks, egress: app.links.egress) {
                Section {
                    Label(warning, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: false))
        .navigationSubtitle("\(links.count) 个网口")
        .toolbar {
            ToolbarItem {
                Button("刷新", systemImage: "arrow.clockwise") { app.links.refresh() }.help("刷新")
            }
            ToolbarItem {
                Button("外部地址", systemImage: "globe") { detectEgress() }
                    .disabled(!app.tunnel.isConnected)
                    .help("外部地址")
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
        HStack(spacing: 10) {
            Image(systemName: link.kind.symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 26, height: 26).background(LinkColors.color(for: link, in: app.links.links), in: Circle())
            // Wide windows put the addresses in their own column; narrow ones
            // stack them under the name instead of overflowing.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    names.frame(minWidth: 150, alignment: .leading)
                    addresses
                }
                VStack(alignment: .leading, spacing: 2) {
                    names
                    addresses
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                if let stat {
                    Text(stat.healthy ? "已连接" : "不可用").font(.caption).foregroundStyle(stat.healthy ? .green : .red)
                    Text("\(RateFormat.bitsPerSecond(rate?.total ?? 0)) · 连接 \(stat.active)").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                } else {
                    Text(app.tunnel.isConnected ? "不可用" : "未连接").font(.caption).foregroundStyle(.secondary)
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
        .padding(.vertical, 2)
    }

    private var names: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(link.kind.title).font(.body.weight(.medium))
            Text("\(link.displayName) · \(link.name)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private var addresses: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("IP 地址 \(link.address ?? "—")").font(.caption.monospaced()).lineLimit(1)
            if let ip = app.links.egress[link.name] {
                Text("外部地址 \(ip)").font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

/// Stable per-link colours (design v0.2: Wi‑Fi cyan, wired orange, iPhone
/// pink, in FlowPalette's exact values). A second and third link of a kind
/// get neighbouring hues; none of them is the exits' green or grey.
enum LinkColors {
    static func color(for link: LinkInterface, in all: [LinkInterface]) -> Color {
        switch link.kind {
        case .wifi: FlowPalette.wifi
        case .ethernet: [FlowPalette.wired, .yellow, .brown][min(2, all.filter { $0.kind == .ethernet }.firstIndex(of: link) ?? 0)]
        case .iPhone: FlowPalette.cellular
        case .other: [Color.purple, .indigo, .teal][min(2, all.filter { $0.kind == .other }.firstIndex(of: link) ?? 0)]
        }
    }
}

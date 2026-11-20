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
        // Design v0.2, links page: one list card, the shared-egress warning, a note.
        DesignPage {
            DesignList(items: links, id: \.name, move: { dragged, target in
                app.linkSettings.value.preferences.order = ListReorder.moving(dragged, onto: target, in: links.map(\.name))
                Task { await app.applyLinkChanges() }
            }) { link in
                row(link)
            }
            if let warning = SharedEgress.warning(links: app.enabledLinks, egress: app.links.egress) {
                DesignWarning(text: warning).padding(.top, 10)
            }
            DesignNote(text: "拖动排序决定主备模式下的优先级。").padding(.top, 10)
        }
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

    private func row(_ link: LinkInterface) -> some View {
        let tag = ProfileComposer.linkTag(link.name)
        let rate = RateFormat.bitsPerSecond(app.linkStats.rates[tag]?.total ?? 0)
        let prefs = app.linkSettings.value.preferences
        var addresses = ["IP 地址 \(link.address ?? "—")"]
        if let ip = app.links.egress[link.name] { addresses.append("外部地址 \(ip)") }
        // One state per link, merged over every aggregate (LinkView).
        let status: LinkRowView.Status
        let activity: String
        if let stat = app.linkStats.link(tag) {
            status = stat.healthy ? .init(text: "已连接", tone: .good) : .init(text: "不可用", tone: .bad)
            activity = "\(rate) · 连接 \(stat.active)"
        } else if app.tunnel.isConnected {
            // No aggregate has it: 聚合 is off or the link is not enabled.
            let inUse = app.activeLinks.contains { $0.name == link.name }
            status = inUse ? .init(text: "已连接", tone: .good) : .init(text: "未使用", tone: .plain)
            activity = rate
        } else {
            status = .init(text: "未连接", tone: .plain)
            activity = ""
        }
        return LinkRowView(
            symbol: link.kind.symbol, color: LinkColors.color(for: link, in: app.links.links),
            name: link.kind.title, badge: prefs.backup.contains(link.name) ? "仅备用" : nil,
            detail: "\(link.displayName) · \(link.name)", addresses: addresses, status: status, activity: activity,
            isOn: Binding(
                get: { !app.linkSettings.value.preferences.disabled.contains(link.name) },
                set: { on in
                    if on { app.linkSettings.value.preferences.disabled.remove(link.name) } else { app.linkSettings.value.preferences.disabled.insert(link.name) }
                    Task { await app.applyLinkChanges() }
                }
            ),
            isBackupOnly: Binding(
                get: { app.linkSettings.value.preferences.backup.contains(link.name) },
                set: { on in
                    if on { app.linkSettings.value.preferences.backup.insert(link.name) } else { app.linkSettings.value.preferences.backup.remove(link.name) }
                    Task { await app.applyLinkChanges() }
                }
            )
        )
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
        case .relay: FlowPalette.relay
        }
    }
}

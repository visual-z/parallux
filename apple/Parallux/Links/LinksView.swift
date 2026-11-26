import AppKit
import ParalluxKit
import SwiftUI

/// 主窗口「线路」：每条线路的开关、拖动排序、仅备用，逐线路速率与健康，
/// 以及「同一公网出口」提示（设计稿 v0.2）。中继线路（决策 24）和物理线路
/// 列在同一张表里，下面是添加它们的办法，写法照聚合服务器页。
struct LinksView: View {
    @Environment(AppModel.self) private var app
    @State private var adding = false
    @State private var pasted = ""
    @State private var error: String?

    /// Run on a machine on the LAN; prints the import link when it is done.
    static let relayInstallCommand = "sudo sh install.sh --relay --binary ./parallux-server"

    private var ordered: [LinkInterface] {
        let prefs = app.linkSettings.value.preferences
        return app.allLinks.sorted { a, b in
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
            DesignSectionHeader(title: "添加中继线路") {
                Button("复制") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(Self.relayInstallCommand, forType: .string)
                }
                .designPill()
                .help("复制安装命令")
                Button("添加", systemImage: "plus") { promptForLinks() }.designPill(primary: true)
            }
            DesignCode(text: Self.relayInstallCommand, comment: "# 在局域网里的另一台机器上运行，结束后会显示一个导入链接")
            if !app.relays.relays.isEmpty {
                DesignNote(text: "中继线路在分流下和其他线路轮流承载连接，主备下按排序待命，叠加不使用它们。局域网内的连接不经中继。").padding(.top, 10)
            }
        }
        .navigationSubtitle(Self.subtitle(interfaces: app.links.links.count, relays: app.relays.relays.count))
        .sheet(isPresented: $adding) { addSheet }
        .alert("错误", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("完成") { error = nil }
        } message: { Text(error ?? "") }
        .toolbar {
            ToolbarItem {
                Button("刷新", systemImage: "arrow.clockwise") {
                    app.links.refresh()
                    Task { await app.refreshRelayCarriers(force: true) }
                }
                .help("刷新")
            }
            ToolbarItem {
                Button("外部地址", systemImage: "globe") { detectEgress() }
                    .disabled(!app.tunnel.isConnected)
                    .help("外部地址")
            }
        }
    }

    static func subtitle(interfaces: Int, relays: Int) -> String {
        relays == 0 ? "\(interfaces) 个网口" : "\(interfaces) 个网口 · \(relays) 条中继线路"
    }

    /// The paste sheet. A sheet rather than an alert: several links are
    /// pasted at once, one per line, and an alert's field keeps one line.
    private var addSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("新建中继线路").font(.headline)
            TextEditor(text: $pasted)
                .font(.callout.monospaced())
                .frame(minWidth: 460, minHeight: 120)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
                .accessibilityLabel("parallux://relay?…")
            Text("每行一个导入链接。").font(.footnote).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("取消", role: .cancel) { adding = false }
                Button("导入") { add() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
    }

    /// The import sheet, pre-filled with whatever relay links are on the pasteboard.
    private func promptForLinks() {
        let clipboard = NSPasteboard.general.string(forType: .string) ?? ""
        pasted = clipboard.contains("parallux://relay") ? clipboard : ""
        adding = true
    }

    private func add() {
        let text = pasted
        adding = false
        Task {
            do {
                try await app.addRelays(text)
            } catch let failure as RelayLinkURL.LineFailure {
                error = "第 \(failure.line) 行：\(Self.describe(failure.failure))"
            } catch RelayLinkStore.Failure.full(let limit) {
                error = "中继线路最多 \(limit) 条"
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    static func describe(_ failure: RelayLinkURL.Failure) -> String {
        switch failure {
        // The same three wordings as the aggregation server's link
        // (AggregationServersView.describe; copy from SFM only).
        case .unsupportedVersion, .unsupportedMethod: "服务器不支持"
        case let .missing(field) where field == "host" || field == "port": "缺少 URL"
        default: "不可用"
        }
    }

    private func row(_ link: LinkInterface) -> some View {
        let tag = ProfileComposer.linkTag(link.name)
        let rate = RateFormat.bitsPerSecond(app.linkStats.rates[tag]?.total ?? 0)
        let prefs = app.linkSettings.value.preferences
        let relay = link.kind == .relay ? app.relays.relay(named: link.name) : nil
        var addresses = [relay.map { "地址 \($0.host):\($0.port)" } ?? "IP 地址 \(link.address ?? "—")"]
        if let ip = app.links.egress[link.name] { addresses.append("外部地址 \(ip)") }
        // One state per link, merged over every aggregate (LinkView).
        let status: LinkRowView.Status
        let activity: String
        if let relay, prefs.disabled.contains(link.name) == false, let blocker = app.relayBlocker(link) {
            // A relay that cannot be used says why instead of 未使用.
            switch blocker {
            case .noKey: status = .init(text: "不可用", tone: .bad)
            case .noCarrier: status = app.relays.detecting.contains(relay.id) ? .init(text: "检测中...", tone: .plain) : .init(text: "不可用", tone: .bad)
            case .carrierOff: status = .init(text: "未使用", tone: .plain)
            }
            activity = ""
        } else if let stat = app.linkStats.link(tag) {
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
            name: link.title, badge: prefs.backup.contains(link.name) ? "仅备用" : nil,
            detail: app.linkDetail(link), addresses: addresses, status: status, activity: activity,
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
            ),
            recheck: relay == nil ? nil : { Task { await app.refreshRelayCarriers(force: true) } },
            delete: relay == nil ? nil : { Task { await app.removeRelay(link) } }
        )
    }

    private func detectEgress() {
        Task {
            let results = (try? await CommandXPCDialer.probeLinks()) ?? []
            var egress: [String: String] = [:]
            for result in results { if let ip = result.egressIP { egress[result.interface] = ip } }
            app.links.egress = egress
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

import AppKit
import ParalluxKit
import SwiftUI

/// 主窗口「聚合服务器」：服务器列表、设为叠加服务器、粘贴链接添加、部署说明（设计稿 v0.2）。
struct AggregationServersView: View {
    @Environment(AppModel.self) private var app
    @State private var adding = false
    @State private var link = ""
    @State private var error: String?

    var body: some View {
        let servers = app.servers
        Form {
            Section("服务器") {
                if servers.servers.isEmpty {
                    Text("还没有聚合服务器。叠加需要一台你自己的 VPS 运行 Parallux 服务端，见下方部署步骤。")
                        .foregroundStyle(.secondary)
                }
                ForEach(servers.servers) { server in
                    ServerRow(server: server)
                }
                Button("粘贴导入链接…") {
                    link = NSPasteboard.general.string(forType: .string) ?? ""
                    adding = true
                }
            }
            Section("叠加如何工作") {
                Text("叠加把一条连接拆到两条线路上，在聚合服务器上重组，再转发到订阅节点或直接出网。叠加速度上限取决于服务器带宽；两条线路背后若是同一条宽带，叠加不会更快。")
                    .font(.callout).foregroundStyle(.secondary)
                Text("叠加只聚合 TCP，协议本身不加密：只有发往节点的流量走叠加，并且仍由节点的代理协议加密；配置里走「直连」的流量（局域网、国内）不经聚合服务器，按主备在线路之间切换。")
                    .font(.callout).foregroundStyle(.secondary)
                if app.enabledLinks.count > 2 {
                    Text("当前启用了 \(app.enabledLinks.count) 条线路，叠加使用优先级最高的两条（\(app.enabledLinks.prefix(2).map(\.kind.title).joined(separator: "、"))）。")
                        .font(.callout).foregroundStyle(.orange)
                }
            }
            Section("添加服务器") {
                Text("在 VPS 上以 root 运行（需要 Linux 与 systemd）：").font(.callout)
                Text("sudo sh install.sh --binary ./parallux-server --name 东京VPS")
                    .font(.callout.monospaced()).textSelection(.enabled)
                    .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                Text("`install.sh` 与 `parallux-server` 在仓库的 `server/` 目录（`scripts/build-server.sh` 交叉编译）；发布后会有下载地址。脚本结束时打印一条 `parallux://aggregation-server?…` 链接，复制后在这里粘贴。记得在云厂商防火墙放行脚本提示的端口。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationSubtitle("\(servers.servers.count) 台")
        .toolbar {
            ToolbarItem { Button("测延迟", systemImage: "arrow.clockwise") { servers.pingAll() }.help("重新测量延迟") }
        }
        .onAppear { servers.pingAll() }
        .alert("粘贴导入链接", isPresented: $adding) {
            TextField("parallux://aggregation-server?…", text: $link)
            Button("添加") { add() }
            Button("取消", role: .cancel) {}
        }
        .alert("无法添加", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("好") { error = nil }
        } message: { Text(error ?? "") }
    }

    private func add() {
        do {
            let server = try app.servers.add(link: link)
            if app.linkSettings.value.bondServerID == nil {
                app.linkSettings.value.bondServerID = server.id
                Task { await app.applyLinkChanges() }
            }
        } catch let failure as AggregationServerLink.Failure {
            error = Self.describe(failure)
        } catch {
            self.error = error.localizedDescription
        }
    }

    static func describe(_ failure: AggregationServerLink.Failure) -> String {
        switch failure {
        case .notAParalluxLink: "这不是 Parallux 链接。"
        case .notAnAggregationServerLink: "这是 Parallux 链接，但不是聚合服务器链接。"
        case let .unsupportedVersion(v): "链接版本 \(v ?? "缺失") 不受支持，请更新 Parallux 或服务端。"
        case let .missing(field): "链接缺少 \(field)。"
        case let .duplicate(field): "链接里 \(field) 出现了多次。"
        case let .badPort(port): "端口 \(port) 无效。"
        case .pskTooShort: "密钥太短，请使用 install.sh 生成的链接。"
        }
    }
}

private struct ServerRow: View {
    let server: AggregationServer
    @Environment(AppModel.self) private var app

    var body: some View {
        let inUse = app.linkSettings.value.bondServerID == server.id
        HStack(spacing: 12) {
            Image(systemName: "server.rack").foregroundStyle(inUse ? Color.accentColor : .secondary).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(server.name).font(.headline)
                Text("\(server.host):\(server.port)").font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            Spacer()
            if let ms = app.servers.latency[server.id] {
                Text("\(ms) ms").font(.caption).monospacedDigit().foregroundStyle(DelayGrade(milliseconds: Int32(ms)).color)
            } else if app.servers.unreachable.contains(server.id) {
                Text("不可达").font(.caption).foregroundStyle(.red)
            }
            if inUse {
                Text("叠加使用中").font(.caption).padding(.horizontal, 6).padding(.vertical, 2).background(.tint.opacity(0.2), in: Capsule())
            } else {
                Button("用于叠加") {
                    app.linkSettings.value.bondServerID = server.id
                    Task { await app.applyLinkChanges() }
                }
                .controlSize(.small)
            }
        }
        .contextMenu {
            Button("删除", role: .destructive) {
                if inUse { app.linkSettings.value.bondServerID = nil }
                app.servers.remove(server.id)
                Task { await app.applyLinkChanges() }
            }
        }
        .padding(.vertical, 2)
    }
}

import AppKit
import ParalluxKit
import SwiftUI

/// 主窗口「聚合服务器」：服务器列表、设为叠加服务器、粘贴链接添加、部署说明（设计稿 v0.2）。
struct AggregationServersView: View {
    @Environment(AppModel.self) private var app
    @State private var adding = false
    @State private var link = ""
    @State private var error: String?

    /// Run on the VPS; prints the import link when it is done (decision 18).
    static let installCommand = "sudo sh install.sh --binary ./parallux-server"

    var body: some View {
        let servers = app.servers
        // Design v0.2, aggregation server page: the list card, then how to add one.
        DesignPage {
            if servers.servers.isEmpty {
                DesignList(items: ["无服务器"], id: { $0 }) { Text($0).foregroundStyle(.secondary) }
            } else {
                DesignList(items: servers.servers, id: { $0.id.uuidString }) { server in row(server) }
            }
            DesignSectionHeader(title: "添加服务器") {
                Button("复制") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(Self.installCommand, forType: .string)
                }
                .designPill()
                .help("复制安装命令")
                Button("添加", systemImage: "plus") { promptForLink() }.designPill(primary: true)
            }
            DesignCode(text: Self.installCommand, comment: "# 在 VPS 上运行，结束后会显示一个导入链接")
        }
        .navigationSubtitle(servers.servers.isEmpty ? "" : "\(servers.servers.count)")
        .toolbar {
            ToolbarItem { Button("新建服务器", systemImage: "plus") { promptForLink() }.help("新建服务器") }
            ToolbarItem { Button("延迟测试", systemImage: "bolt") { servers.pingAll() }.help("延迟测试") }
        }
        .onAppear { servers.pingAll() }
        .alert("新建服务器", isPresented: $adding) {
            TextField("parallux://aggregation-server?…", text: $link)
            Button("导入") { add() }
            Button("取消", role: .cancel) {}
        }
        .alert("错误", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("完成") { error = nil }
        } message: { Text(error ?? "") }
    }

    /// The import prompt, pre-filled with whatever link is on the pasteboard.
    private func promptForLink() {
        link = NSPasteboard.general.string(forType: .string) ?? ""
        adding = true
    }

    private func row(_ server: AggregationServer) -> some View {
        let inUse = app.linkSettings.value.bondServerID == server.id
        let latency = app.servers.latency[server.id]
        let unreachable = app.servers.unreachable.contains(server.id)
        return ServerRowView(
            name: server.name, address: "\(server.host):\(server.port)",
            // Design: the server in use is 在线, the others wait.
            tag: unreachable ? "不可用" : inUse ? "在线" : "待命", tone: unreachable ? .bad : inUse ? .good : .plain,
            latency: latency.map { "\($0) ms" } ?? "", latencyColor: DelayGrade(milliseconds: Int32(latency ?? 0)).color,
            inUse: inUse,
            enable: {
                app.linkSettings.value.bondServerID = server.id
                Task { await app.applyLinkChanges() }
            },
            delete: {
                if inUse { app.linkSettings.value.bondServerID = nil }
                app.servers.remove(server.id)
                Task { await app.applyLinkChanges() }
            }
        )
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
        // Copy from SFM only (docs/design/copy-and-style.md): it has no
        // per-reason import errors, so every malformed link reads the same.
        case .unsupportedVersion: "服务器不支持"
        case let .missing(field) where field == "host" || field == "port": "缺少 URL"
        default: "不可用"
        }
    }
}

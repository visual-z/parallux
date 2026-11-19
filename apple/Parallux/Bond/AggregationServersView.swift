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
                    Text("无服务器").foregroundStyle(.secondary)
                }
                ForEach(servers.servers) { server in
                    ServerRow(server: server)
                }
            }
            Section {
                HStack(alignment: .firstTextBaseline) {
                    Text("sudo sh install.sh --binary ./parallux-server")
                        .font(.callout.monospaced()).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("复制") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("sudo sh install.sh --binary ./parallux-server", forType: .string)
                    }
                    .controlSize(.small)
                }
                Button("粘贴") {
                    link = NSPasteboard.general.string(forType: .string) ?? ""
                    adding = true
                }
            } header: {
                Text("添加服务器")
            } footer: {
                Text("在 VPS 上运行，结束后会显示一个导入链接").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationSubtitle(servers.servers.isEmpty ? "" : "\(servers.servers.count)")
        .toolbar {
            ToolbarItem { Button("新建服务器", systemImage: "plus") { link = NSPasteboard.general.string(forType: .string) ?? ""; adding = true }.help("新建服务器") }
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

private struct ServerRow: View {
    let server: AggregationServer
    @Environment(AppModel.self) private var app

    var body: some View {
        let inUse = app.linkSettings.value.bondServerID == server.id
        HStack(spacing: 10) {
            Image(systemName: "server.rack").foregroundStyle(inUse ? Color.accentColor : .secondary).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(server.name).font(.body.weight(.medium))
                Text("\(server.host):\(server.port)").font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            Spacer()
            if let ms = app.servers.latency[server.id] {
                Text("\(ms) ms").font(.caption).monospacedDigit().foregroundStyle(DelayGrade(milliseconds: Int32(ms)).color)
            } else if app.servers.unreachable.contains(server.id) {
                Text("不可用").font(.caption).foregroundStyle(.red)
            }
            if inUse {
                Text("在线").font(.caption).foregroundStyle(.green)
            } else {
                Button("启用") {
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

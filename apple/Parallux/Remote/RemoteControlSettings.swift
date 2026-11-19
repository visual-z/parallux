import ParalluxKit
import SwiftUI

/// Settings › 远程控制: view and control another device's running core (SFM #94–96).
struct RemoteControlSettings: View {
    @Environment(AppModel.self) private var app
    @State private var adding = false

    var body: some View {
        let remote = app.remote
        Form {
            Section("服务器") {
                LabeledContent("本机") {
                    if remote.isRemote {
                        Button("连接") { remote.activate(nil, session: app.session, localConnected: app.tunnel.isConnected) }
                    } else {
                        Text("已连接").foregroundStyle(.secondary)
                    }
                }
                ForEach(remote.servers) { server in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(server.name)
                            Text(server.address).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                        Spacer()
                        switch remote.reachable[server.id] {
                        case true?: Text("已启动").font(.caption).foregroundStyle(.green)
                        case false?: Text("不可用").font(.caption).foregroundStyle(.red)
                        case nil: EmptyView()
                        }
                        if remote.active?.id == server.id {
                            Text("已连接").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Button("连接") { remote.activate(server, session: app.session) }
                        }
                    }
                    .contextMenu {
                        Button("刷新") { remote.probe(server) }
                        Button("删除", role: .destructive) { remote.remove(server.id) }
                    }
                }
                Button("新建服务器") { adding = true }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $adding) { AddRemoteServer() }
        .onAppear { remote.servers.forEach(remote.probe) }
    }
}

private struct AddRemoteServer: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var address = ""
    @State private var secret = ""
    @State private var error: String?

    var body: some View {
        Form {
            TextField("名称", text: $name, prompt: Text("可选"))
            TextField("URL", text: $address, prompt: Text("必填"))
            SecureField("密钥", text: $secret)
            if let error { Text(error).foregroundStyle(.red) }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("创建") {
                    do {
                        try app.remote.add(name: name, address: address, secret: secret)
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }
                .disabled(RemoteServerAddress.connectURL(address).isEmpty)
            }
        }
    }
}

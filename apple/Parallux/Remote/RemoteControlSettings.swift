import ParalluxKit
import SwiftUI

/// Settings › 远程控制: view and control another device's running core (SFM #94–96).
struct RemoteControlSettings: View {
    @Environment(AppModel.self) private var app
    @State private var adding = false

    var body: some View {
        let remote = app.remote
        Form {
            Section {
                Text("和 SFM 一样，可以查看并控制另一台设备上运行的内核。对方需要开启 command server（端口与密钥）。")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("设备") {
                LabeledContent("本机") {
                    if remote.isRemote {
                        Button("切回本机") { remote.activate(nil, session: app.session, localConnected: app.tunnel.isConnected) }
                    } else {
                        Text("正在查看").foregroundStyle(.secondary)
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
                        case true?: Text("可达").font(.caption).foregroundStyle(.green)
                        case false?: Text("不可达").font(.caption).foregroundStyle(.red)
                        case nil: EmptyView()
                        }
                        if remote.active?.id == server.id {
                            Text("正在查看").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Button("查看") { remote.activate(server, session: app.session) }
                        }
                    }
                    .contextMenu {
                        Button("探测") { remote.probe(server) }
                        Button("删除", role: .destructive) { remote.remove(server.id) }
                    }
                }
                Button("添加远程设备…") { adding = true }
            }
            Section {
                Text("查看远程设备时，本机才有的操作（开关隧道、线路、聚合方式、系统代理）不可用。").font(.caption).foregroundStyle(.secondary)
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
            TextField("地址", text: $address, prompt: Text("192.168.1.20:9090"))
            SecureField("密钥", text: $secret)
            if let error { Text(error).foregroundStyle(.red) }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("添加") {
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

import ParalluxKit
import SwiftUI

/// Diagnostics › 端点: Tailscale (status, login, exit node, waiting files),
/// OpenVPN / OpenConnect (status, challenges). Shown only when the profile has such endpoints.
struct EndpointsSection: View {
    @Environment(AppModel.self) private var app
    @State private var model = EndpointsModel()
    @State private var answering: EndpointStatus?

    var body: some View {
        Group {
            if !model.statuses.isEmpty {
                Section("端点") {
                    ForEach(model.statuses) { status in
                        EndpointRow(status: status, model: model) { answering = status }
                    }
                }
            }
        }
        .task(id: app.session.isRunning) {
            model.stop()
            if app.session.isRunning { model.start() }
        }
        .onDisappear { model.stop() }
        .sheet(item: $answering) { status in ChallengeSheet(status: status, model: model) }
    }
}

private struct EndpointRow: View {
    let status: EndpointStatus
    let model: EndpointsModel
    let answer: () -> Void

    var body: some View {
        let line = EndpointSummary.line(status)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(title) · \(status.tag)").font(.headline)
                Spacer()
                Text(line.text).font(.caption).foregroundStyle(line.isError ? .red : line.needsUser ? .orange : .secondary)
                    .textSelection(.enabled).lineLimit(2)
            }
            if status.kind == .tailscale {
                if let url = URL(string: status.authURL), !status.authURL.isEmpty {
                    Link("在浏览器中登录", destination: url).font(.callout)
                }
                let peers = model.peers[status.tag] ?? []
                let exits = peers.filter(\.exitNodeOption)
                if !exits.isEmpty {
                    Picker("出口节点", selection: Binding(
                        get: { exits.first(where: \.isExitNode)?.id ?? "" },
                        set: { model.setExitNode(endpoint: status.tag, peer: $0) }
                    )) {
                        Text("不使用").tag("")
                        ForEach(exits) { Text("\($0.name)\($0.online ? "" : "（离线）")").tag($0.id) }
                    }
                }
                if let waiting = model.waitingFiles[status.tag], waiting > 0 {
                    Text("Taildrop：\(waiting) 个文件等待接收（接收功能尚未提供，可在其他 Tailscale 客户端里接收）").font(.caption).foregroundStyle(.secondary)
                }
            } else if line.needsUser {
                HStack {
                    Button("回应认证…", action: answer)
                    Button("取消认证") { model.cancel(status) }
                }
                .controlSize(.small)
            }
        }
        .padding(.vertical, 2)
    }

    private var title: String {
        switch status.kind {
        case .tailscale: "Tailscale"
        case .openVPN: "OpenVPN"
        case .openConnect: "OpenConnect"
        }
    }
}

private struct ChallengeSheet: View {
    let status: EndpointStatus
    let model: EndpointsModel
    @Environment(\.dismiss) private var dismiss
    @State private var values: [String: String] = [:]

    private var fields: [EndpointsModel.FormField] {
        status.kind == .openConnect
            ? (model.forms[status.tag] ?? [])
            : [.init(key: "username", label: "用户名", secret: false), .init(key: "password", label: "密码或一次性口令", secret: true)]
    }

    var body: some View {
        Form {
            Text("\(status.tag) 需要认证").font(.headline)
            ForEach(fields) { field in
                let binding = Binding(get: { values[field.key] ?? "" }, set: { values[field.key] = $0 })
                if field.secret { SecureField(field.label, text: binding) } else { TextField(field.label, text: binding) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("提交") { model.answer(status, values: values); dismiss() }
            }
        }
    }
}

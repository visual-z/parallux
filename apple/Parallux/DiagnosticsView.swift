import AppKit
import ParalluxKit
import SwiftUI

/// Diagnostics page. For now only the per-link bind probe
/// (research-sysext-bind-interface); speed tests and DNS/MTU checks come later.
struct DiagnosticsView: View {
    @State private var results: [LinkProbeResult] = []
    @State private var error: String?
    @State private var running = false

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("在网络扩展里对每个物理网口单独建连，检查能否绑定非默认网口，以及各自的出口地址。需要隧道已连接。")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(running ? "检测中…" : "检测线路", action: run).disabled(running)
                }
                if let error {
                    Text(error).foregroundStyle(.red)
                }
            }
            if !results.isEmpty {
                Section("结果") {
                    Table(results) {
                        TableColumn("网口") { Text("\($0.interface) #\($0.index)").monospaced() }
                        TableColumn("建连") { Text($0.connected ? "成功" : "失败").foregroundStyle($0.connected ? .green : .red) }
                        TableColumn("errno") { r in Text(r.errno.map { "\($0) (\(r.failedCall ?? ""))" } ?? "—").monospaced() }
                        TableColumn("耗时") { Text("\($0.millis) ms").monospacedDigit() }
                        TableColumn("出口 IP") { Text($0.egressIP ?? "—").monospaced().textSelection(.enabled) }
                    }
                    .frame(minHeight: 160)
                    Button("拷贝结果", action: copy)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func run() {
        running = true
        error = nil
        Task.detached {
            let outcome = Result { try CommandXPCDialer.probeLinks() }
            await MainActor.run {
                running = false
                switch outcome {
                case let .success(value): results = value
                case let .failure(failure): error = failure.localizedDescription
                }
            }
        }
    }

    private func copy() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(results) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(String(decoding: data, as: UTF8.self), forType: .string)
    }
}

extension LinkProbeResult: @retroactive Identifiable {
    public var id: String { interface }
}

import AppKit
import ParalluxKit
import SwiftUI

/// 设置 › 内核 › 辅助服务: install state, working directory, crash reports.
///
/// The working directory is root's container for the extension, which Finder
/// cannot open (mode 700), so the page shows its path with "拷贝路径"
/// instead of "在访达中显示" (docs/tasks/feat-helper-service.md, 环境假设).
struct HelperSettingsSection: View {
    @State private var helper = HelperServiceManager()
    @State private var confirmingDestroy = false
    @State private var report: CrashReportCatalog.Report?

    var body: some View {
        Group { sections }.task { await helper.refresh() }
    }

    @ViewBuilder private var sections: some View {
        Section("辅助服务") {
            LabeledContent("状态", value: stateText)
            if let version = helper.version { LabeledContent("版本", value: version) }
            HStack {
                switch helper.state {
                case .enabled:
                    Button("更新") { Task { await helper.install() } }
                    Button("卸载", role: .destructive) { Task { await helper.uninstall() } }
                case .requiresApproval:
                    Button("打开设置") { helper.openApproval() }
                    Button("卸载", role: .destructive) { Task { await helper.uninstall() } }
                case .notInstalled, .failed:
                    Button("安装辅助服务") { Task { await helper.install() } }
                case .unsigned:
                    EmptyView()
                }
            }
            .disabled(helper.busy)
            if let error = helper.lastError { Text(error).font(.caption).foregroundStyle(.red) }
        }
        if helper.state == .enabled {
            Section("工作目录") {
                if let info = helper.workingDirectory {
                    LabeledContent("工作目录") {
                        Text(info.path).font(.caption.monospaced()).textSelection(.enabled).lineLimit(2)
                    }
                    LabeledContent("数据大小", value: info.exists ? RateFormat.bytes(info.sizeBytes) : "空")
                    HStack {
                        Button("复制") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(info.path, forType: .string)
                        }
                        Button("清理", role: .destructive) { confirmingDestroy = true }
                            .disabled(!info.exists)
                    }
                    .disabled(helper.busy)
                }
            }
            Section("崩溃报告") {
                if helper.crashReports.isEmpty {
                    Text("空").foregroundStyle(.secondary)
                } else {
                    ForEach(helper.crashReports, id: \.name) { entry in
                        Button {
                            Task { report = await helper.readCrashReport(entry.name) }
                        } label: {
                            LabeledContent(entry.name, value: entry.modified.formatted(date: .abbreviated, time: .shortened))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .confirmationDialog("确认删除", isPresented: $confirmingDestroy) {
                Button("清理", role: .destructive) { Task { await helper.destroyWorkingDirectory() } }
            } message: {
                Text("此操作不可逆")
            }
            .sheet(item: Binding(get: { report.map(ReportBox.init) }, set: { report = $0?.report })) { box in
                CrashReportView(report: box.report)
            }
        }
    }

    private var stateText: String {
        switch helper.state {
        case .notInstalled: "已禁用"
        case .requiresApproval: "需要辅助服务"
        case .enabled: "已启用"
        case .unsigned: "仅在 macOS 独立版本中可用"
        case let .failed(message): message
        }
    }
}

private struct ReportBox: Identifiable {
    let report: CrashReportCatalog.Report
    var id: String { report.name }
}

private struct CrashReportView: View {
    let report: CrashReportCatalog.Report
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(report.name).font(.headline)
            if report.truncated {
                Text("只显示前 \(CrashReportCatalog.maxReadBytes >> 10) KB").font(.caption).foregroundStyle(.secondary)
            }
            ScrollView {
                Text(report.text).font(.caption.monospaced()).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Button("复制") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(report.text, forType: .string)
                }
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 640, height: 480)
    }
}

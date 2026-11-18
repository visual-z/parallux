import ParalluxKit
import SwiftUI

/// 设置 › 通用：自动检查更新、检查更新、更新渠道、上次检查（设计稿 v0.2；
/// 设计稿的叫法是词表禁词，见 docs/tasks/feat-release.md 来源）。
struct UpdateSection: View {
    @State private var updater = UpdaterModel.shared

    var body: some View {
        @Bindable var updater = updater
        Section("更新") {
            if updater.isConfigured {
                Toggle("自动检查更新", isOn: Binding(get: { updater.automaticallyChecks }, set: { updater.automaticallyChecks = $0 }))
                Picker("更新渠道", selection: $updater.channel) {
                    ForEach(UpdateChannel.allCases) { Text($0.title).tag($0) }
                }
                HStack {
                    Text(updater.lastCheck.map { "上次检查：\($0.formatted(date: .abbreviated, time: .shortened))" } ?? "还没有检查过")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("检查更新…") { updater.checkForUpdates() }.disabled(!updater.canCheckForUpdates)
                }
            } else {
                Text("此构建未配置更新源（开发构建）。发布构建由 scripts/release.sh 写入更新地址与公钥。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

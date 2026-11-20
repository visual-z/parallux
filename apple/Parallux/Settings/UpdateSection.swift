import ParalluxKit
import SwiftUI

/// 设置 › 通用：自动检查更新、检查更新、更新渠道、上次检查（设计稿 v0.2；
/// 设计稿的叫法是词表禁词，这里用「更新渠道」）。
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
                    if let last = updater.lastCheck {
                        Text(last.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("检查更新") { updater.checkForUpdates() }.disabled(!updater.canCheckForUpdates)
                }
            } else {
                LabeledContent("检查更新", value: "仅在 macOS 独立版本中可用")
            }
        }
    }
}

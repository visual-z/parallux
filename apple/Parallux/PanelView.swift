import ParalluxKit
import SwiftUI

/// The menu bar panel (left click). Skeleton of the v0.2 layout: header with
/// the master switch, links, aggregation mode, exit, footer. Values are not
/// wired to the core yet.
struct PanelView: View {
    let openMainWindow: () -> Void

    @State private var isOn = false
    @State private var mode: AggregationMode = .balance

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Parallux").font(.headline)
                    Text(isOn ? "已连接 · \(mode.title)" : "未连接")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("开启 Parallux", isOn: $isOn).toggleStyle(.switch).labelsHidden()
            }
            Divider()
            Text("聚合方式").font(.caption).foregroundStyle(.secondary)
            Picker("聚合方式", selection: $mode) {
                ForEach(AggregationMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Divider()
            HStack {
                Button("打开主窗口", action: openMainWindow)
                Spacer()
                SettingsLink { Image(systemName: "gearshape") }
                    .help("设置")
            }
        }
        .padding(16)
        .frame(width: 340)
    }
}

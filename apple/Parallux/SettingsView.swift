import Libbox
import ParalluxKit
import SwiftUI

/// The Settings window (⌘,). One tab per `SettingsTab`; only Core shows real
/// data so far, which also proves the app links Libbox.xcframework.
struct SettingsView: View {
    var body: some View {
        TabView {
            ForEach(SettingsTab.allCases) { tab in
                Tab(tab.title, systemImage: tab.symbol) {
                    content(for: tab)
                }
            }
        }
        .frame(width: 560, height: 360)
    }

    @ViewBuilder private func content(for tab: SettingsTab) -> some View {
        switch tab {
        case .core:
            Form {
                LabeledContent("内核版本", value: PxbridgeVersion())
                LabeledContent("App Group", value: AppGroup.identifier() ?? "未签名构建，无 App Group")
            }
            .formStyle(.grouped)
        default:
            ContentUnavailableView(tab.title, systemImage: tab.symbol, description: Text("尚未实现"))
        }
    }
}

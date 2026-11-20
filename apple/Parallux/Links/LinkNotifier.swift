import Foundation
import ParalluxKit
import UserNotifications

/// Posts 「线路掉线 / 恢复」 notifications from health changes in linkStats.
@MainActor
final class LinkNotifier {
    private var last: [String: Bool] = [:]
    private var authorized = false

    func update(groups: [LinkGroupStat], links: [LinkInterface], enabled: Bool) {
        // Merged over every aggregate, so group order cannot flip it.
        let current = LinkView.merge(groups).mapValues(\.healthy)
        defer { last = current }
        guard enabled, !last.isEmpty else { return }
        for (tag, healthy) in current where last[tag] != nil && last[tag] != healthy {
            let name = links.first { ProfileComposer.linkTag($0.name) == tag }.map { $0.kind == .relay ? "中继线路 \($0.title)" : "\($0.kind.title)（\($0.name)）" } ?? tag
            post(title: healthy ? "线路已恢复" : "线路不可用", body: healthy ? "\(name)重新参与聚合。" : "\(name)暂时不可用，新连接改走其他线路。")
        }
    }

    private func post(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        Task {
            if !authorized {
                authorized = (try? await center.requestAuthorization(options: [.alert])) ?? false
            }
            guard authorized else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }
}

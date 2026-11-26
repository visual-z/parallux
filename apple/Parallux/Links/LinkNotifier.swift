import Foundation
import ParalluxKit
import UserNotifications

/// Posts 「线路不可用 / 已恢复」 notifications. Which health changes deserve
/// one, and what they say, is LinkAlerts' call (fix-link-alerts-single-line).
@MainActor
final class LinkNotifier {
    private var alerts = LinkAlerts()
    private var authorized = false

    func update(groups: [LinkGroupStat], links: [LinkInterface], enabled: Bool, now: Date = Date()) {
        // Merged over every aggregate, so group order cannot flip it.
        let health = LinkView.merge(groups).mapValues(\.healthy)
        let names = Dictionary(links.map { link in
            (ProfileComposer.linkTag(link.name), link.kind == .relay ? "中继线路 \(link.title)" : "\(link.kind.title)（\(link.name)）")
        }, uniquingKeysWith: { first, _ in first })
        // Stepped even when notifications are off, so turning them on does
        // not announce a change that happened while they were off.
        let due = alerts.step(health: health, names: names, now: now)
        guard enabled else { return }
        for alert in due { post(title: alert.title, body: alert.body) }
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

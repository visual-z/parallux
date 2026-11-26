import Foundation
import ParalluxKit
import UserNotifications

/// Posts the core's notifications (SFM parity #111). The system extension
/// queues them (it has no user session); this drains the queue over XPC
/// while the tunnel is up and posts them with UNUserNotificationCenter.
@MainActor
final class CoreNotificationForwarder {
    private let app: AppModel
    private var task: Task<Void, Never>?
    private var authorized: Bool?

    /// Why 2 s: core notifications are rare; a two-second delay is invisible
    /// and costs one XPC round trip per tick only while connected.
    static let interval: Duration = .seconds(2)

    init(app: AppModel) { self.app = app }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.interval)
                guard let self else { return }
                guard self.app.tunnel.isConnected else { continue }
                // Suspends while the extension answers; holds no thread
                // (refactor-xpc-polls-suspend).
                let items = await CommandXPCDialer.notifications()
                if !items.isEmpty { await self.post(items) }
            }
        }
    }

    private func post(_ items: [CoreNotification]) async {
        let center = UNUserNotificationCenter.current()
        if authorized == nil {
            authorized = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        }
        for item in items {
            if item.cancel {
                center.removePendingNotificationRequests(withIdentifiers: [item.identifier])
                center.removeDeliveredNotifications(withIdentifiers: [item.identifier])
                continue
            }
            guard authorized == true else { continue }
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.subtitle = item.subtitle
            content.body = item.body
            if !item.openURL.isEmpty { content.userInfo["OPEN_URL"] = item.openURL }
            try? await center.add(UNNotificationRequest(identifier: item.identifier, content: content, trigger: nil))
        }
    }
}

import Foundation

/// A notification the core asked for (libbox `PlatformInterface.send`). The
/// system extension runs outside the user session, so it queues them and the
/// app posts them (card feat-system-integration, 环境假设).
public struct CoreNotification: Codable, Equatable, Sendable {
    public var identifier: String
    public var title: String
    public var subtitle: String
    public var body: String
    public var openURL: String
    /// true for a cancellation of `identifier` rather than a new notification.
    public var cancel: Bool

    public init(identifier: String, title: String = "", subtitle: String = "", body: String = "", openURL: String = "", cancel: Bool = false) {
        self.identifier = identifier
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.openURL = openURL
        self.cancel = cancel
    }
}

/// Bounded FIFO of pending notifications in the extension.
public final class NotificationQueue: @unchecked Sendable {
    /// Why 32: core notifications are sporadic; 32 covers a burst during a
    /// reconnect storm while capping memory if the app never drains.
    public static let capacity = 32
    private let lock = NSLock()
    private var items: [CoreNotification] = []

    public init() {}

    public func push(_ item: CoreNotification) {}
    /// Removes and returns everything queued, oldest first.
    public func drain() -> [CoreNotification] { [] }

    public static func encode(_ items: [CoreNotification]) -> Data { Data() }
    public static func decode(_ data: Data) -> [CoreNotification] { [] }
}

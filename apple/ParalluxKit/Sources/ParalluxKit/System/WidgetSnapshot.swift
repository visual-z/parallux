import Foundation

/// What the widget and the Control Center toggle show, written by the app
/// into the App Group's UserDefaults.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public var connected: Bool
    /// AggregationMode raw value in effect, nil with fewer than two links.
    public var mode: String?
    public var linkCount: Int
    /// Bytes per second, both directions.
    public var rate: Int64
    public var profileName: String?
    public var updatedAt: Date

    public init(connected: Bool, mode: String?, linkCount: Int, rate: Int64, profileName: String?, updatedAt: Date) {
        self.connected = connected
        self.mode = mode
        self.linkCount = linkCount
        self.rate = rate
        self.profileName = profileName
        self.updatedAt = updatedAt
    }

    public static let defaultsKey = "parallux.widget-snapshot"
    /// Why 60 s: the app rewrites at least every 5 s while running; a minute
    /// without a write means the app quit, so the numbers are not current.
    public static let staleAfter: TimeInterval = 60

    public func isStale(now: Date) -> Bool { false }

    public func encoded() -> Data { Data() }
    public static func decode(_ data: Data?) -> WidgetSnapshot? { nil }
}

/// Decides when the app writes a new snapshot.
public struct WidgetSnapshotThrottle: Sendable {
    /// Why 5 s: widgets cannot animate rates anyway; WidgetKit budgets reloads.
    public static let interval: TimeInterval = 5
    private var last: WidgetSnapshot?

    public init() {}

    /// true when `snapshot` should be written now; records it if so.
    public mutating func shouldWrite(_ snapshot: WidgetSnapshot) -> Bool { true }

    /// true when the change also needs widget and control reloads (state, not just rate).
    public static func isStateChange(from old: WidgetSnapshot?, to new: WidgetSnapshot) -> Bool { true }
}

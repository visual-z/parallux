import Foundation

// stubs: fix-overview-cards

/// What a subscription server says about the account's traffic.
public struct SubscriptionUsage: Codable, Equatable, Sendable {
    public var upload: Int64
    public var download: Int64
    /// The quota in bytes; nil when the server states none.
    public var total: Int64?
    public var expires: Date?

    public init(upload: Int64, download: Int64, total: Int64? = nil, expires: Date? = nil) {
        self.upload = upload
        self.download = download
        self.total = total
        self.expires = expires
    }

    public var used: Int64 { 0 }

    public static func parse(header: String?) -> SubscriptionUsage? { nil }
}

/// The profile card's usage line and bar.
public struct UsageSummary: Equatable, Sendable {
    public var text: String
    /// Used share of the quota, 0...1; nil when there is no quota to draw.
    public var fraction: Double?
    public var note: String?

    public static func make(usage: SubscriptionUsage?, sessionTotal: Int64, now: Date, timeZone: TimeZone = .current) -> UsageSummary {
        UsageSummary(text: "", fraction: nil, note: nil)
    }
}

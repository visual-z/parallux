import Foundation

/// What a subscription server says about the account's traffic, from the
/// `subscription-userinfo` response header that comes with the profile:
///
///     upload=1073741824; download=2147483648; total=107374182400; expire=1798675200
///
/// Bytes and Unix seconds. There is no specification, only the convention
/// Clash-family clients and subscription panels share; every field may be
/// missing, so the parser takes what it can read and nothing more.
public struct SubscriptionUsage: Codable, Equatable, Sendable {
    public var upload: Int64
    public var download: Int64
    /// The quota in bytes; nil when the server states none (absent, or 0,
    /// which is how panels write "unlimited").
    public var total: Int64?
    public var expires: Date?

    public init(upload: Int64, download: Int64, total: Int64? = nil, expires: Date? = nil) {
        self.upload = upload
        self.download = download
        self.total = total
        self.expires = expires
    }

    /// Upload plus download, saturating: the counts come from a server.
    public var used: Int64 {
        let (sum, overflow) = upload.addingReportingOverflow(download)
        return overflow ? .max : sum
    }

    /// nil when the header says nothing about traffic: missing, not in this
    /// form, or carrying only an expiry.
    public static func parse(header: String?) -> SubscriptionUsage? {
        guard let header else { return nil }
        var values: [String: Int64] = [:]
        for field in header.split(separator: ";") {
            let parts = field.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
            guard let value = count(parts[1].trimmingCharacters(in: .whitespaces)) else { continue }
            values[key] = value
        }
        guard values["upload"] != nil || values["download"] != nil || values["total"] != nil else { return nil }
        let total = values["total"].flatMap { $0 > 0 ? $0 : nil }
        let expires = values["expire"].flatMap { $0 > 0 ? Date(timeIntervalSince1970: TimeInterval($0)) : nil }
        return SubscriptionUsage(upload: values["upload"] ?? 0, download: values["download"] ?? 0, total: total, expires: expires)
    }

    /// A count as servers write it: an integer, or a decimal or exponent
    /// form. Negative reads as 0; anything past Int64 saturates.
    private static func count(_ text: String) -> Int64? {
        if let exact = Int64(text) { return max(exact, 0) }
        guard let value = Double(text), !value.isNaN else { return nil }
        if value <= 0 { return 0 }
        // Int64(exactly:) would trap-free reject 2^63; compare first.
        return value >= 9_223_372_036_854_775_807 ? .max : Int64(value)
    }
}

/// The profile card's usage line and bar (overview).
public struct UsageSummary: Equatable, Sendable {
    public var text: String
    /// `text` in two parts, for a row with the label on one side. stub
    public var label: String { "" }
    public var value: String { "" }
    /// Used share of the quota, 0...1; nil when there is no quota to draw.
    public var fraction: Double?
    /// The expiry, when the server states one.
    public var note: String?

    public init(text: String, fraction: Double?, note: String?) {
        self.text = text
        self.fraction = fraction
        self.note = note
    }

    /// - Parameters:
    ///   - usage: the selected profile's, nil when its server reports none
    ///     or it is not a subscription.
    ///   - sessionTotal: bytes the core carried this session, both
    ///     directions. Shown only without `usage`, and labelled as what it
    ///     is: it is not the account's running total.
    public static func make(usage: SubscriptionUsage?, sessionTotal: Int64, now: Date, timeZone: TimeZone = .current) -> UsageSummary {
        guard let usage else {
            return UsageSummary(text: "本次会话已用 \(RateFormat.bytes(sessionTotal)) / 无限", fraction: nil, note: nil)
        }
        var note: String?
        if let expires = usage.expires {
            let day = day(expires, timeZone: timeZone)
            note = expires <= now ? "已于 \(day) 到期" : "\(day) 到期"
        }
        guard let total = usage.total else {
            return UsageSummary(text: "已用 \(RateFormat.bytes(usage.used)) / 无限", fraction: nil, note: note)
        }
        // total > 0 by SubscriptionUsage.parse; a hand-built 0 draws a full bar.
        let fraction = total > 0 ? min(max(Double(usage.used) / Double(total), 0), 1) : 1
        return UsageSummary(text: "已用 \(RateFormat.bytes(usage.used)) / \(RateFormat.bytes(total))", fraction: fraction, note: note)
    }

    /// The calendar day in the user's time zone, as 2026-12-31.
    private static func day(_ date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

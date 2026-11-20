import Foundation
import Testing
@testable import ParalluxKit

private let gib: Int64 = 1 << 30
private let utc = TimeZone(identifier: "UTC")!

@Suite struct SubscriptionUsageTests {
    /// The header subscription servers send, as Clash-family and sing-box
    /// clients read it: `upload=…; download=…; total=…; expire=…`, bytes and
    /// Unix seconds, any order, any spacing, any of them missing.
    @Test func theUserinfoHeaderGivesUsedTotalAndExpiry() throws {
        let full = try #require(SubscriptionUsage.parse(header: "upload=1073741824; download=2147483648; total=107374182400; expire=1798675200"))
        #expect(full.upload == gib)
        #expect(full.download == 2 * gib)
        #expect(full.used == 3 * gib)
        #expect(full.total == 100 * gib)
        #expect(full.expires == Date(timeIntervalSince1970: 1_798_675_200))

        let loose = try #require(SubscriptionUsage.parse(header: " Total = 1000 ;download=40;UPLOAD=2;;expire=;future=x "))
        #expect(loose == SubscriptionUsage(upload: 2, download: 40, total: 1000, expires: nil), "order, case, spaces, an empty value and an unknown key")

        // No quota: absent, or 0 as providers write "unlimited".
        #expect(try #require(SubscriptionUsage.parse(header: "upload=5; download=7")).total == nil)
        #expect(try #require(SubscriptionUsage.parse(header: "upload=5; download=7; total=0")).total == nil)
        #expect(try #require(SubscriptionUsage.parse(header: "upload=5; download=7; total=0; expire=0")).expires == nil, "expire=0 is no expiry")
        // Only a quota, nothing used yet.
        #expect(SubscriptionUsage.parse(header: "total=1000") == SubscriptionUsage(upload: 0, download: 0, total: 1000))
        // Some servers write decimals or exponents.
        #expect(try #require(SubscriptionUsage.parse(header: "upload=1.0; download=2.5E3; total=1e12")).used == 2501)
        // Negative counts read as 0; counts past Int64 saturate instead of trapping.
        let odd = try #require(SubscriptionUsage.parse(header: "upload=-5; download=9223372036854775807; total=99999999999999999999999"))
        #expect(odd.upload == 0)
        #expect(odd.total == Int64.max)
        #expect(SubscriptionUsage(upload: Int64.max, download: Int64.max).used == Int64.max, "used saturates")

        // Nothing usable.
        #expect(SubscriptionUsage.parse(header: nil) == nil)
        #expect(SubscriptionUsage.parse(header: "") == nil)
        #expect(SubscriptionUsage.parse(header: "expire=1798675200") == nil, "an expiry alone says nothing about traffic")
        #expect(SubscriptionUsage.parse(header: "upload=abc; download=") == nil)
        #expect(SubscriptionUsage.parse(header: "<html>502 Bad Gateway</html>") == nil)
    }

    @Test func theProfileCardShowsUsedOverQuotaOrOverUnlimited() {
        let now = Date(timeIntervalSince1970: 1_790_000_000) // 2026-09-21 UTC
        let expires = Date(timeIntervalSince1970: 1_798_675_200) // 2026-12-31 00:00 UTC

        // A quota: used over total, the bar at the used share.
        let quota = UsageSummary.make(usage: SubscriptionUsage(upload: gib, download: 24 * gib, total: 100 * gib, expires: expires),
                                      sessionTotal: 999, now: now, timeZone: utc)
        #expect(quota.text == "已用 \(RateFormat.bytes(25 * gib)) / \(RateFormat.bytes(100 * gib))")
        #expect(quota.fraction == 0.25)
        #expect(quota.note == "2026-12-31 到期")

        // 0, exactly the quota, and past it: the bar stays within 0...1.
        #expect(UsageSummary.make(usage: SubscriptionUsage(upload: 0, download: 0, total: 100), sessionTotal: 0, now: now, timeZone: utc).fraction == 0)
        #expect(UsageSummary.make(usage: SubscriptionUsage(upload: 40, download: 60, total: 100), sessionTotal: 0, now: now, timeZone: utc).fraction == 1)
        let over = UsageSummary.make(usage: SubscriptionUsage(upload: 0, download: 150, total: 100), sessionTotal: 0, now: now, timeZone: utc)
        #expect(over.fraction == 1)
        #expect(over.text == "已用 \(RateFormat.bytes(150)) / \(RateFormat.bytes(100))", "the text still says how far over")
        #expect(over.note == nil, "no expiry stated, no note")

        // The server reports usage but no quota: used over 无限, no bar.
        let unlimited = UsageSummary.make(usage: SubscriptionUsage(upload: gib, download: gib), sessionTotal: 999, now: now, timeZone: utc)
        #expect(unlimited.text == "已用 \(RateFormat.bytes(2 * gib)) / 无限")
        #expect(unlimited.fraction == nil)

        // The server says nothing (or the profile is local): what this
        // session carried, over 无限, and it says which figure that is.
        let silent = UsageSummary.make(usage: nil, sessionTotal: 3 * gib, now: now, timeZone: utc)
        #expect(silent.text == "本次会话已用 \(RateFormat.bytes(3 * gib)) / 无限")
        #expect(silent.fraction == nil)
        #expect(silent.note == nil)
        #expect(UsageSummary.make(usage: nil, sessionTotal: 0, now: now, timeZone: utc).text == "本次会话已用 \(RateFormat.bytes(0)) / 无限")

        // An expiry in the past says so.
        let lapsed = UsageSummary.make(usage: SubscriptionUsage(upload: 0, download: 1, total: 10, expires: Date(timeIntervalSince1970: 1_780_000_000)),
                                       sessionTotal: 0, now: now, timeZone: utc)
        #expect(lapsed.note == "已于 2026-05-28 到期")
        // The date is the user's calendar day, not UTC's.
        let tokyo = UsageSummary.make(usage: SubscriptionUsage(upload: 0, download: 1, total: 10, expires: Date(timeIntervalSince1970: 1_798_675_200 - 3600)),
                                      sessionTotal: 0, now: now, timeZone: TimeZone(identifier: "Asia/Tokyo")!)
        #expect(tokyo.note == "2026-12-31 到期")
    }

    @Test func aProfileKeepsItsUsageAndOlderDataStillLoads() throws {
        let usage = SubscriptionUsage(upload: 1, download: 2, total: 3, expires: Date(timeIntervalSince1970: 1_798_675_200))
        let profile = Profile(name: "sub", kind: .remote, remoteURL: URL(string: "https://sub.example.com/x"), usage: usage)
        let decoded = try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(profile))
        #expect(decoded == profile)
        #expect(decoded.usage == usage)
        // A profile written before the field existed.
        let old = #"{"id":"11111111-2222-3333-4444-555555555555","name":"old","kind":"remote","remoteURL":"https://sub.example.com/x","autoUpdate":true,"autoUpdateInterval":3600}"#
        let loaded = try JSONDecoder().decode(Profile.self, from: Data(old.utf8))
        #expect(loaded.usage == nil)
        #expect(loaded.name == "old")
    }
}

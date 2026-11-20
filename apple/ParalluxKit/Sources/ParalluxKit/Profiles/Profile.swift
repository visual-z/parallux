import Foundation

/// Where a profile's content comes from (glossary: 配置).
public enum ProfileKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case local
    /// A file in the user's iCloud Drive, read in place.
    case icloud
    /// A subscription URL, downloaded and cached locally.
    case remote

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .local: "本地"
        case .icloud: "iCloud"
        case .remote: "远程"
        }
    }
}

/// One sing-box configuration known to Parallux.
public struct Profile: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: ProfileKind
    /// iCloud: path relative to the iCloud Drive root.
    public var icloudPath: String?
    /// Remote: the subscription URL.
    public var remoteURL: URL?
    public var autoUpdate: Bool
    /// Seconds between automatic updates; see RemoteUpdate.clamp.
    public var autoUpdateInterval: TimeInterval
    public var lastUpdated: Date?
    /// Remote: what the subscription server said about traffic at the last
    /// download (`subscription-userinfo`); nil when it said nothing. Missing
    /// in data written before this field existed.
    public var usage: SubscriptionUsage?

    public init(id: UUID = UUID(), name: String, kind: ProfileKind, icloudPath: String? = nil, remoteURL: URL? = nil,
                autoUpdate: Bool = false, autoUpdateInterval: TimeInterval = RemoteUpdate.defaultInterval, lastUpdated: Date? = nil,
                usage: SubscriptionUsage? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.icloudPath = icloudPath
        self.remoteURL = remoteURL
        self.autoUpdate = autoUpdate
        self.autoUpdateInterval = autoUpdateInterval
        self.lastUpdated = lastUpdated
        self.usage = usage
    }
}

public enum RemoteUpdate {
    /// Why 12 h: SFM's default and the design's example ("每 12 小时更新").
    public static let defaultInterval: TimeInterval = 12 * 3600
    /// Why 15 min: subscription servers rate-limit; SFM's minimum.
    public static let minimumInterval: TimeInterval = 15 * 60
    /// Why 7 d: anything longer is effectively manual; keeps the picker finite.
    public static let maximumInterval: TimeInterval = 7 * 86400

    public static func clamp(_ interval: TimeInterval) -> TimeInterval {
        guard interval.isFinite else { return interval > 0 ? maximumInterval : minimumInterval }
        return min(max(interval, minimumInterval), maximumInterval)
    }

    public static func isDue(_ profile: Profile, now: Date) -> Bool {
        guard profile.kind == .remote, profile.autoUpdate else { return false }
        guard let last = profile.lastUpdated else { return true }
        return now.timeIntervalSince(last) >= clamp(profile.autoUpdateInterval)
    }
}

public enum BoundedDownload {
    /// Why 16 MiB: real subscriptions are tens to hundreds of KiB; the cap
    /// stops a wrong URL (a video, an ISO) from filling memory. Assumed value.
    public static let maxBytes = 16 << 20

    public struct TooLarge: Error, Equatable {
        public let limit: Int
    }

    /// Collects bytes and fails as soon as more than `limit` arrive.
    public static func collect<S: AsyncSequence>(_ bytes: S, limit: Int = maxBytes) async throws -> Data where S.Element == UInt8 {
        var data = Data()
        for try await byte in bytes {
            guard data.count < limit else { throw TooLarge(limit: limit) }
            data.append(byte)
        }
        return data
    }
}

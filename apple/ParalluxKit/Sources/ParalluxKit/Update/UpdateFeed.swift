import Foundation

/// Update channel (settings › 通用 › 更新渠道).
public enum UpdateChannel: String, CaseIterable, Identifiable, Sendable {
    case stable, beta
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .stable: "稳定版"
        case .beta: "测试版"
        }
    }

    public static let defaultsKey = "parallux.update.channel"
}

/// Where Sparkle should look for updates, from the build's Info.plist values.
public enum UpdateFeed {
    public enum Resolution: Equatable, Sendable {
        case feed(URL)
        /// This build has no feed or no public key: the updater stays off.
        case notConfigured
    }

    public static let stableKey = "SUFeedURL"
    public static let betaKey = "ParalluxUpdateBetaFeed"
    public static let publicKeyKey = "SUPublicEDKey"

    public static func resolve(channel: UpdateChannel, stable: String?, beta: String?, publicKey: String?) -> Resolution {
        .notConfigured
    }
}

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
        // Without a public key Sparkle cannot verify an update; without an
        // https stable feed there is nothing safe to check.
        guard let key = publicKey, usable(key) != nil, let stableURL = secureURL(stable) else { return .notConfigured }
        if channel == .beta, let betaURL = secureURL(beta) { return .feed(betaURL) }
        return .feed(stableURL)
    }

    /// nil for missing, empty or unexpanded build variables ("$(…)").
    private static func usable(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty, !value.hasPrefix("$(") else { return nil }
        return value
    }

    private static func secureURL(_ value: String?) -> URL? {
        guard let text = usable(value), let url = URL(string: text), url.scheme?.lowercased() == "https", url.host() != nil else { return nil }
        return url
    }
}

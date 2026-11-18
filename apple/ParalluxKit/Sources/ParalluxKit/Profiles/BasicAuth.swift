import Foundation

/// SFM #18: a subscription URL with "user:pass@" is fetched with HTTP Basic
/// auth instead, so the credentials never travel in the URL (or its logs).
public enum BasicAuth {
    public static func request(for url: URL, timeout: TimeInterval) -> URLRequest {
        URLRequest(url: url, timeoutInterval: timeout)
    }
}

extension Profile {
    /// Remote profiles are overwritten by every update, so editing them is refused.
    public var isReadOnly: Bool { false }
}

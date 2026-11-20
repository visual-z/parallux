import Foundation

/// SFM #18: a subscription URL with "user:pass@" is fetched with HTTP Basic
/// auth instead, so the credentials never travel in the URL (or its logs).
public enum BasicAuth {
    public static func request(for url: URL, timeout: TimeInterval) -> URLRequest {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let user = components.user else { return URLRequest(url: url, timeoutInterval: timeout) }
        let password = components.password ?? ""
        components.user = nil
        components.password = nil
        var request = URLRequest(url: components.url ?? url, timeoutInterval: timeout)
        let token = Data("\(user):\(password)".utf8).base64EncodedString()
        request.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
        return request
    }
}

extension Profile {
    /// Remote profiles are overwritten by every update, so editing them is refused.
    public var isReadOnly: Bool { kind == .remote }
}

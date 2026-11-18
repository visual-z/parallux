import Foundation

/// A sing-box endpoint's state, copied out of libbox (Tailscale, OpenVPN, OpenConnect).
public struct EndpointStatus: Equatable, Identifiable, Sendable {
    public enum Kind: String, Sendable { case tailscale, openVPN, openConnect }
    public var kind: Kind
    public var tag: String
    /// libbox `state` / `backendState`, e.g. "Running", "NeedsLogin", "connecting".
    public var state: String
    public var stateText: String
    public var error: String
    /// Tailscale: the login URL while NeedsLogin.
    public var authURL: String
    /// OpenVPN / OpenConnect: a pending challenge id.
    public var challengeID: String?
    public var id: String { "\(kind.rawValue):\(tag)" }

    public init(kind: Kind, tag: String, state: String, stateText: String = "", error: String = "", authURL: String = "", challengeID: String? = nil) {
        self.kind = kind
        self.tag = tag
        self.state = state
        self.stateText = stateText
        self.error = error
        self.authURL = authURL
        self.challengeID = challengeID
    }
}

public enum EndpointSummary {
    public struct Line: Equatable, Sendable {
        public var text: String
        public var needsUser: Bool
        public var isError: Bool
    }

    public static func line(_ status: EndpointStatus) -> Line { Line(text: "", needsUser: false, isError: false) }
}

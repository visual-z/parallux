/// The one-line state under "Parallux" in the panel, the overview subtitle
/// and the status item's tooltip.
public enum StatusLine {
    public enum Tunnel: Equatable, Sendable {
        case disconnected, connecting, connected, disconnecting
    }

    public enum Setup: Equatable, Sendable {
        case ready, awaitingApproval, failed(String)
    }

    /// - Parameters:
    ///   - actionError: the last failed user action (reading a profile…).
    ///   - coreError: the last error of the command-client streams.
    ///   - linkKind: the default link's kind ("Wi‑Fi"), if any.
    public static func text(setup: Setup, tunnel: Tunnel, actionError: String?, coreError: String?, linkKind: String?) -> String {
        ""
    }
}

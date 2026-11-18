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
        if let actionError { return actionError }
        switch setup {
        case .awaitingApproval: return "请在系统设置中允许网络扩展"
        case let .failed(message): return message
        case .ready: break
        }
        switch tunnel {
        case .connected:
            if let coreError { return "已连接，但读不到内核：\(coreError)" }
            return linkKind.map { "已连接 · 1 条线路（\($0)）" } ?? "已连接"
        case .connecting: return "正在连接…"
        case .disconnecting: return "正在断开…"
        case .disconnected: return "未连接"
        }
    }
}

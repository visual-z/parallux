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
    ///   - linkKind: the default link's kind ("Wi‑Fi"), or with several links
    ///     "<mode> · <n> 条线路".
    public static func text(setup: Setup, tunnel: Tunnel, actionError: String?, coreError: String?, linkKind: String?) -> String {
        if let actionError { return actionError }
        switch setup {
        case .awaitingApproval: return "需要在系统设置中授权"
        case let .failed(message): return message
        case .ready: break
        }
        switch tunnel {
        case .connected:
            if let coreError { return "已连接，但读不到内核：\(coreError)" }
            guard let linkKind else { return "已连接" }
            // Several links arrive pre-formatted as "<mode> · <n> 条线路".
            return linkKind.contains("条线路") ? "已连接 · \(linkKind)" : "已连接 · 1 条线路（\(linkKind)）"
        case .connecting: return "正在连接…"
        case .disconnecting: return "正在断开…"
        case .disconnected: return "未连接"
        }
    }
}

/// A one-shot action sent to the core, and what to say when it fails.
/// The sentence names the action; the
/// transport's own error text (gRPC status, deadlines) is not shown: it is
/// long, says nothing a user can act on, and once read as 「读不到内核」.
public enum CoreAction: CaseIterable, Sendable {
    case urlTest, selectOutbound, setRouteMode, closeConnection, clearLogs

    public var failure: String {
        switch self {
        case .urlTest: "延迟测试失败"
        case .selectOutbound: "切换节点失败"
        case .setRouteMode: "切换路由模式失败"
        case .closeConnection: "关闭连接失败"
        case .clearLogs: "清除日志失败"
        }
    }
}

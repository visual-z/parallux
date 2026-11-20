/// What the app does at launch about the extension macOS is running.
/// The app only reaches the Mach service of
/// its own build (decision 11), so after an update a running old extension is
/// unreachable until it is replaced.
public enum LaunchUpgrade: Equatable, Sendable {
    case none, replace, replaceAndReconnect

    public enum Status: Equatable, Sendable { case disconnected, connecting, connected, reasserting, disconnecting }

    public static func action(signed: Bool, status: Status, stale: Bool) -> LaunchUpgrade {
        guard signed, stale else { return .none }
        switch status {
        case .connected, .connecting, .reasserting: return .replaceAndReconnect
        case .disconnected, .disconnecting: return .replace
        }
    }
}

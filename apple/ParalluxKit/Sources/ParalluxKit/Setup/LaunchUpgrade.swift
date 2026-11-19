/// What the app does at launch about the extension macOS is running
/// (fix-stale-extension-on-launch). stub
public enum LaunchUpgrade: Equatable, Sendable {
    case none, replace, replaceAndReconnect

    public enum Status: Equatable, Sendable { case disconnected, connecting, connected, reasserting, disconnecting }

    public static func action(signed: Bool, status: Status, stale: Bool) -> LaunchUpgrade { .none }
}

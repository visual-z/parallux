/// When to reconnect a command-client stream the core closed (a reload ends
/// every subscription; fix-stream-reconnect). stub
public enum StreamRetry {
    public static let attemptLimit = 0
    public static func delay(after attempt: Int) -> Duration? { nil }
}

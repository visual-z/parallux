/// When to reconnect a command-client stream the core closed (a reload ends
/// every subscription).
public enum StreamRetry {
    /// Why 6: 0.25 + 0.5 + 1 + 2 + 4 + 8 ≈ 16 s covers a reload that downloads
    /// rule-sets again; after that the error is real and shown. Assumed value;
    /// measure with the time between "reload" and "core … started" in the log.
    public static let attemptLimit = 6

    /// nil: stop and show the error.
    public static func delay(after attempt: Int) -> Duration? {
        guard attempt >= 0, attempt < attemptLimit else { return nil }
        return .milliseconds(250 << attempt)
    }
}

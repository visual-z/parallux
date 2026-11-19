import Foundation

/// What the extension hands back from `startTunnel` (fix-tunnel-start-sandbox).
///
/// nesessionmanager decodes that error across XPC and only knows system
/// classes; gomobile's errors are `Universeerror`, which it drops, leaving the
/// session in "connecting" for good. So the one exit converts every error to a
/// plain NSError whose userInfo holds strings only.
public enum ProviderError {
    public static let domain = "io.github.visual-z.parallux.tunnel"
    /// Why 240: two lines of the status line show about 120 characters; the
    /// rest only matters in the log, which keeps the full text. Assumed value.
    public static let summaryLimit = 240

    public static func portable(_ error: Error) -> NSError {
        let source = error as NSError
        return NSError(domain: domain, code: source.code, userInfo: [NSLocalizedDescriptionKey: summary(source.localizedDescription)])
    }

    /// sing-box joins parallel failures with " | " (one per rule-set, say);
    /// keep the first and say how many more there were.
    public static func summary(_ raw: String) -> String {
        let parts = raw.components(separatedBy: " | ")
        var text = parts[0]
        let dropped = parts.count - 1
        let suffix = dropped > 0 ? "（另有 \(dropped) 处错误）" : ""
        let room = summaryLimit - suffix.count
        if text.count > room { text = String(text.prefix(max(0, room - 1))) + "…" }
        return text + suffix
    }
}

/// The extension's version as macOS reports it, against the one bundled in
/// this app (fix-tunnel-start-sandbox).
public struct ExtensionVersion: Equatable, Sendable {
    public var short: String
    public var build: String
    public init(short: String, build: String) {
        self.short = short
        self.build = build
    }

    /// Any difference, newer or older, means replace: the app only talks to
    /// the Mach service named after its own build (decision 11).
    public static func needsActivation(installed: ExtensionVersion?, bundled: ExtensionVersion) -> Bool {
        installed != bundled
    }
}

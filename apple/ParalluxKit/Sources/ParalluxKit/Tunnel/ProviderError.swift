import Foundation

/// What the extension hands back from `startTunnel` (fix-tunnel-start-sandbox).
/// stub
public enum ProviderError {
    public static let domain = "io.github.visual-z.parallux.tunnel"
    public static func portable(_ error: Error) -> NSError { error as NSError }
    public static let summaryLimit = 240
    public static func summary(_ raw: String) -> String { raw }
}

/// The extension's version as macOS reports it, against the one bundled in
/// this app (fix-tunnel-start-sandbox). stub
public struct ExtensionVersion: Equatable, Sendable {
    public var short: String
    public var build: String
    public init(short: String, build: String) {
        self.short = short
        self.build = build
    }

    public static func needsActivation(installed: ExtensionVersion?, bundled: ExtensionVersion) -> Bool { installed == nil }
}

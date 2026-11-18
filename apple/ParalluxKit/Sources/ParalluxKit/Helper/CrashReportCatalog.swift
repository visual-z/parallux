import Foundation

/// The crash reports libbox archives in `<working>/crash_reports`
/// (experimental/libbox/log.go), read by the root helper for the app.
public enum CrashReportCatalog {
    /// Why 50: a settings list, not an archive browser; older ones stay on disk.
    public static let maxListed = 50
    /// Why 256 KiB: a Go panic with all goroutines is tens of KiB; the cap
    /// keeps one XPC reply small. Assumed value.
    public static let maxReadBytes = 256 << 10

    public struct Entry: Codable, Equatable, Sendable {
        public var name: String
        public var size: Int64
        public var modified: Date
        public init(name: String, size: Int64, modified: Date) {
            self.name = name
            self.size = size
            self.modified = modified
        }
    }

    public struct Report: Codable, Equatable, Sendable {
        public var name: String
        public var text: String
        public var truncated: Bool
        public init(name: String, text: String, truncated: Bool) {
            self.name = name
            self.text = text
            self.truncated = truncated
        }
    }

    public enum Failure: Error, Equatable {
        case invalidName
        case notFound
    }

    /// Newest first, at most `limit`.
    public static func list(in directory: URL, limit: Int = maxListed) -> [Entry] { [] }

    /// `name` must be a single file name inside `directory`.
    public static func read(_ name: String, in directory: URL, limit: Int = maxReadBytes) throws -> Report {
        throw Failure.notFound
    }
}

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
    public static func list(in directory: URL, limit: Int = maxListed) -> [Entry] {
        guard limit > 0, let urls = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        let entries: [Entry] = urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true else { return nil }
            return Entry(name: url.lastPathComponent, size: Int64(values.fileSize ?? 0),
                         modified: values.contentModificationDate ?? .distantPast)
        }
        return Array(entries.sorted { $0.modified != $1.modified ? $0.modified > $1.modified : $0.name < $1.name }.prefix(limit))
    }

    /// `name` must be a single file name inside `directory`.
    public static func read(_ name: String, in directory: URL, limit: Int = maxReadBytes) throws -> Report {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\0") else {
            throw Failure.invalidName
        }
        let url = directory.appendingPathComponent(name)
        guard let handle = try? FileHandle(forReadingFrom: url) else { throw Failure.notFound }
        defer { try? handle.close() }
        // Read one byte past the cap to learn whether the file is longer.
        let data = (try? handle.read(upToCount: limit + 1)) ?? Data()
        let truncated = data.count > limit
        return Report(name: name, text: String(decoding: data.prefix(limit), as: UTF8.self), truncated: truncated)
    }
}

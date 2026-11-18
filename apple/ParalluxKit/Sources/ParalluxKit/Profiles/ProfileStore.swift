import Foundation
import Observation

/// The profile library: an ordered list, the selection, and one content file
/// per local or remote profile. Persisted as `index.json` plus `<id>.json`
/// in `directory`; every mutation writes through before returning.
@MainActor @Observable
public final class ProfileStore {
    public private(set) var profiles: [Profile] = []
    public private(set) var selectedID: UUID?
    public let directory: URL

    private struct Index: Codable {
        var profiles: [Profile]
        var selectedID: UUID?
    }

    private var indexURL: URL { directory.appendingPathComponent("index.json") }

    public init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: indexURL) {
            let index = try JSONDecoder().decode(Index.self, from: data)
            profiles = index.profiles
            selectedID = index.selectedID
            // Repair an index written by a crashed or older build.
            if let selectedID, !profiles.contains(where: { $0.id == selectedID }) {
                self.selectedID = profiles.first?.id
            }
        }
        checkInvariants()
    }

    public static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("io.github.visual-z.parallux/profiles", isDirectory: true)
    }

    public var selected: Profile? { profiles.first { $0.id == selectedID } }

    public func contentURL(for id: UUID) -> URL { directory.appendingPathComponent("\(id.uuidString).json") }

    /// Adds at the end; the first profile ever added becomes the selection.
    @discardableResult
    public func add(_ profile: Profile, content: String?) throws -> Profile {
        if let content { try write(content, to: contentURL(for: profile.id)) }
        profiles.append(profile)
        if selectedID == nil { selectedID = profile.id }
        try save()
        return profile
    }

    public func update(_ profile: Profile) throws {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[index] = profile
        try save()
    }

    /// Removes the profile and its content; a deleted selection moves to the
    /// next profile, else the previous one, else none.
    public func delete(_ id: UUID) throws {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles.remove(at: index)
        if selectedID == id {
            selectedID = index < profiles.count ? profiles[index].id : profiles.last?.id
        }
        try save()
        try? FileManager.default.removeItem(at: contentURL(for: id))
    }

    /// Same contract as SwiftUI's onMove.
    public func move(fromOffsets source: IndexSet, toOffset destination: Int) throws {
        let moving = source.map { profiles[$0] }
        let before = source.filter { $0 < destination }.count
        profiles = profiles.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        profiles.insert(contentsOf: moving, at: destination - before)
        try save()
    }

    public func select(_ id: UUID?) throws {
        guard id == nil || profiles.contains(where: { $0.id == id }) else { return }
        selectedID = id
        try save()
    }

    /// Stored content of a local or remote profile; nil for iCloud profiles,
    /// whose content lives in iCloud Drive.
    public func content(of id: UUID) throws -> String? {
        let url = contentURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try String(contentsOf: url, encoding: .utf8)
    }

    public func setContent(_ content: String, for id: UUID) throws {
        try write(content, to: contentURL(for: id))
    }

    private func write(_ content: String, to url: URL) throws {
        try Data(content.utf8).write(to: url, options: .atomic)
    }

    private func save() throws {
        checkInvariants()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(Index(profiles: profiles, selectedID: selectedID)).write(to: indexURL, options: .atomic)
    }

    /// INV-1 (docs/INVARIANTS.md).
    func checkInvariants() {
        assert(selectedID == nil || profiles.contains { $0.id == selectedID }, "INV-1: selection outside the library")
    }
}

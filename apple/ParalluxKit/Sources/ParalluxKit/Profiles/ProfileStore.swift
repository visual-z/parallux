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

    public init(directory: URL) throws {
        self.directory = directory
    }

    public static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("io.github.visual-z.parallux/profiles", isDirectory: true)
    }

    public var selected: Profile? { profiles.first { $0.id == selectedID } }

    public func contentURL(for id: UUID) -> URL { directory.appendingPathComponent("\(id.uuidString).json") }

    @discardableResult
    public func add(_ profile: Profile, content: String?) throws -> Profile { profile }
    public func update(_ profile: Profile) throws {}
    public func delete(_ id: UUID) throws {}
    public func move(fromOffsets source: IndexSet, toOffset destination: Int) throws {}
    public func select(_ id: UUID?) throws {}
    public func content(of id: UUID) throws -> String? { nil }
    public func setContent(_ content: String, for id: UUID) throws {}

    /// INV-1 (docs/INVARIANTS.md).
    func checkInvariants() {}
}

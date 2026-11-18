import Foundation
import Testing
@testable import ParalluxKit

@MainActor private func temporaryStore() throws -> (ProfileStore, URL) {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parallux-profiles-\(UUID().uuidString)")
    return (try ProfileStore(directory: directory), directory)
}

@MainActor @Suite struct ProfileStoreTests {
    @Test func aStoreReopensWithTheSameProfilesAndSelection() throws {
        let (store, directory) = try temporaryStore()
        let local = try store.add(Profile(name: "本地", kind: .local), content: "{}")
        let remote = try store.add(Profile(name: "主力机场", kind: .remote, remoteURL: URL(string: "https://example.com/sub")!,
                                           autoUpdate: true, autoUpdateInterval: 3600, lastUpdated: Date(timeIntervalSince1970: 1_800_000_000)),
                                   content: #"{"outbounds":[]}"#)
        let cloud = try store.add(Profile(name: "云", kind: .icloud, icloudPath: "sing-box/a.json"), content: nil)
        try store.move(fromOffsets: [2], toOffset: 0)
        try store.select(remote.id)

        let reopened = try ProfileStore(directory: directory)
        #expect(reopened.profiles == [cloud, local, remote])
        #expect(reopened.selectedID == remote.id)
        #expect(try reopened.content(of: remote.id) == #"{"outbounds":[]}"#)
        #expect(try reopened.content(of: local.id) == "{}")
    }

    @Test func deletingTheSelectedProfileSelectsANeighbour() throws {
        let (store, _) = try temporaryStore()
        let a = try store.add(Profile(name: "a", kind: .local), content: "{}")
        let b = try store.add(Profile(name: "b", kind: .local), content: "{}")
        let c = try store.add(Profile(name: "c", kind: .local), content: "{}")
        try store.select(b.id)
        try store.delete(b.id)
        #expect(store.selectedID == c.id, "the next one")
        #expect(!FileManager.default.fileExists(atPath: store.contentURL(for: b.id).path))
        try store.delete(c.id)
        #expect(store.selectedID == a.id, "no next, so the previous one")
        try store.delete(a.id)
        #expect(store.selectedID == nil)
        #expect(store.profiles.isEmpty)
    }

    @Test func anyOperationSequenceKeepsTheSelectionValid() throws {
        let (store, _) = try temporaryStore()
        var rng = SplitMix64(seed: 0xC0FFEE)
        for _ in 0..<500 {
            let ids = store.profiles.map(\.id)
            switch rng.int(5) {
            case 0: try store.add(Profile(name: rng.string(), kind: .local), content: "{}")
            case 1: if let id = ids.randomElement(using: &rng) { try store.delete(id) }
            case 2: if !ids.isEmpty { try store.move(fromOffsets: [rng.int(ids.count)], toOffset: rng.int(ids.count + 1)) }
            case 3: try store.select(rng.bool() ? ids.randomElement(using: &rng) : nil)
            default:
                if var profile = store.profiles.randomElement(using: &rng) {
                    profile.name = rng.string()
                    try store.update(profile)
                }
            }
            if let selected = store.selectedID {
                #expect(store.profiles.contains { $0.id == selected })
            }
        }
    }

    @Test func movingAProfileKeepsEveryOtherInOrder() throws {
        let (store, _) = try temporaryStore()
        for index in 0..<6 { try store.add(Profile(name: "p\(index)", kind: .local), content: "{}") }
        try #require(store.profiles.count == 6)
        var rng = SplitMix64(seed: 7)
        for _ in 0..<200 {
            let before = store.profiles.map(\.id)
            let source = rng.int(before.count)
            let moved = before[source]
            try store.move(fromOffsets: [source], toOffset: rng.int(before.count + 1))
            let after = store.profiles.map(\.id)
            #expect(Set(after) == Set(before))
            #expect(after.filter { $0 != moved } == before.filter { $0 != moved })
        }
    }
}

@Suite struct RemoteUpdateTests {
    @Test func remoteUpdateIsDueOnlyAfterItsInterval() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        var profile = Profile(name: "r", kind: .remote, remoteURL: URL(string: "https://example.com")!, autoUpdate: true,
                              autoUpdateInterval: 3600, lastUpdated: now.addingTimeInterval(-3599))
        #expect(!RemoteUpdate.isDue(profile, now: now))
        profile.lastUpdated = now.addingTimeInterval(-3600)
        #expect(RemoteUpdate.isDue(profile, now: now))
        profile.lastUpdated = nil
        #expect(RemoteUpdate.isDue(profile, now: now), "never updated")
        profile.autoUpdate = false
        #expect(!RemoteUpdate.isDue(profile, now: now), "auto update off")
        profile.autoUpdate = true
        profile.kind = .local
        #expect(!RemoteUpdate.isDue(profile, now: now), "only remote profiles update")
        // An interval below the floor behaves like the floor.
        profile = Profile(name: "r", kind: .remote, autoUpdate: true, autoUpdateInterval: 0, lastUpdated: now.addingTimeInterval(-60))
        #expect(!RemoteUpdate.isDue(profile, now: now))
        #expect(RemoteUpdate.clamp(0) == RemoteUpdate.minimumInterval)
        #expect(RemoteUpdate.clamp(1) == RemoteUpdate.minimumInterval)
        #expect(RemoteUpdate.clamp(.infinity) == RemoteUpdate.maximumInterval)
        #expect(RemoteUpdate.clamp(3600) == 3600)
    }
}

@Suite struct BoundedDownloadTests {
    private struct Bytes: AsyncSequence {
        typealias Element = UInt8
        let count: Int
        struct AsyncIterator: AsyncIteratorProtocol {
            var remaining: Int
            mutating func next() async -> UInt8? {
                guard remaining > 0 else { return nil }
                remaining -= 1
                return 0x7B
            }
        }
        func makeAsyncIterator() -> AsyncIterator { AsyncIterator(remaining: count) }
    }

    @Test func aDownloadLargerThanTheCapIsRejected() async throws {
        await #expect(throws: BoundedDownload.TooLarge(limit: 10)) {
            try await BoundedDownload.collect(Bytes(count: 11), limit: 10)
        }
        #expect(try await BoundedDownload.collect(Bytes(count: 10), limit: 10).count == 10)
        #expect(try await BoundedDownload.collect(Bytes(count: 0), limit: 10).isEmpty)
        #expect(try await BoundedDownload.collect(Bytes(count: 1), limit: 10).count == 1)
    }
}

extension SplitMix64: RandomNumberGenerator {}

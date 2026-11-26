import Foundation
import Libbox
import Observation
import os
import ParalluxKit

/// Reads, imports, validates and updates profiles; ProfileStore keeps them.
@MainActor @Observable
final class ProfileService {
    let store: ProfileStore
    private(set) var updating: Set<UUID> = []
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private let log = Logger(subsystem: "io.github.visual-z.parallux", category: "profiles")

    /// Why 10 min: a check is a date comparison; the shortest update interval
    /// is 15 min, so a due profile is at most 10 min late.
    static let dueCheckInterval: TimeInterval = 10 * 60
    /// Why 30 s: a subscription is a small file; a hung server must not keep
    /// "updating" spinning forever. Assumed value.
    static let requestTimeout: TimeInterval = 30

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    init() {
        do {
            store = try ProfileStore(directory: ProfileStore.defaultDirectory)
        } catch {
            // A corrupt index must not stop the app; start empty in a fresh
            // directory and keep the old one for inspection.
            let fallback = ProfileStore.defaultDirectory.deletingLastPathComponent()
                .appendingPathComponent("profiles-recovered-\(Int(Date().timeIntervalSince1970))")
            store = try! ProfileStore(directory: fallback)
        }
    }

    func startAutoUpdate() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Self.dueCheckInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateDueProfiles() }
        }
        updateDueProfiles()
    }

    func updateDueProfiles() {
        for profile in store.profiles where RemoteUpdate.isDue(profile, now: Date()) {
            Task { try? await update(profile) }
        }
    }

    // MARK: content

    static var iCloudDriveRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
    }

    func content(of profile: Profile) async throws -> String {
        switch profile.kind {
        case .local, .remote:
            guard let content = try store.content(of: profile.id) else { throw Failure(message: "配置「\(profile.name)」没有内容") }
            return content
        case .icloud:
            guard let path = profile.icloudPath else { throw Failure(message: "配置「\(profile.name)」没有 iCloud 路径") }
            let url = Self.iCloudDriveRoot.appendingPathComponent(path)
            return try await Task.detached { try Self.coordinatedRead(url) }.value
        }
    }

    /// NSFileCoordinator makes iCloud Drive download a file that is only in the cloud.
    nonisolated private static func coordinatedRead(_ url: URL) throws -> String {
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        var coordinationError: NSError?
        var result: Result<String, Error> = .failure(Failure(message: "无法读取 \(url.lastPathComponent)"))
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { readable in
            result = Result { try String(contentsOf: readable, encoding: .utf8) }
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }

    func save(_ content: String, for profile: Profile) async throws {
        try Self.validate(content)
        switch profile.kind {
        case .local, .remote:
            try store.setContent(content, for: profile.id)
        case .icloud:
            guard let path = profile.icloudPath else { return }
            try Data(content.utf8).write(to: Self.iCloudDriveRoot.appendingPathComponent(path), options: .atomic)
        }
    }

    /// The same check the extension's libbox will run, so a broken profile
    /// is rejected here rather than when the tunnel starts.
    static func validate(_ content: String) throws {
        var error: NSError?
        LibboxCheckConfig(content, &error)
        if let error { throw Failure(message: error.localizedDescription) }
    }

    static func format(_ content: String) throws -> String {
        var error: NSError?
        let box = LibboxFormatConfig(content, &error)
        if let error { throw Failure(message: error.localizedDescription) }
        return box?.value ?? content
    }

    // MARK: adding

    func addLocal(name: String, content: String) throws {
        try Self.validate(content)
        try store.add(Profile(name: name, kind: .local), content: content)
    }

    /// .json adds a local profile; .bpf (SFM's binary profile) restores
    /// local or remote profiles with their update settings.
    func importFile(_ url: URL) async throws {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        if url.pathExtension.lowercased() == "bpf" {
            var error: NSError?
            guard let content = LibboxDecodeProfileContent(try Data(contentsOf: url), &error), error == nil else {
                throw Failure(message: "不是有效的 .bpf 文件：\(error?.localizedDescription ?? "")")
            }
            try Self.validate(content.config)
            if content.type == LibboxProfileTypeRemote, let remote = URL(string: content.remotePath) {
                let interval = content.autoUpdateInterval > 0 ? TimeInterval(content.autoUpdateInterval) * 60 : RemoteUpdate.defaultInterval
                try store.add(Profile(name: content.name, kind: .remote, remoteURL: remote, autoUpdate: content.autoUpdate,
                                      autoUpdateInterval: RemoteUpdate.clamp(interval),
                                      lastUpdated: content.lastUpdated > 0 ? Date(timeIntervalSince1970: TimeInterval(content.lastUpdated)) : nil),
                              content: content.config)
            } else {
                try store.add(Profile(name: content.name, kind: .local), content: content.config)
            }
            return
        }
        let content = try String(contentsOf: url, encoding: .utf8)
        try addLocal(name: url.deletingPathExtension().lastPathComponent, content: content)
    }

    /// SFM-compatible .bpf bytes (libbox ProfileContent.encode).
    func exportBPF(_ profile: Profile) async throws -> Data {
        let content = LibboxProfileContent()
        content.name = profile.name
        content.config = try await self.content(of: profile)
        switch profile.kind {
        case .remote:
            content.type = LibboxProfileTypeRemote
            content.remotePath = profile.remoteURL?.absoluteString ?? ""
            content.autoUpdate = profile.autoUpdate
            // SFM stores the interval in minutes.
            content.autoUpdateInterval = Int32(profile.autoUpdateInterval / 60)
            content.lastUpdated = Int64(profile.lastUpdated?.timeIntervalSince1970 ?? 0)
        case .icloud:
            content.type = LibboxProfileTypeiCloud
        case .local:
            content.type = LibboxProfileTypeLocal
        }
        guard let data = content.encode() else { throw Failure(message: "无法编码 .bpf") }
        return data
    }

    func addICloud(name: String, fileURL: URL) async throws {
        let root = Self.iCloudDriveRoot.standardizedFileURL.path
        let path = fileURL.standardizedFileURL.path
        guard path.hasPrefix(root + "/") else { throw Failure(message: "请选择 iCloud 云盘里的文件") }
        let profile = Profile(name: name, kind: .icloud, icloudPath: String(path.dropFirst(root.count + 1)))
        try Self.validate(try await content(of: profile))
        try store.add(profile, content: nil)
    }

    func addRemote(name: String, url: URL, autoUpdate: Bool, interval: TimeInterval) async throws {
        let (content, usage) = try await Self.download(url)
        try Self.validate(content)
        try store.add(Profile(name: name, kind: .remote, remoteURL: url, autoUpdate: autoUpdate,
                              autoUpdateInterval: RemoteUpdate.clamp(interval), lastUpdated: Date(), usage: usage), content: content)
    }

    /// Accepts SFM's `sing-box://import-remote-profile?url=…#name` links.
    func importLink(_ link: String) async throws {
        var error: NSError?
        guard let parsed = LibboxParseRemoteProfileImportLink(link, &error), error == nil, let url = URL(string: parsed.url) else {
            throw Failure(message: error?.localizedDescription ?? "不是有效的导入链接")
        }
        try await addRemote(name: parsed.name.isEmpty ? (url.host() ?? "远程配置") : parsed.name, url: url,
                            autoUpdate: true, interval: RemoteUpdate.defaultInterval)
    }

    static func shareLink(for profile: Profile) -> String? {
        guard profile.kind == .remote, let url = profile.remoteURL else { return nil }
        return LibboxGenerateRemoteProfileImportLink(profile.name, url.absoluteString)
    }

    // MARK: updating

    func update(_ profile: Profile) async throws {
        guard profile.kind == .remote, let url = profile.remoteURL, !updating.contains(profile.id) else { return }
        updating.insert(profile.id)
        defer { updating.remove(profile.id) }
        do {
            let (content, usage) = try await Self.download(url)
            try Self.validate(content)
            try store.setContent(content, for: profile.id)
            var updated = store.profiles.first { $0.id == profile.id } ?? profile
            updated.lastUpdated = Date()
            // The figures of this download replace the last ones, also when
            // the server stopped sending them: a stale quota would mislead.
            // A failed update never gets here and keeps what it had.
            updated.usage = usage
            try store.update(updated)
        } catch {
            log.error("update \(profile.name, privacy: .private) failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    /// The profile, and what the server's `subscription-userinfo` header
    /// says about the account's traffic (nil when it sends none). The header
    /// comes with the download, so usage costs no extra request against
    /// servers that rate-limit.
    static func download(_ url: URL) async throws -> (content: String, usage: SubscriptionUsage?) {
        var request = BasicAuth.request(for: url, timeout: requestTimeout)
        request.setValue("Parallux (sing-box)", forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        let http = response as? HTTPURLResponse
        if let http, !(200..<300).contains(http.statusCode) {
            throw Failure(message: "服务器返回 \(http.statusCode)")
        }
        // value(forHTTPHeaderField:) matches the name case-insensitively.
        let usage = SubscriptionUsage.parse(header: http?.value(forHTTPHeaderField: "subscription-userinfo"))
        do {
            let data = try await BoundedDownload.collect(bytes)
            return (String(decoding: data, as: UTF8.self), usage)
        } catch is BoundedDownload.TooLarge {
            throw Failure(message: "下载内容超过 \(BoundedDownload.maxBytes >> 20) MB，不像是配置文件")
        }
    }
}

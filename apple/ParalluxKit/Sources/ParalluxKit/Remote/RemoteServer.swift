import Foundation

/// Another device's sing-box command server (SFM Remote Control).
public struct RemoteServer: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    /// As entered, normalised for display (RemoteServerAddress.normalize).
    public var address: String

    public init(id: UUID = UUID(), name: String, address: String) {
        self.id = id
        self.name = name
        self.address = RemoteServerAddress.normalize(address)
    }
}

/// SFM Library/Database/RemoteServer.swift normalizeURL / connectURL.
public enum RemoteServerAddress {
    private static func trimmed(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") { value.removeLast() }
        return value
    }

    /// For display: no trailing slash, no default http:// (https:// is kept).
    public static func normalize(_ raw: String) -> String {
        let value = trimmed(raw)
        if value.lowercased().hasPrefix("http://") { return String(value.dropFirst("http://".count)) }
        return value
    }

    /// For libbox: a scheme is required, defaulting to http.
    public static func connectURL(_ raw: String) -> String {
        let value = trimmed(raw)
        guard !value.isEmpty else { return "" }
        let lower = value.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") { return value }
        return "http://" + value
    }
}

/// The remote device list in UserDefaults; secrets in a SecretStore.
@MainActor
public final class RemoteServerStore {
    public private(set) var servers: [RemoteServer] = []
    private let defaults: UserDefaults
    private let secrets: any SecretStore
    public static let defaultsKey = "parallux.remote-servers"

    public init(defaults: UserDefaults, secrets: any SecretStore) {
        self.defaults = defaults
        self.secrets = secrets
        if let data = defaults.data(forKey: Self.defaultsKey),
           let servers = try? JSONDecoder().decode([RemoteServer].self, from: data) {
            self.servers = servers
        }
    }

    public func add(_ server: RemoteServer, secret: String) throws {
        try secrets.setSecret(secret, for: server.id)
        servers.removeAll { $0.id == server.id }
        servers.append(server)
        save()
    }

    public func remove(_ id: UUID) {
        servers.removeAll { $0.id == id }
        save()
        secrets.removeSecret(for: id)
    }

    public func secret(for id: UUID) -> String? { secrets.secret(for: id) }

    private func save() {
        if let data = try? JSONEncoder().encode(servers) { defaults.set(data, forKey: Self.defaultsKey) }
    }
}

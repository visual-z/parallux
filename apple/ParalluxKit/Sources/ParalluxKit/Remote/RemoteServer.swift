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
    public static func normalize(_ raw: String) -> String { raw }
    public static func connectURL(_ raw: String) -> String { raw }
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
    }

    public func add(_ server: RemoteServer, secret: String) throws {}
    public func remove(_ id: UUID) {}
    public func secret(for id: UUID) -> String? { nil }
}

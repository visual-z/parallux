import Foundation
import Testing
@testable import ParalluxKit

private final class Secrets: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [UUID: String] = [:]
    func secret(for id: UUID) -> String? { lock.withLock { values[id] } }
    func setSecret(_ secret: String, for id: UUID) throws { lock.withLock { values[id] = secret } }
    func removeSecret(for id: UUID) { lock.withLock { values[id] = nil } }
    var count: Int { lock.withLock { values.count } }
}

@Suite struct RemoteServerAddressTests {
    @Test func remoteAddressesNormalizeLikeSFM() {
        #expect(RemoteServerAddress.normalize("  http://192.168.1.20:9090/ ") == "192.168.1.20:9090")
        #expect(RemoteServerAddress.normalize("HTTP://host:1//") == "host:1")
        #expect(RemoteServerAddress.normalize("https://host:1/") == "https://host:1")
        #expect(RemoteServerAddress.normalize("") == "")
        #expect(RemoteServerAddress.connectURL("192.168.1.20:9090") == "http://192.168.1.20:9090")
        #expect(RemoteServerAddress.connectURL("https://host:1/") == "https://host:1")
        #expect(RemoteServerAddress.connectURL("http://host:1") == "http://host:1")
        #expect(RemoteServerAddress.connectURL("  ") == "")
        #expect(RemoteServer(name: "m", address: "http://h:1/").address == "h:1")
    }
}

@MainActor @Suite struct RemoteServerStoreTests {
    @Test func remoteServerListsNeverCarryTheSecret() throws {
        let defaults = try #require(UserDefaults(suiteName: "parallux-remote-\(UUID().uuidString)"))
        let secrets = Secrets()
        let store = RemoteServerStore(defaults: defaults, secrets: secrets)
        let server = RemoteServer(name: "家里的 Mac mini", address: "192.168.1.20:9090")
        try store.add(server, secret: "remote-secret-canary")
        #expect(store.secret(for: server.id) == "remote-secret-canary")
        let stored = try #require(defaults.data(forKey: RemoteServerStore.defaultsKey))
        #expect(!String(decoding: stored, as: UTF8.self).contains("remote-secret-canary"))
        let reopened = RemoteServerStore(defaults: defaults, secrets: secrets)
        #expect(reopened.servers == [server])
        reopened.remove(server.id)
        #expect(reopened.servers.isEmpty)
        #expect(secrets.count == 0)
    }
}

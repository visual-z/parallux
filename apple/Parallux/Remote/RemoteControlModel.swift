import Foundation
import Observation
import ParalluxKit

/// Remote devices and which one, if any, the interface is viewing.
@MainActor @Observable
final class RemoteControlModel {
    private(set) var servers: [RemoteServer] = []
    private(set) var active: RemoteServer?
    private(set) var reachable: [UUID: Bool] = [:]
    @ObservationIgnored private let store = RemoteServerStore(defaults: .standard, secrets: KeychainSecretStore(service: KeychainSecretStore.remoteService))

    init() { servers = store.servers }

    var isRemote: Bool { active != nil }

    func add(name: String, address: String, secret: String) throws {
        let server = RemoteServer(name: name.isEmpty ? RemoteServerAddress.normalize(address) : name, address: address)
        try store.add(server, secret: secret)
        servers = store.servers
        probe(server)
    }

    func remove(_ id: UUID) {
        if active?.id == id { activate(nil, session: nil) }
        store.remove(id)
        servers = store.servers
    }

    func probe(_ server: RemoteServer) {
        let remote = CommandTarget.Remote(server: server, secret: store.secret(for: server.id) ?? "")
        Task.detached {
            let ok = CommandTarget.probe(remote)
            await MainActor.run { self.reachable[server.id] = ok }
        }
    }

    /// Switches every page to `server` (nil: this Mac) and restarts the core streams.
    /// Back on this Mac, the session runs only if the local tunnel is connected.
    func activate(_ server: RemoteServer?, session: CoreSession?, localConnected: Bool = false) {
        active = server
        CommandTarget.set(server.map { CommandTarget.Remote(server: $0, secret: store.secret(for: $0.id) ?? "") })
        guard let session else { return }
        session.stop()
        if server != nil || localConnected { session.start() }
    }
}

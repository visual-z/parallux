import Foundation
import Network
import Observation
import ParalluxKit

/// The aggregation servers and their reachability, shared by the servers page and the panel.
@MainActor @Observable
final class AggregationServersModel {
    private(set) var servers: [AggregationServer] = []
    /// TCP connect time per server, measured from the app.
    private(set) var latency: [UUID: Int] = [:]
    private(set) var unreachable: Set<UUID> = []
    @ObservationIgnored private let store = AggregationServerStore(defaults: .standard, secrets: KeychainSecretStore())

    /// Why 3 s: a reachable VPS answers in well under a second; longer means unusable for 叠加. Assumed.
    static let pingTimeout: TimeInterval = 3

    init() { servers = store.servers }

    func add(link: String) throws -> AggregationServer {
        let parsed = try AggregationServerLink.parse(link)
        try store.add(parsed.server, psk: parsed.psk)
        servers = store.servers
        ping(parsed.server)
        return parsed.server
    }

    func rename(_ id: UUID, to name: String) {
        guard var server = servers.first(where: { $0.id == id }) else { return }
        server.name = name
        store.update(server)
        servers = store.servers
    }

    func remove(_ id: UUID) {
        store.remove(id)
        servers = store.servers
        latency[id] = nil
    }

    func psk(for id: UUID) -> String? { store.psk(for: id) }

    func pingAll() { servers.forEach(ping) }

    private func ping(_ server: AggregationServer) {
        guard let port = NWEndpoint.Port(rawValue: server.port) else { return }
        let connection = NWConnection(host: NWEndpoint.Host(server.host), port: port, using: .tcp)
        let started = Date()
        let id = server.id
        let finish: @Sendable (Int?) -> Void = { [weak self] millis in
            connection.cancel()
            Task { @MainActor in
                guard let self else { return }
                if let millis { self.latency[id] = millis; self.unreachable.remove(id) } else { self.latency[id] = nil; self.unreachable.insert(id) }
            }
        }
        let once = Once()
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready: once.run { finish(Int(Date().timeIntervalSince(started) * 1000)) }
            case .failed, .cancelled: once.run { finish(nil) }
            default: break
            }
        }
        connection.start(queue: .global())
        DispatchQueue.global().asyncAfter(deadline: .now() + Self.pingTimeout) { once.run { finish(nil) } }
    }

    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false
        func run(_ body: () -> Void) {
            lock.lock()
            guard !done else { lock.unlock(); return }
            done = true
            lock.unlock()
            body()
        }
    }

    func summary(_ id: UUID?) -> String? {
        guard let id, let server = servers.first(where: { $0.id == id }) else { return nil }
        if let ms = latency[id] { return "\(server.name) · \(ms) ms" }
        return unreachable.contains(id) ? "\(server.name) · 不可达" : server.name
    }
}

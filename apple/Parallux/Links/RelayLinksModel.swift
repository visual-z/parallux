import Foundation
import Observation
import ParalluxKit

/// The relay links (glossary: 中继线路) and their carriers, shared by the
/// links page, the panel and AppModel.compose.
@MainActor @Observable
final class RelayLinksModel {
    private(set) var relays: [RelayLink] = []
    /// Relays whose carrier is being looked for right now.
    private(set) var detecting: Set<UUID> = []
    /// Relays whose key is in the Keychain. Read when the list changes, so
    /// rows do not query the Keychain on every redraw.
    private(set) var keyed: Set<UUID> = []
    @ObservationIgnored private let store = RelayLinkStore(defaults: .standard, secrets: KeychainSecretStore(service: KeychainSecretStore.relayService))

    init() { reload() }

    private func reload() {
        relays = store.relays
        keyed = Set(relays.map(\.id).filter { store.key(for: $0) != nil })
    }

    /// The relays as links, in the order they were added.
    var links: [LinkInterface] { relays.map(\.link) }

    func relay(named linkName: String) -> RelayLink? { relays.first { $0.linkName == linkName } }

    func key(for id: UUID) -> String? { store.key(for: id) }

    /// Adds every link in `text` (one per line). A line that is not a relay
    /// link adds nothing at all (RelayLinkURL.parseAll); the store's limit
    /// may stop it part-way, which the thrown error says.
    func add(text: String) throws -> [RelayLink] {
        let parsed = try RelayLinkURL.parseAll(text)
        defer { reload() }
        return try parsed.map { try store.add($0.relay, key: $0.key) }
    }

    func remove(_ id: UUID) {
        store.remove(id)
        reload()
    }

    /// Looks for the carrier of every relay that has none or whose carrier
    /// is no longer among `physical` (`force`: of every relay). Returns
    /// whether any carrier changed, so the caller can recompose.
    ///
    /// A relay host that answers over no interface keeps the carrier it had
    /// as long as that interface still exists: the host being down for a
    /// moment is not a reason to forget how to reach it.
    func detectCarriers(physical: [LinkInterface], force: Bool = false) async -> Bool {
        let names = physical.map(\.name)
        let pending = relays.filter { relay in
            guard !detecting.contains(relay.id) else { return false }
            guard let carrier = relay.carrier else { return true }
            return force || !names.contains(carrier)
        }
        guard !pending.isEmpty else { return false }
        detecting.formUnion(pending.map(\.id))
        var changed = false
        // At most RelayLinkStore.limit probes at once, each bounded by
        // RelayCarrier.timeout per interface.
        await withTaskGroup(of: (RelayLink, String?).self) { group in
            for relay in pending {
                group.addTask { (relay, await Self.find(host: relay.host, port: relay.port, interfaces: names)) }
            }
            for await (relay, found) in group {
                detecting.remove(relay.id)
                let carrier = found ?? relay.carrier.flatMap { names.contains($0) ? $0 : nil }
                if carrier != relay.carrier {
                    store.setCarrier(carrier, for: relay.id)
                    changed = true
                }
            }
        }
        reload()
        return changed
    }

    /// RelayCarrier.find blocks in poll(); it runs on a GCD thread so it
    /// never holds one of the cooperative pool's.
    private nonisolated static func find(host: String, port: UInt16, interfaces: [String]) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: RelayCarrier.find(host: host, port: port, interfaces: interfaces))
            }
        }
    }
}

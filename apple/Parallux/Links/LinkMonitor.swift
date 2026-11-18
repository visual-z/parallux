import Foundation
import Network
import Observation
import ParalluxKit
import SystemConfiguration

/// Every candidate link on this Mac (Wi‑Fi, Ethernet, iPhone USB, bridges to
/// a second Wi‑Fi). NWPathMonitor only signals "something changed"; the list
/// itself is re-read from getifaddrs and SystemConfiguration, which see every
/// interface, not just the preferred path.
@MainActor @Observable
final class LinkMonitor {
    private(set) var links: [LinkInterface] = []
    /// Egress IP per interface from the last probe run (links page warning).
    var egress: [String: String] = [:]
    @ObservationIgnored private let monitor = NWPathMonitor()

    init() {
        refresh()
        monitor.pathUpdateHandler = { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        monitor.start(queue: DispatchQueue(label: "parallux.link-monitor"))
    }

    func refresh() {
        let found = LinkInventory.classify(Self.readRaw())
        if found != links { links = found }
    }

    nonisolated static func readRaw() -> [LinkInventory.Raw] {
        var system: [String: (type: String?, name: String?)] = [:]
        if let all = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] {
            for interface in all {
                guard let bsd = SCNetworkInterfaceGetBSDName(interface) as String? else { continue }
                system[bsd] = (SCNetworkInterfaceGetInterfaceType(interface) as String?,
                               SCNetworkInterfaceGetLocalizedDisplayName(interface) as String?)
            }
        }
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }
        var flags: [String: UInt32] = [:]
        var ipv4: [String: String] = [:]
        var order: [String] = []
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let name = String(cString: entry.pointee.ifa_name)
            if flags[name] == nil { order.append(name) }
            flags[name] = entry.pointee.ifa_flags
            if let address = entry.pointee.ifa_addr, address.pointee.sa_family == sa_family_t(AF_INET), ipv4[name] == nil {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    ipv4[name] = String(cString: host)
                }
            }
        }
        return order.map { name in
            LinkInventory.Raw(name: name, scType: system[name]?.type, scDisplayName: system[name]?.name,
                              flags: flags[name] ?? 0, ipv4: ipv4[name])
        }
    }
}

/// Per-link rates while the tunnel is up: polls the extension's linkStats
/// once a second (the same cadence as the core's status stream).
@MainActor @Observable
final class LinkStatsPoller {
    private(set) var groups: [LinkGroupStat] = []
    private(set) var rates: [String: LinkRates.Rate] = [:]
    @ObservationIgnored private var task: Task<Void, Never>?

    /// Why 1 s: matches the status stream; per-link rates are shown at most once a second.
    static let interval: Duration = .seconds(1)

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            var previous: [LinkGroupStat] = []
            var last = ContinuousClock.now
            while !Task.isCancelled {
                let json = await Task.detached { CommandXPCDialer.linkStats() }.value
                let current = LinkGroupStat.decode(json)
                let now = ContinuousClock.now
                let seconds = Double((now - last).components.seconds) + Double((now - last).components.attoseconds) / 1e18
                let rates = LinkRates.rates(previous: previous, current: current, interval: seconds)
                previous = current
                last = now
                guard let self else { return }
                self.groups = current
                self.rates = rates
                try? await Task.sleep(for: Self.interval)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        groups = []
        rates = [:]
    }

    /// Health of a link outbound tag in the first aggregate that has it.
    func link(_ tag: String) -> LinkGroupStat.Link? {
        for group in groups { if let link = group.links.first(where: { $0.tag == tag }) { return link } }
        return nil
    }
}

/// LinkSettings persisted on every change.
@MainActor @Observable
final class LinkSettingsModel {
    var value: LinkSettings {
        didSet { if value != oldValue { value.save(to: .standard) } }
    }

    init() {
        value = LinkSettings.load(from: .standard)
    }
}

import Foundation
import Libbox
import Network
import NetworkExtension
import os
import ParalluxKit

/// libbox's view of the operating system inside the extension.
///
/// openTun and the default-interface monitor are adapted from SFM's
/// ExtensionPlatformInterface.swift (GPLv3, docs/LICENSES.md) and trimmed to
/// libbox 1.14.4's protocol. Process lookup, shells and bridges belong to the
/// helper service (PLAN decision 12) and report "unsupported" until it exists.
final class ExtensionPlatform: NSObject, LibboxPlatformInterfaceProtocol, LibboxCommandServerHandlerProtocol, @unchecked Sendable {
    private unowned let tunnel: PacketTunnelProvider
    private var monitor: NWPathMonitor?
    private var lastPath: String?

    /// Why: setTunnelNetworkSettings normally answers in milliseconds; a
    /// wedged nesessionmanager must not hang libbox's startup forever.
    /// Assumed value, generous because route installation can be slow on
    /// first activation.
    private static let settingsTimeout: TimeInterval = 30

    init(tunnel: PacketTunnelProvider) {
        self.tunnel = tunnel
    }

    func reset() {
        monitor?.cancel()
        monitor = nil
        lastPath = nil
    }

    // MARK: tun

    func openTun(_ options: (any LibboxTunOptionsProtocol)?, ret0_: UnsafeMutablePointer<Int32>?) throws {
        guard let options, let ret0_ else { throw ExtensionError("openTun: nil arguments") }
        let prefs = tunnel.startOptions ?? TunnelStartOptions(configContent: "")
        let settings = try Self.networkSettings(options, prefs)

        let done = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var failure: Error?
        tunnel.setTunnelNetworkSettings(settings) { error in
            failure = error
            done.signal()
        }
        if done.wait(timeout: .now() + Self.settingsTimeout) == .timedOut {
            throw ExtensionError("setTunnelNetworkSettings timed out")
        }
        if let failure { throw failure }

        if let fd = tunnel.packetFlow.value(forKeyPath: "socket.fileDescriptor") as? Int32 {
            ret0_.pointee = fd
            return
        }
        let fd = LibboxGetTunnelFileDescriptor()
        guard fd != -1 else { throw ExtensionError("openTun: missing utun file descriptor") }
        ret0_.pointee = fd
    }

    private static func strings(_ iterator: (any LibboxStringIteratorProtocol)?) -> [String] {
        var out: [String] = []
        while let iterator, iterator.hasNext() { out.append(iterator.next()) }
        return out
    }

    private static func prefixes(_ iterator: (any LibboxRoutePrefixIteratorProtocol)?) -> [LibboxRoutePrefix] {
        var out: [LibboxRoutePrefix] = []
        while let iterator, iterator.hasNext() {
            if let next = iterator.next() { out.append(next) }
        }
        return out
    }

    static func networkSettings(_ options: any LibboxTunOptionsProtocol, _ prefs: TunnelStartOptions) throws -> NEPacketTunnelNetworkSettings {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        if options.getAutoRoute() {
            settings.mtu = NSNumber(value: options.getMTU())
            var dns: NEDNSSettings?
            if options.getDNSMode()?.value != LibboxDNSModeDisabled {
                let servers = strings(try options.getDNSServerAddress())
                if !servers.isEmpty { dns = NEDNSSettings(servers: servers) }
            }

            let v4 = prefixes(options.getInet4Address())
            let ipv4 = NEIPv4Settings(addresses: v4.map { $0.address() }, subnetMasks: v4.map { $0.mask() })
            var v4Routes = prefixes(options.getInet4RouteAddress()).map {
                NEIPv4Route(destinationAddress: $0.address(), subnetMask: $0.mask())
            }
            if v4Routes.isEmpty {
                v4Routes = prefs.autoRouteUseSubRangesByDefault
                    ? (0..<8).map { NEIPv4Route(destinationAddress: "\(1 << $0).0.0.0", subnetMask: "\(256 - (1 << $0)).0.0.0") }
                    : [NEIPv4Route.default()]
            }
            var v4Excluded = prefixes(options.getInet4RouteExcludeAddress()).map {
                NEIPv4Route(destinationAddress: $0.address(), subnetMask: $0.mask())
            }
            if prefs.excludeDefaultRoute {
                v4Excluded.append(NEIPv4Route(destinationAddress: "0.0.0.0", subnetMask: "255.255.255.254"))
            }
            if prefs.excludeAPNs {
                v4Excluded.append(NEIPv4Route(destinationAddress: "17.0.0.0", subnetMask: "255.0.0.0"))
            }
            ipv4.includedRoutes = v4Routes
            ipv4.excludedRoutes = v4Excluded
            settings.ipv4Settings = ipv4

            let v6 = prefixes(options.getInet6Address())
            if !v6.isEmpty {
                let ipv6 = NEIPv6Settings(addresses: v6.map { $0.address() }, networkPrefixLengths: v6.map { NSNumber(value: $0.prefix()) })
                var v6Routes = prefixes(options.getInet6RouteAddress()).map {
                    NEIPv6Route(destinationAddress: $0.address(), networkPrefixLength: NSNumber(value: $0.prefix()))
                }
                if v6Routes.isEmpty {
                    v6Routes = prefs.autoRouteUseSubRangesByDefault
                        ? (0..<8).map { NEIPv6Route(destinationAddress: String(1 << $0, radix: 16) + "00::", networkPrefixLength: NSNumber(value: 8 - $0)) }
                        : [NEIPv6Route.default()]
                }
                var v6Excluded = prefixes(options.getInet6RouteExcludeAddress()).map {
                    NEIPv6Route(destinationAddress: $0.address(), networkPrefixLength: NSNumber(value: $0.prefix()))
                }
                if prefs.excludeDefaultRoute {
                    v6Excluded.append(NEIPv6Route(destinationAddress: "::", networkPrefixLength: 127))
                }
                ipv6.includedRoutes = v6Routes
                ipv6.excludedRoutes = v6Excluded
                settings.ipv6Settings = ipv6
            }

            let hasDefaultRoute = v4Routes.contains { $0.destinationAddress == "0.0.0.0" && $0.destinationSubnetMask == "0.0.0.0" }
            if !hasDefaultRoute {
                dns?.matchDomains = [""]
                dns?.matchDomainsNoSearch = true
            }
            settings.dnsSettings = dns
        }

        if options.isHTTPProxyEnabled() {
            let proxy = NEProxySettings()
            let server = NEProxyServer(address: options.getHTTPProxyServer(), port: Int(options.getHTTPProxyServerPort()))
            proxy.httpServer = server
            proxy.httpsServer = server
            proxy.httpEnabled = prefs.systemProxyEnabled
            proxy.httpsEnabled = prefs.systemProxyEnabled
            var bypass = strings(options.getHTTPProxyBypassDomain())
            if prefs.excludeAPNs, !bypass.contains("push.apple.com") { bypass.append("push.apple.com") }
            if !bypass.isEmpty { proxy.exceptionList = bypass }
            let match = strings(options.getHTTPProxyMatchDomain())
            if !match.isEmpty { proxy.matchDomains = match }
            settings.proxySettings = proxy
        }
        return settings
    }

    // MARK: interfaces

    func startDefaultInterfaceMonitor(_ listener: (any LibboxInterfaceUpdateListenerProtocol)?) throws {
        guard let listener else { return }
        let monitor = NWPathMonitor()
        self.monitor = monitor
        let first = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var signalled = false
        // libbox's listener is a Go object; calls into it are thread-safe.
        nonisolated(unsafe) let target = listener
        monitor.pathUpdateHandler = { [weak self] path in
            self?.publish(path, to: target)
            if !signalled {
                signalled = true
                first.signal()
            }
        }
        monitor.start(queue: DispatchQueue(label: "parallux.path-monitor"))
        // Why 5 s: NWPathMonitor delivers the current path immediately in
        // practice; the bound only guards a broken monitor (assumed value).
        _ = first.wait(timeout: .now() + 5)
    }

    private func publish(_ path: NWPath, to listener: any LibboxInterfaceUpdateListenerProtocol) {
        let description = "\(path.status) " + path.availableInterfaces.map { "\($0.name)#\($0.index)" }.joined(separator: ",")
        listener.updateNetworkPath(description)
        guard description != lastPath else { return }
        lastPath = description
        guard path.status != .unsatisfied, let primary = path.availableInterfaces.first else {
            listener.updateDefaultInterface("", interfaceIndex: -1, isExpensive: false, isConstrained: false)
            return
        }
        listener.updateDefaultInterface(primary.name, interfaceIndex: Int32(primary.index), isExpensive: path.isExpensive, isConstrained: path.isConstrained)
    }

    func closeDefaultInterfaceMonitor(_: (any LibboxInterfaceUpdateListenerProtocol)?) throws {
        reset()
    }

    func getInterfaces() throws -> any LibboxNetworkInterfaceIteratorProtocol {
        guard let monitor else { throw ExtensionError("interface monitor not started") }
        let path = monitor.currentPath
        let interfaces: [LibboxNetworkInterface] = path.status == .unsatisfied ? [] : path.availableInterfaces.map {
            let interface = LibboxNetworkInterface()
            interface.name = $0.name
            interface.index = Int32($0.index)
            switch $0.type {
            case .wifi: interface.type = LibboxInterfaceTypeWIFI
            case .cellular: interface.type = LibboxInterfaceTypeCellular
            case .wiredEthernet: interface.type = LibboxInterfaceTypeEthernet
            default: interface.type = LibboxInterfaceTypeOther
            }
            return interface
        }
        return InterfaceIterator(interfaces)
    }

    private final class InterfaceIterator: NSObject, LibboxNetworkInterfaceIteratorProtocol {
        private var items: IndexingIterator<[LibboxNetworkInterface]>
        private var current: LibboxNetworkInterface?
        init(_ items: [LibboxNetworkInterface]) { self.items = items.makeIterator() }
        func hasNext() -> Bool {
            current = items.next()
            return current != nil
        }
        func next() -> LibboxNetworkInterface? { current }
    }

    func underNetworkExtension() -> Bool { true }
    func includeAllNetworks() -> Bool { tunnel.startOptions?.includeAllNetworks ?? false }
    func usePlatformAutoDetectControl() -> Bool { false }
    func autoDetectControl(_: Int32) throws {}
    func registerMyInterface(_: String?) {}

    func clearDNSCache() {
        // Re-applying the same settings flushes the resolver cache (SFM does
        // the same); nothing to do before the tunnel has settings.
    }

    // MARK: not supported inside the extension (helper service, PLAN decision 12)

    func findConnectionOwner(_: Int32, sourceAddress _: String?, sourcePort _: Int32, destinationAddress _: String?, destinationPort _: Int32) throws -> LibboxConnectionOwner {
        throw ExtensionError("process lookup needs the helper service")
    }

    func readWIFIState() -> LibboxWIFIState? { nil }
    func localDNSTransport() -> (any LibboxLocalDNSTransportProtocol)? { nil }
    func usePlatformShell() -> Bool { false }
    func checkPlatformShell() throws { throw ExtensionError("no platform shell") }
    func openShellSession(_: LibboxPlatformUser?, command _: String?, environ _: (any LibboxStringIteratorProtocol)?, term _: String?, rows _: Int32, cols _: Int32) throws -> any LibboxShellSessionProtocol {
        throw ExtensionError("no platform shell")
    }
    func lookupUser(_: String?) throws -> LibboxPlatformUser { throw ExtensionError("no user lookup") }
    func readSystemSSHHostKey(_ error: NSErrorPointer) -> String { "" }
    func lookupSFTPServer(_ error: NSErrorPointer) -> String { "" }
    func tailscaleHostname() -> String { Host.current().localizedName ?? "" }
    func usePlatformBridge() -> Bool { false }
    func createBridge(_: LibboxBridgeOptions?) throws -> any LibboxBridgeSessionProtocol { throw ExtensionError("no bridge") }
    func startNeighborMonitor(_: (any LibboxNeighborUpdateListenerProtocol)?) throws {}
    func closeNeighborMonitor(_: (any LibboxNeighborUpdateListenerProtocol)?) throws {}
    func send(_: LibboxNotification?) throws {}
    func cancelNotification(_: String?, typeID _: Int32) throws {}

    // MARK: LibboxCommandServerHandler

    func serviceStop() throws {
        tunnel.cancelTunnelWithError(nil)
    }

    func serviceReload() throws {
        guard let options = tunnel.startOptions else { throw ExtensionError("no start options to reload") }
        try tunnel.commandServer?.startOrReloadService(options.configContent, options: LibboxOverrideOptions())
    }

    func getSystemProxyStatus() throws -> LibboxSystemProxyStatus {
        let status = LibboxSystemProxyStatus()
        status.available = false
        status.enabled = tunnel.startOptions?.systemProxyEnabled ?? false
        return status
    }

    func setSystemProxyEnabled(_: Bool) throws {
        throw ExtensionError("toggle the system proxy from settings; it applies on reconnect")
    }

    func connectSSHAgent(_: UnsafeMutablePointer<Int32>?) throws { throw ExtensionError("no SSH agent") }
    func triggerNativeCrash() throws { throw ExtensionError("disabled") }
    func writeDebugMessage(_ message: String?) {
        if let message { tunnel.log.debug("\(message, privacy: .public)") }
    }
}

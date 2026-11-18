import Foundation
import Libbox
import NetworkExtension
import Observation
import os
import ParalluxKit

/// Owns the NETunnelProviderManager: installs the system extension, saves the
/// VPN configuration, starts and stops the tunnel (adapted from SFM
/// ExtensionProfile.swift, GPLv3).
@MainActor @Observable
final class TunnelController {
    enum Phase: Equatable {
        case unknown
        case needsExtension
        case awaitingApproval
        case ready
        case failed(String)
    }

    private(set) var phase: Phase = .unknown
    private(set) var vpnStatus: NEVPNStatus = .invalid
    private(set) var connectedDate: Date?
    let session = CoreSession()

    @ObservationIgnored private var manager: NETunnelProviderManager?
    @ObservationIgnored private var observer: (any NSObjectProtocol)?
    @ObservationIgnored private let installer = SystemExtensionInstaller()
    @ObservationIgnored private let log = Logger(subsystem: "io.github.visual-z.parallux", category: "tunnel")

    var isConnected: Bool { vpnStatus == .connected }
    var isBusy: Bool { [.connecting, .disconnecting, .reasserting].contains(vpnStatus) }

    init() {
        LibboxSetXPCDialer(CommandXPCDialer.shared)
    }

    /// Loads an existing configuration without prompting; never installs.
    func load() async {
        do {
            manager = try await NETunnelProviderManager.loadAllFromPreferences().first
            phase = manager == nil ? .needsExtension : .ready
            observe()
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Installs (or updates) the system extension and the VPN configuration.
    func install() async {
        do {
            switch try await installer.activate() {
            case .needsApproval:
                phase = .awaitingApproval
                return
            case .willCompleteAfterReboot:
                phase = .failed("需要重启后完成安装")
                return
            case .activated:
                break
            }
            let manager = self.manager ?? NETunnelProviderManager()
            let proto = NETunnelProviderProtocol()
            proto.providerBundleIdentifier = SystemExtensionInstaller.extensionBundleID
            proto.serverAddress = "Parallux"
            manager.protocolConfiguration = proto
            manager.localizedDescription = "Parallux"
            manager.isEnabled = true
            try await manager.saveToPreferences()
            try await manager.loadFromPreferences()
            self.manager = manager
            phase = .ready
            observe()
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func connect(_ options: TunnelStartOptions, onDemand: (enabled: Bool, rules: [OnDemandRuleModel])? = nil) async {
        guard let manager else { return }
        do {
            if let onDemand {
                manager.onDemandRules = onDemand.rules.filter { $0.problem == nil }.map(Self.rule)
                manager.isOnDemandEnabled = onDemand.enabled && !onDemand.rules.isEmpty
            }
            if !manager.isEnabled {
                manager.isEnabled = true
                try await manager.saveToPreferences()
            }
            if let proto = manager.protocolConfiguration {
                proto.includeAllNetworks = options.includeAllNetworks
                proto.excludeLocalNetworks = options.excludeLocalNetworks
                proto.excludeAPNs = options.excludeAPNs
                proto.excludeDeviceCommunication = options.excludeDeviceCommunication
                proto.enforceRoutes = options.enforceRoutes
                try await manager.saveToPreferences()
            }
            try manager.connection.startVPNTunnel(options: options.encoded())
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Turns on-demand off first, or the system would reconnect at once.
    /// Reloads the running core with new options without dropping the tunnel
    /// (the extension's handleAppMessage calls libbox startOrReloadService).
    func reload(_ options: TunnelStartOptions) async throws {
        guard let session = manager?.connection as? NETunnelProviderSession, vpnStatus == .connected else { return }
        let data = try options.json()
        let reply: Data? = try await withCheckedThrowingContinuation { continuation in
            do {
                try session.sendProviderMessage(data) { continuation.resume(returning: $0) }
            } catch {
                continuation.resume(throwing: error)
            }
        }
        if let reply, !reply.isEmpty {
            throw NSError(domain: "Parallux.Tunnel", code: 2, userInfo: [NSLocalizedDescriptionKey: String(decoding: reply, as: UTF8.self)])
        }
    }

    func disconnect() async {
        if let manager, manager.isOnDemandEnabled {
            manager.isOnDemandEnabled = false
            try? await manager.saveToPreferences()
        }
        manager?.connection.stopVPNTunnel()
    }

    /// Removes the VPN configuration and the system extension.
    func uninstall() async {
        await disconnect()
        try? await manager?.removeFromPreferences()
        manager = nil
        observer.map(NotificationCenter.default.removeObserver)
        observer = nil
        do {
            try await installer.deactivate()
            phase = .needsExtension
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func installedExtensionVersion() async -> String? { await installer.installedVersion() }

    static func rule(_ model: OnDemandRuleModel) -> NEOnDemandRule {
        let rule: NEOnDemandRule = model.action == .connect ? NEOnDemandRuleConnect() : NEOnDemandRuleDisconnect()
        switch model.match {
        case .anyNetwork:
            rule.interfaceTypeMatch = .any
        case let .wifi(ssid):
            rule.interfaceTypeMatch = .wiFi
            rule.ssidMatch = [ssid]
        case let .probe(url):
            rule.interfaceTypeMatch = .any
            rule.probeURL = URL(string: url)
        }
        return rule
    }

    private func observe() {
        guard observer == nil, let connection = manager?.connection else { return }
        apply(connection)
        observer = NotificationCenter.default.addObserver(forName: .NEVPNStatusDidChange, object: connection, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let connection = self.manager?.connection else { return }
                self.apply(connection)
            }
        }
    }

    private func apply(_ connection: NEVPNConnection) {
        let wasConnected = vpnStatus == .connected
        vpnStatus = connection.status
        connectedDate = connection.connectedDate
        if connection.status == .connected, !wasConnected {
            session.start()
        } else if connection.status != .connected, wasConnected {
            session.stop()
        }
    }
}

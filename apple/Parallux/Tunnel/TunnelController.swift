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

    func connect(_ options: TunnelStartOptions) async {
        guard let manager else { return }
        do {
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

    func disconnect() {
        manager?.connection.stopVPNTunnel()
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

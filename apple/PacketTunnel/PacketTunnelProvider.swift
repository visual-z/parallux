import Libbox
import NetworkExtension
import os

/// The packet tunnel. M0 only proves the extension links the Go core; starting
/// sing-box through libbox's command server is milestone M1
/// (docs/tasks/research-sysext-ipc.md).
final class PacketTunnelProvider: NEPacketTunnelProvider {
    private let log = Logger(subsystem: "io.github.visual-z.parallux.tunnel", category: "tunnel")

    // Completion-handler forms: the async overrides cannot take the
    // non-Sendable options dictionary under Swift 6 strict concurrency.
    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        log.info("core \(PxbridgeVersion(), privacy: .public) asked to start")
        completionHandler(NEVPNError(.configurationInvalid, userInfo: [
            NSLocalizedDescriptionKey: "Parallux 内核尚未接入（里程碑 M1）",
        ]))
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        log.info("stop requested, reason \(reason.rawValue)")
        completionHandler()
    }
}

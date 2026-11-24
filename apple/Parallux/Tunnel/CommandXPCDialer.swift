import Foundation
import Libbox
import ParalluxKit

/// libbox calls this when its command client connects: ask the extension
/// over XPC for a socket to its command server (PLAN decision 11).
final class CommandXPCDialer: NSObject, LibboxXPCDialerProtocol, @unchecked Sendable {
    static let shared = CommandXPCDialer()

    /// The app's only connection to the extension's Mach service. The status,
    /// notification and command callers all go through it, so one connection
    /// serves them all instead of one per call (fix-tunnel-xpc-connection-churn).
    static let link: TunnelXPCLink? = {
        guard let service = MachService.name(in: .main) else { return nil }
        return TunnelXPCLink(open: { NSXPCLinkTransport(service: service) })
    }()

    private static var missingAppGroup: NSError {
        NSError(domain: "Parallux.XPC", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "未签名的构建没有 App Group，无法连接网络扩展",
        ])
    }

    func dialXPC(_ ret0_: UnsafeMutablePointer<Int32>?) throws {
        guard let link = Self.link else { throw Self.missingAppGroup }
        ret0_?.pointee = try link.dialCommandSocket()
    }

    /// Probes every link from inside the extension (research-sysext-bind-interface).
    static func probeLinks() throws -> [LinkProbeResult] {
        guard let link else { throw missingAppGroup }
        return try link.probeLinks()
    }

    /// Which rule of the running configuration `target` matches; nil when the extension is unreachable.
    static func explainRoute(_ target: String) -> RouteExplanation? {
        guard let link else { return nil }
        return RouteExplanation.decode(link.explainRoute(target))
    }

    /// Per-link counters; "[]" when the extension is unreachable.
    static func linkStats() -> String {
        link?.linkStats() ?? "[]"
    }

    /// Queued core notifications; empty when the extension is unreachable.
    static func notifications() -> [CoreNotification] {
        link?.notifications() ?? []
    }
}
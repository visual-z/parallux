import Foundation

/// What the system extension exports on its Mach service (PLAN decision 11).
///
/// The extension runs as root, so its command.sock sits in root's home and the
/// app cannot open it; instead the extension opens the socket and hands the
/// connected descriptor over XPC (SFM's CommandXPC.swift does the same).
@objc public protocol TunnelXPCProtocol {
    /// Replies with a FileHandle connected to libbox's command server.
    func connectToCommandServer(reply: @escaping (FileHandle?, NSError?) -> Void)
    /// Runs LinkProbe on every candidate interface from inside the extension
    /// and replies with a JSON array of LinkProbeResult.
    func probeLinks(reply: @escaping (Data?, NSError?) -> Void)
    /// Replies with core/pxbridge LinkStatsJSON: per-link counters of every
    /// running aggregate outbound.
    func linkStats(reply: @escaping (String) -> Void)
    /// Replies with pxbridge.ExplainRoute(target): which rule of the running
    /// configuration a target matches and where it goes.
    func explainRoute(_ target: String, reply: @escaping (String) -> Void)
    /// Removes and replies with the core's queued notifications
    /// (NotificationQueue.encode); the app posts them, because a system
    /// extension runs outside the user session.
    func drainNotifications(reply: @escaping (Data) -> Void)
}

public enum TunnelXPC {
    /// How long the app waits for the extension to answer a dial.
    /// Why: libbox calls the dialer synchronously from Go and a missing reply
    /// (extension crashed, listener not resumed) would hang that goroutine
    /// forever. 5 s is assumed: SFM's local probe timeout is a few seconds and
    /// an XPC round trip to a running extension takes milliseconds; measure
    /// with `log stream` on the dial if this ever fires spuriously.
    public static let dialTimeout: TimeInterval = 5

    public enum DialError: Error, Equatable {
        case timedOut
        case noHandle
        case remote(String)
    }

    /// Bound for a whole probeLinks round: probes run in parallel, each
    /// capped at LinkProbe.timeout, plus slack for XPC. Derived, not measured.
    public static let probeTimeout: TimeInterval = LinkProbe.timeout + 2

    /// Runs the probes concurrently; used by the extension's XPC handler.
    public static func runProbes(interfaces: [String] = LinkProbe.candidateInterfaces()) -> [LinkProbeResult] {
        let results = ResultsBox(count: interfaces.count)
        DispatchQueue.concurrentPerform(iterations: interfaces.count) { index in
            results.set(index, LinkProbe.probe(interface: interfaces[index]))
        }
        return results.values
    }

    private final class ResultsBox: @unchecked Sendable {
        private let lock = NSLock()
        private var slots: [LinkProbeResult?]
        init(count: Int) { slots = Array(repeating: nil, count: count) }
        func set(_ index: Int, _ value: LinkProbeResult) { lock.withLock { slots[index] = value } }
        var values: [LinkProbeResult] { lock.withLock { slots.compactMap { $0 } } }
    }

    /// Whitelists FileHandle in the reply; NSXPC refuses classes it was not told about.
    public static func makeInterface() -> NSXPCInterface {
        let interface = NSXPCInterface(with: TunnelXPCProtocol.self)
        interface.setClasses(
            NSSet(object: FileHandle.self) as! Set<AnyHashable>,
            for: #selector(TunnelXPCProtocol.connectToCommandServer(reply:)),
            argumentIndex: 0,
            ofReply: true
        )
        return interface
    }
}

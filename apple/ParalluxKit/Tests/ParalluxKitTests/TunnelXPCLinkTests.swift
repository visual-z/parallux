import Foundation
@testable import ParalluxKit
import Testing

/// State shared with the closures a link captures.
private final class Box: @unchecked Sendable {
    var clock: Duration = .zero
    var failStats = false
    var transports: [FakeTransport] = []
}

/// Stands in for one connection to the extension.
private final class FakeTransport: TunnelXPCTransport, @unchecked Sendable {
    init(box: Box) { self.box = box }

    private let box: Box
    private let lock = NSLock()
    private var alive = true
    private var calls = 0

    var isAlive: Bool { lock.withLock { alive } }
    var linkStatsCalls: Int { lock.withLock { calls } }

    func linkStats(timeout _: TimeInterval) throws -> String {
        lock.withLock { calls += 1 }
        if box.failStats { throw TunnelXPC.DialError.timedOut }
        return "[]"
    }

    func dialCommandSocket(timeout _: TimeInterval) throws -> Int32 {
        throw TunnelXPC.DialError.noHandle
    }

    func drainNotifications(timeout _: TimeInterval) throws -> [CoreNotification] { [] }
    func explainRoute(_: String, timeout _: TimeInterval) throws -> String { "" }
    func probeLinks(timeout _: TimeInterval) throws -> [LinkProbeResult] { [] }

    func invalidate() { die() }

    /// What the system's invalidationHandler does to a real connection.
    func die() {
        lock.withLock { alive = false }
    }
}

@Suite struct TunnelXPCLinkTests {
    private func makeLink(_ box: Box) -> TunnelXPCLink {
        TunnelXPCLink(open: {
            let transport = FakeTransport(box: box)
            box.transports.append(transport)
            return transport
        }, now: { box.clock })
    }

    @Test func theLinkOpensOneConnectionHoweverManyPollsArrive() {
        let box = Box()
        let link = makeLink(box)

        for _ in 0..<50 { _ = link.linkStats() }
        #expect(box.transports.count == 1)
        #expect(box.transports.first?.linkStatsCalls == 50)

        // A connection the system invalidated is replaced once, not per call.
        box.transports[0].die()
        _ = link.linkStats()
        _ = link.linkStats()
        #expect(box.transports.count == 2)
        #expect(box.transports[1].linkStatsCalls == 2)
    }

    @Test func aFailingExtensionCoolsThePollsDownInsteadOfDialingEveryTick() throws {
        let box = Box()
        box.failStats = true
        let link = makeLink(box)

        _ = link.linkStats()
        #expect(box.transports.count == 1)
        #expect(box.transports[0].linkStatsCalls == 1)
        let cooldown = try #require(TunnelXPCPollRetry.delay(after: 1))

        box.clock += cooldown / 2
        _ = link.linkStats()
        #expect(box.transports.count == 1, "inside the cooldown the poll does not dial")

        box.clock += cooldown
        box.failStats = false
        _ = link.linkStats()
        #expect(box.transports.count == 2, "after the cooldown the link reconnects")
        #expect(box.transports[1].linkStatsCalls == 1)

        // One answer clears the cooldown: the next poll goes straight through.
        box.clock += .milliseconds(1)
        _ = link.linkStats()
        #expect(box.transports.count == 2)
        #expect(box.transports[1].linkStatsCalls == 2)
    }

    @Test func thePollCooldownGrowsAndStopsAtItsCap() throws {
        #expect(TunnelXPCPollRetry.delay(after: 0) == nil)
        #expect(TunnelXPCPollRetry.delay(after: -1) == nil)
        var previous = Duration.zero
        for failures in 1...12 {
            let delay = try #require(TunnelXPCPollRetry.delay(after: failures))
            #expect(delay > .zero)
            #expect(delay >= previous)
            previous = delay
        }
        #expect(previous == TunnelXPCPollRetry.delayLimit, "the cooldown reaches its cap")
        #expect(TunnelXPCPollRetry.delay(after: 40) == TunnelXPCPollRetry.delayLimit)
    }
}
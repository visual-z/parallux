import Foundation
@testable import ParalluxKit
import Testing

/// Counters shared with the closures a link captures.
private final class Box: @unchecked Sendable {
    var opened = 0
    var clock: Duration = .zero
}

/// Stands in for one connection to the extension.
private final class FakeTransport: TunnelXPCTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var alive = true
    private var statsCalls = 0
    var failStats = false

    var isAlive: Bool { lock.withLock { alive } }
    var linkStatsCalls: Int { lock.withLock { statsCalls } }

    func linkStats(timeout _: TimeInterval) throws -> String {
        lock.withLock { statsCalls += 1 }
        if failStats { throw TunnelXPC.DialError.timedOut }
        return "[]"
    }

    func dialCommandSocket(timeout _: TimeInterval) throws -> Int32 {
        throw TunnelXPC.DialError.noHandle
    }

    func drainNotifications(timeout _: TimeInterval) throws -> [CoreNotification] { [] }
    func explainRoute(_: String, timeout _: TimeInterval) throws -> String { "" }
    func probeLinks(timeout _: TimeInterval) throws -> [LinkProbeResult] { [] }

    func invalidate() {
        lock.withLock { alive = false }
    }

    /// What an invalidationHandler does to a real connection.
    func die() {
        lock.withLock { alive = false }
    }
}

@Suite struct TunnelXPCLinkTests {
    @Test func theLinkOpensOneConnectionHoweverManyPollsArrive() {
        let box = Box()
        let fake = FakeTransport()
        let link = TunnelXPCLink(open: {
            box.opened += 1
            return fake
        }, now: { box.clock })

        for _ in 0..<50 { _ = link.linkStats() }
        #expect(box.opened == 1)
        #expect(fake.linkStatsCalls == 50)

        // A connection the remote side invalidated is replaced once, not per call.
        fake.die()
        _ = link.linkStats()
        _ = link.linkStats()
        #expect(box.opened == 2)
    }

    @Test func aFailingExtensionCoolsThePollsDownInsteadOfDialingEveryTick() throws {
        let box = Box()
        let fake = FakeTransport()
        fake.failStats = true
        let link = TunnelXPCLink(open: {
            box.opened += 1
            return fake
        }, now: { box.clock })

        _ = link.linkStats()
        #expect(fake.linkStatsCalls == 1)
        let cooldown = try #require(TunnelXPCPollRetry.delay(after: 1))

        box.clock += cooldown / 2
        _ = link.linkStats()
        #expect(fake.linkStatsCalls == 1, "inside the cooldown the poll does not dial")
        #expect(box.opened == 1)

        box.clock += cooldown
        fake.failStats = false
        _ = link.linkStats()
        #expect(fake.linkStatsCalls == 2)
        #expect(box.opened == 2, "after the cooldown the link reconnects")

        // One answer clears the cooldown: the next poll goes straight through.
        box.clock += .milliseconds(1)
        _ = link.linkStats()
        #expect(fake.linkStatsCalls == 3)
        #expect(box.opened == 2)
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
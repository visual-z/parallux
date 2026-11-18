import Foundation
import Testing
@testable import ParalluxKit

/// Serves one end of a socketpair over XPC, the way the extension serves
/// libbox's command.sock.
private final class SocketServer: NSObject, NSXPCListenerDelegate, TunnelXPCProtocol, @unchecked Sendable {
    let served: FileHandle?
    let replies: Bool
    init(served: FileHandle?, replies: Bool = true) {
        self.served = served
        self.replies = replies
    }

    func listener(_: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = TunnelXPC.makeInterface()
        connection.exportedObject = self
        connection.resume()
        return true
    }

    func connectToCommandServer(reply: @escaping (FileHandle?, NSError?) -> Void) {
        if replies { reply(served, nil) }
    }
}

private func connect(to server: SocketServer) -> (NSXPCListener, NSXPCConnection) {
    let listener = NSXPCListener.anonymous()
    listener.delegate = server
    listener.resume()
    let connection = NSXPCConnection(listenerEndpoint: listener.endpoint)
    return (listener, connection)
}

@Suite struct TunnelXPCTests {
    @Test func aCommandSocketHandedOverXPCCarriesBytes() throws {
        var fds: [Int32] = [0, 0]
        #expect(socketpair(AF_UNIX, SOCK_STREAM, 0, &fds) == 0)
        let server = SocketServer(served: FileHandle(fileDescriptor: fds[0], closeOnDealloc: true))
        let (listener, connection) = connect(to: server)
        defer { connection.invalidate(); listener.invalidate() }

        let fd = try TunnelXPC.dialCommandSocket(over: connection, timeout: 2)
        defer { close(fd) }
        let payload = Array("started-service".utf8)
        #expect(write(fds[1], payload, payload.count) == payload.count)
        var buffer = [UInt8](repeating: 0, count: payload.count)
        #expect(read(fd, &buffer, buffer.count) == payload.count)
        #expect(buffer == payload)
        close(fds[1])
    }

    @Test func dialingAServiceThatNeverRepliesTimesOut() {
        let server = SocketServer(served: nil, replies: false)
        let (listener, connection) = connect(to: server)
        defer { connection.invalidate(); listener.invalidate() }

        let started = Date()
        #expect(throws: TunnelXPC.DialError.timedOut) {
            try TunnelXPC.dialCommandSocket(over: connection, timeout: 0.3)
        }
        #expect(Date().timeIntervalSince(started) < 2)
    }

    @Test func aReplyWithoutAHandleIsAnErrorNotADescriptor() {
        let server = SocketServer(served: nil)
        let (listener, connection) = connect(to: server)
        defer { connection.invalidate(); listener.invalidate() }
        #expect(throws: TunnelXPC.DialError.noHandle) {
            try TunnelXPC.dialCommandSocket(over: connection, timeout: 2)
        }
    }

    @Test func connectingToAMissingSocketReportsTheCall() {
        #expect(throws: UnixSocket.Failure.self) {
            try UnixSocket.connect(path: "/nonexistent/parallux/command.sock")
        }
    }

    @Test func aUnixSocketPathLongerThanSunPathIsRejectedBeforeConnecting() {
        let path = "/" + String(repeating: "a", count: 200)
        #expect(throws: UnixSocket.Failure(call: "path", code: ENAMETOOLONG)) {
            try UnixSocket.connect(path: path)
        }
    }
}

@Suite struct TunnelStartOptionsTests {
    /// Property over a fixed-seed sample: every field survives, not just the config.
    @Test func startOptionsSurviveARoundTrip() throws {
        var rng = SplitMix64(seed: 0x5EED)
        for _ in 0..<200 {
            var options = TunnelStartOptions(configContent: rng.string())
            options.includeAllNetworks = rng.bool()
            options.excludeLocalNetworks = rng.bool()
            options.excludeAPNs = rng.bool()
            options.excludeDeviceCommunication = rng.bool()
            options.enforceRoutes = rng.bool()
            options.systemProxyEnabled = rng.bool()
            options.excludeDefaultRoute = rng.bool()
            options.autoRouteUseSubRangesByDefault = rng.bool()
            let decoded = try TunnelStartOptions.decode(options.encoded())
            #expect(decoded == options)
        }
    }

    @Test func optionsWithoutTheParalluxKeyDecodeToNil() throws {
        #expect(try TunnelStartOptions.decode(nil) == nil)
        #expect(try TunnelStartOptions.decode(["other": NSNumber(value: 1)]) == nil)
    }
}

@Suite struct MachServiceTests {
    @Test func aMachServiceOutsideTheAppGroupIsRejected() {
        let group = "ABCDE12345.io.github.visual-z.parallux"
        #expect(MachService.resolve("\(group).tunnel.0.0.1", appGroup: group) == "\(group).tunnel.0.0.1")
        #expect(MachService.resolve("OTHERTEAM1.io.github.visual-z.parallux.tunnel.0.0.1", appGroup: group) == nil)
        #expect(MachService.resolve("\(group).tunnel.", appGroup: group) == nil)
        #expect(MachService.resolve("\(group).tunnel", appGroup: group) == nil)
        #expect(MachService.resolve(nil, appGroup: group) == nil)
        // Unsigned build: no team prefix, so no group and no service.
        #expect(MachService.resolve("io.github.visual-z.parallux.tunnel.0.0.1", appGroup: nil) == nil)
    }
}

/// Deterministic generator for the property tests (fixed seed, no Foundation randomness).
struct SplitMix64 {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func bool() -> Bool { next() & 1 == 1 }
    mutating func int(_ bound: Int) -> Int { Int(next() % UInt64(bound)) }
    /// Includes empty strings, multi-byte characters and JSON metacharacters.
    mutating func string() -> String {
        let alphabet = Array("ab{}\"\\:,\n 线路é😀")
        return String((0..<int(64)).map { _ in alphabet[int(alphabet.count)] })
    }
}

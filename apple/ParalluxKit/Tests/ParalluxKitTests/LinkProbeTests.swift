import Foundation
import Testing
@testable import ParalluxKit

/// A TCP listener on 127.0.0.1 that accepts and replies with a fixed trace body.
private final class TraceServer: @unchecked Sendable {
    let fd: Int32
    let port: UInt16
    init() throws {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        self.fd = fd
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0
        _ = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        listen(fd, 4)
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) } }
        port = UInt16(bigEndian: address.sin_port)
        Thread.detachNewThread {
            let client = accept(fd, nil, nil)
            guard client >= 0 else { return }
            var buffer = [UInt8](repeating: 0, count: 1024)
            _ = read(client, &buffer, buffer.count)
            let reply = Array("HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\nfl=1\nip=203.0.113.9\nts=1\n".utf8)
            _ = write(client, reply, reply.count)
            close(client)
        }
    }
    deinit { close(fd) }
}

@Suite struct LinkProbeTests {
    @Test func aBoundProbeThroughLoopbackReachesALocalListenerAndReadsTheEgressAddress() throws {
        let server = try TraceServer()
        let result = LinkProbe.probe(interface: "lo0", host: "127.0.0.1", port: server.port, timeout: 2)
        #expect(result.connected)
        #expect(result.errno == nil)
        #expect(result.index > 0)
        #expect(result.egressIP == "203.0.113.9")
    }

    @Test func probingAnInterfaceThatDoesNotExistReportsENXIO() {
        let result = LinkProbe.probe(interface: "nope0", host: "127.0.0.1", port: 9, timeout: 1)
        #expect(!result.connected)
        #expect(result.errno == ENXIO)
        #expect(result.failedCall == "if_nametoindex")
    }

    @Test func aRefusedPortReportsECONNREFUSED() throws {
        // Bind a listener to learn a free port, then close it so nothing answers.
        let port = try TraceServer().port
        let result = LinkProbe.probe(interface: "lo0", host: "127.0.0.1", port: port, timeout: 1, readTrace: false)
        #expect(!result.connected)
        #expect(result.errno == ECONNREFUSED)
        #expect(result.failedCall == "connect")
    }

    @Test func traceParsingFindsTheEgressAddress() {
        #expect(LinkProbe.parseTrace("fl=1\nip=198.51.100.7\nts=2\n") == "198.51.100.7")
        #expect(LinkProbe.parseTrace("ip=2001:db8::1") == "2001:db8::1")
        #expect(LinkProbe.parseTrace("fl=1\nvisit_scheme=http\n") == nil)
        #expect(LinkProbe.parseTrace("") == nil)
    }

    @Test func candidateInterfacesExcludeVirtualOnes() {
        let up = UInt32(IFF_UP | IFF_RUNNING)
        #expect(LinkProbe.isCandidate(name: "en0", flags: up, hasIPv4: true))
        #expect(LinkProbe.isCandidate(name: "en7", flags: up, hasIPv4: true))
        for name in ["lo0", "utun3", "ipsec0", "awdl0", "llw0", "bridge0", "anpi0", "ap1"] {
            #expect(!LinkProbe.isCandidate(name: name, flags: up, hasIPv4: true), "\(name) is virtual")
        }
        #expect(!LinkProbe.isCandidate(name: "en0", flags: UInt32(IFF_UP), hasIPv4: true), "not running")
        #expect(!LinkProbe.isCandidate(name: "en0", flags: up, hasIPv4: false), "no IPv4")
        #expect(!LinkProbe.isCandidate(name: "en0", flags: up | UInt32(IFF_LOOPBACK), hasIPv4: true))
    }
}

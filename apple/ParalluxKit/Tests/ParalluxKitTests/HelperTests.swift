import Foundation
import Testing
@testable import ParalluxKit

private typealias M = SocketOwnerMatcher

/// Test addresses are all valid; a parser that rejects one fails
/// `addressesParseAndIPv4MappedEqualsIPv4` instead of crashing the run.
private func ep(_ address: String, _ port: UInt16) -> M.Endpoint {
    M.Endpoint(M.Address(address) ?? M.Address.invalidForTests, port)
}

extension SocketOwnerMatcher.Address {
    static let invalidForTests = SocketOwnerMatcher.Address(testBytes: [], isIPv4: false)
}

private func entry(_ pid: Int32, _ proto: M.Proto, _ local: M.Endpoint, _ remote: M.Endpoint?) -> M.SocketEntry {
    M.SocketEntry(pid: pid, uid: 501, proto: proto, local: local, remote: remote)
}

@Suite struct SocketOwnerMatcherTests {
    @Test func addressesParseAndIPv4MappedEqualsIPv4() throws {
        #expect(M.Address("10.0.0.2") == M.Address("::ffff:10.0.0.2"))
        #expect(try #require(M.Address("::ffff:10.0.0.2")).isIPv4)
        #expect(try #require(M.Address("2001:db8::1")).isIPv4 == false)
        #expect(try #require(M.Address("0.0.0.0")).isUnspecified)
        #expect(try #require(M.Address("::")).isUnspecified)
        #expect(try #require(M.Address("10.0.0.2")).isUnspecified == false)
        #expect(M.Address("not an address") == nil)
        #expect(M.Address("") == nil)
    }

    @Test func zeroCandidatesMatchNothing() {
        #expect(M.match([], proto: .tcp, source: ep("10.0.0.2", 5000), destination: ep("1.1.1.1", 443)) == nil)
    }

    @Test func anExactTCPMatchIsFound() throws {
        let target = entry(42, .tcp, ep("10.0.0.2", 5000), ep("1.1.1.1", 443))
        let entries = [
            entry(1, .tcp, ep("10.0.0.2", 5001), ep("1.1.1.1", 443)),
            entry(2, .tcp, ep("10.0.0.2", 5000), ep("1.1.1.2", 443)),
            target,
        ]
        let found = try #require(M.match(entries, proto: .tcp, source: ep("10.0.0.2", 5000), destination: ep("1.1.1.1", 443)))
        #expect(found.entry == target)
        #expect(found.kind == .exact)
    }

    @Test func tcpNeverFallsBack() {
        let entries = [
            entry(1, .tcp, ep("10.0.0.2", 5000), ep("9.9.9.9", 443)),
            entry(2, .tcp, ep("0.0.0.0", 5000), nil),
        ]
        #expect(M.match(entries, proto: .tcp, source: ep("10.0.0.2", 5000), destination: ep("1.1.1.1", 443)) == nil)
    }

    @Test func udpFallsBackToTheLocalAddressThenToTheWildcard() throws {
        let local = entry(7, .udp, ep("10.0.0.2", 5353), ep("8.8.8.8", 53))
        let wildcard = entry(8, .udp, ep("0.0.0.0", 5353), nil)
        let viaLocal = try #require(M.match([wildcard, local], proto: .udp, source: ep("10.0.0.2", 5353), destination: ep("1.1.1.1", 53)))
        #expect(viaLocal.entry.pid == 7)
        #expect(viaLocal.kind == .localFallback)
        let viaWildcard = try #require(M.match([wildcard], proto: .udp, source: ep("10.0.0.2", 5353), destination: ep("1.1.1.1", 53)))
        #expect(viaWildcard.entry.pid == 8)
        #expect(viaWildcard.kind == .wildcardFallback)
    }

    @Test func withoutADestinationTheLocalAddressDecides() throws {
        let entries = [entry(3, .udp, ep("10.0.0.2", 6000), nil)]
        let found = try #require(M.match(entries, proto: .udp, source: ep("10.0.0.2", 6000), destination: nil))
        #expect(found.entry.pid == 3)
        #expect(found.kind == .exact)
    }

    @Test func ipv4MappedSourcesMatchIPv4SocketsAndFamiliesDoNotMix() throws {
        let v4 = entry(5, .tcp, ep("10.0.0.2", 7000), ep("1.1.1.1", 443))
        let mapped = try #require(M.match([v4], proto: .tcp, source: ep("::ffff:10.0.0.2", 7000), destination: ep("::ffff:1.1.1.1", 443)))
        #expect(mapped.entry.pid == 5)
        let v6 = entry(6, .udp, ep("::", 7000), nil)
        #expect(M.match([v6], proto: .udp, source: ep("10.0.0.2", 7000), destination: ep("1.1.1.1", 53)) == nil,
                "an IPv6 wildcard does not own an IPv4 flow")
        let v6Exact = entry(9, .tcp, ep("2001:db8::2", 7001), ep("2001:db8::1", 443))
        #expect(try #require(M.match([v6Exact], proto: .tcp, source: ep("2001:db8::2", 7001), destination: ep("2001:db8::1", 443))).entry.pid == 9)
    }

    @Test func theProtocolMustMatch() {
        let entries = [entry(1, .udp, ep("10.0.0.2", 5000), ep("1.1.1.1", 443))]
        #expect(M.match(entries, proto: .tcp, source: ep("10.0.0.2", 5000), destination: ep("1.1.1.1", 443)) == nil)
    }

    @Test func theMatcherOnlyReturnsCandidatesThatFitTheQuery() {
        var rng = SplitMix64(seed: 0x50C)
        let addresses = ["10.0.0.2", "10.0.0.3", "0.0.0.0", "2001:db8::2", "::", "::ffff:10.0.0.2"]
        let ports: [UInt16] = [0, 1, 443, 5000, 65535]
        func randomEndpoint() -> M.Endpoint { ep(addresses[rng.int(addresses.count)], ports[rng.int(ports.count)]) }
        for _ in 0..<500 {
            var entries = (0..<rng.int(8)).map { index in
                entry(Int32(index + 100), rng.bool() ? .tcp : .udp, randomEndpoint(), rng.bool() ? randomEndpoint() : nil)
            }
            let proto: M.Proto = rng.bool() ? .tcp : .udp
            let source = randomEndpoint()
            let destination = randomEndpoint()
            if let found = M.match(entries, proto: proto, source: source, destination: destination) {
                #expect(entries.contains(found.entry))
                #expect(found.entry.proto == proto)
                #expect(found.entry.local.port == source.port)
                #expect(found.entry.local.address.isIPv4 == source.address.isIPv4)
            }
            // An exact match placed anywhere is found as exact.
            let exact = entry(1, proto, source, destination)
            entries.insert(exact, at: rng.int(entries.count + 1))
            let found = M.match(entries, proto: proto, source: source, destination: destination)
            #expect(found?.kind == .exact)
            #expect(found.map { $0.entry.local == source && $0.entry.remote == destination } == true)
        }
    }
}

@Suite struct CrashReportCatalogTests {
    private func directory(files: [(String, Int, TimeInterval)]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("parallux-crash-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        for (name, size, age) in files {
            let file = url.appendingPathComponent(name)
            try Data(repeating: 0x41, count: size).write(to: file)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 2_000_000_000 - age)], ofItemAtPath: file.path)
        }
        return url
    }

    @Test func reportsAreListedNewestFirstUpToTheCap() throws {
        let dir = try directory(files: [("old.log", 3, 300), ("new.log", 2, 0), ("mid.log", 1, 100)])
        #expect(CrashReportCatalog.list(in: dir).map(\.name) == ["new.log", "mid.log", "old.log"])
        #expect(CrashReportCatalog.list(in: dir, limit: 1).map(\.name) == ["new.log"])
        #expect(CrashReportCatalog.list(in: dir, limit: 0).isEmpty)
        #expect(CrashReportCatalog.list(in: dir).first?.size == 2)
        #expect(CrashReportCatalog.list(in: dir.appendingPathComponent("missing")).isEmpty)
    }

    @Test func readingTruncatesAtTheCapAndRejectsPathsOutsideTheDirectory() throws {
        let dir = try directory(files: [("big.log", 100, 0), ("small.log", 5, 0)])
        let big = try CrashReportCatalog.read("big.log", in: dir, limit: 10)
        #expect(big.text.count == 10)
        #expect(big.truncated)
        let small = try CrashReportCatalog.read("small.log", in: dir, limit: 10)
        #expect(small.text == "AAAAA")
        #expect(!small.truncated)
        #expect(throws: CrashReportCatalog.Failure.invalidName) { try CrashReportCatalog.read("../etc/passwd", in: dir) }
        #expect(throws: CrashReportCatalog.Failure.invalidName) { try CrashReportCatalog.read("a/b.log", in: dir) }
        #expect(throws: CrashReportCatalog.Failure.invalidName) { try CrashReportCatalog.read("", in: dir) }
        #expect(throws: CrashReportCatalog.Failure.invalidName) { try CrashReportCatalog.read("..", in: dir) }
        #expect(throws: CrashReportCatalog.Failure.notFound) { try CrashReportCatalog.read("none.log", in: dir) }
    }
}

/// A fake helper behind an anonymous listener: real NSXPC encoding, no root.
private final class FakeHelper: NSObject, NSXPCListenerDelegate, HelperXPCProtocol, @unchecked Sendable {
    let replies: Bool
    private(set) var destroyed = false
    init(replies: Bool = true) { self.replies = replies }

    func listener(_: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = HelperXPC.makeInterface()
        connection.exportedObject = self
        connection.resume()
        return true
    }

    func version(reply: @escaping (String) -> Void) { if replies { reply("0.0.1 (42)") } }

    func findConnectionOwner(proto: Int32, sourceAddress: String, sourcePort: Int32, destinationAddress: String, destinationPort: Int32,
                             reply: @escaping (Data?, NSError?) -> Void) {
        guard replies else { return }
        let owner = HelperConnectionOwner(pid: 99, userID: 501, userName: "visual", processPath: "/usr/bin/curl")
        reply(proto == 6 && sourcePort == 5000 ? try? JSONEncoder().encode(owner) : nil,
              proto == 6 && sourcePort == 5000 ? nil : NSError(domain: "fake", code: 1, userInfo: [NSLocalizedDescriptionKey: "not found"]))
    }

    func workingDirectoryInfo(reply: @escaping (Data?, NSError?) -> Void) {
        guard replies else { return }
        reply(try? JSONEncoder().encode(HelperWorkingDirectory.Info(path: "/var/root/x", exists: true, sizeBytes: 1234)), nil)
    }

    func destroyWorkingDirectory(token: String, reply: @escaping (NSError?) -> Void) {
        guard replies else { return }
        if token == HelperWorkingDirectory.destroyToken {
            destroyed = true
            reply(nil)
        } else {
            reply(NSError(domain: "fake", code: 2, userInfo: [NSLocalizedDescriptionKey: "bad token"]))
        }
    }

    func listCrashReports(reply: @escaping (Data?, NSError?) -> Void) {
        guard replies else { return }
        reply(try? JSONEncoder().encode([CrashReportCatalog.Entry(name: "a.log", size: 1, modified: Date(timeIntervalSince1970: 1))]), nil)
    }

    func readCrashReport(name: String, reply: @escaping (Data?, NSError?) -> Void) {
        guard replies else { return }
        reply(try? JSONEncoder().encode(CrashReportCatalog.Report(name: name, text: "panic", truncated: false)), nil)
    }
}

@Suite struct HelperXPCTests {
    private func client(for helper: FakeHelper) -> (HelperXPCClient, NSXPCListener) {
        let listener = NSXPCListener.anonymous()
        listener.delegate = helper
        listener.resume()
        let endpoint = listener.endpoint
        return (HelperXPCClient { NSXPCConnection(listenerEndpoint: endpoint) }, listener)
    }

    @Test func callsRoundTripOverXPC() throws {
        let helper = FakeHelper()
        let (client, listener) = client(for: helper)
        defer { listener.invalidate() }
        #expect(try client.version(timeout: 2) == "0.0.1 (42)")
        let owner = try client.findConnectionOwner(proto: 6, sourceAddress: "10.0.0.2", sourcePort: 5000,
                                                   destinationAddress: "1.1.1.1", destinationPort: 443, timeout: 2)
        #expect(owner == HelperConnectionOwner(pid: 99, userID: 501, userName: "visual", processPath: "/usr/bin/curl"))
        #expect(throws: HelperXPC.CallError.remote("not found")) {
            try client.findConnectionOwner(proto: 17, sourceAddress: "10.0.0.2", sourcePort: 1, destinationAddress: "1.1.1.1", destinationPort: 53, timeout: 2)
        }
        #expect(try client.workingDirectoryInfo(timeout: 2).sizeBytes == 1234)
        #expect(try client.listCrashReports(timeout: 2).map(\.name) == ["a.log"])
        #expect(try client.readCrashReport(name: "a.log", timeout: 2).text == "panic")
    }

    @Test func destroyingTheWorkingDirectoryNeedsTheToken() throws {
        let helper = FakeHelper()
        let (client, listener) = client(for: helper)
        defer { listener.invalidate() }
        #expect(throws: HelperXPC.CallError.remote("bad token")) { try client.destroyWorkingDirectory(token: "yes", timeout: 2) }
        #expect(!helper.destroyed)
        try client.destroyWorkingDirectory(token: HelperWorkingDirectory.destroyToken, timeout: 2)
        #expect(helper.destroyed)
    }

    @Test func aHelperThatNeverRepliesTimesOut() {
        let helper = FakeHelper(replies: false)
        let (client, listener) = client(for: helper)
        defer { listener.invalidate() }
        let started = Date()
        #expect(throws: HelperXPC.CallError.timedOut) { try client.version(timeout: 0.3) }
        #expect(throws: HelperXPC.CallError.timedOut) {
            try client.findConnectionOwner(proto: 6, sourceAddress: "10.0.0.2", sourcePort: 5000, destinationAddress: "1.1.1.1", destinationPort: 443, timeout: 0.3)
        }
        #expect(Date().timeIntervalSince(started) < 3)
    }

    @Test func theExtensionHomeIsRootsContainerForItsBundleID() {
        #expect(HelperWorkingDirectory.extensionHome(extensionBundleID: "io.github.visual-z.parallux.tunnel").path
            == "/var/root/Library/Containers/io.github.visual-z.parallux.tunnel/Data")
    }
}

@Suite struct HelperMachServiceTests {
    @Test func theHelperServiceMustSitInsideTheAppGroup() {
        let group = "ABCDE12345.io.github.visual-z.parallux"
        #expect(HelperMachService.resolve("\(group).helper.0.0.1.20261119", appGroup: group) == "\(group).helper.0.0.1.20261119")
        #expect(HelperMachService.resolve("\(group).helper.", appGroup: group) == nil)
        #expect(HelperMachService.resolve("\(group).tunnel.0.0.1", appGroup: group) == nil)
        #expect(HelperMachService.resolve("OTHERTEAM1.io.github.visual-z.parallux.helper.0.0.1", appGroup: group) == nil)
        #expect(HelperMachService.resolve("io.github.visual-z.parallux.helper.0.0.1.1", appGroup: nil) == nil)
        #expect(HelperMachService.resolve(nil, appGroup: group) == nil)
    }
}

import Foundation
import Testing
@testable import ParalluxKit

@Suite struct BasicAuthTests {
    @Test func basicAuthMovesUserinfoIntoAHeader() throws {
        let url = try #require(URL(string: "https://alice:p%40ss@sub.example.com/link?x=1"))
        let request = BasicAuth.request(for: url, timeout: 30)
        #expect(request.url?.absoluteString == "https://sub.example.com/link?x=1")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Basic " + Data("alice:p@ss".utf8).base64EncodedString())
        #expect(request.timeoutInterval == 30)
        let plain = BasicAuth.request(for: try #require(URL(string: "https://sub.example.com/link")), timeout: 5)
        #expect(plain.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(plain.url?.absoluteString == "https://sub.example.com/link")
        let userOnly = BasicAuth.request(for: try #require(URL(string: "https://bob@sub.example.com/")), timeout: 5)
        #expect(userOnly.value(forHTTPHeaderField: "Authorization") == "Basic " + Data("bob:".utf8).base64EncodedString())
    }

    @Test func onlyRemoteProfilesAreReadOnly() {
        #expect(Profile(name: "r", kind: .remote).isReadOnly)
        #expect(!Profile(name: "l", kind: .local).isReadOnly)
        #expect(!Profile(name: "c", kind: .icloud).isReadOnly)
    }
}

@Suite struct ConnectionFilterTests {
    private func row(_ id: String, destination: String, network: String = "tcp", total: Int64, rate: Int64, at: TimeInterval, closed: Bool = false) -> ConnectionRow {
        ConnectionRow(id: id, process: "p\(id)", destination: destination, rule: "", outbound: "direct", network: network,
                      uplinkTotal: total / 2, downlinkTotal: total - total / 2, createdAt: Date(timeIntervalSince1970: at),
                      isClosed: closed, uplink: 0, downlink: rate)
    }

    @Test func connectionQueryFiltersSortsAndHidesDNS() {
        let rows = [
            row("1", destination: "a.example.com:443", total: 100, rate: 5, at: 10),
            row("2", destination: "1.1.1.1:53", network: "udp", total: 300, rate: 0, at: 30),
            row("3", destination: "b.example.com:443", total: 900, rate: 1, at: 20, closed: true),
            row("4", destination: "c.example.com:80", total: 50, rate: 50, at: 40),
        ]
        #expect(ConnectionQuery.apply(rows, state: .active, sort: .date, hideDNS: false, text: "").map(\.id) == ["4", "2", "1"])
        #expect(ConnectionQuery.apply(rows, state: .closed, sort: .date, hideDNS: false, text: "").map(\.id) == ["3"])
        #expect(ConnectionQuery.apply(rows, state: .all, sort: .traffic, hideDNS: false, text: "").map(\.id) == ["3", "2", "1", "4"])
        #expect(ConnectionQuery.apply(rows, state: .all, sort: .rate, hideDNS: false, text: "").map(\.id) == ["4", "1", "3", "2"])
        #expect(ConnectionQuery.apply(rows, state: .all, sort: .date, hideDNS: true, text: "").map(\.id) == ["4", "3", "1"])
        #expect(ConnectionQuery.apply(rows, state: .all, sort: .date, hideDNS: true, text: "example").map(\.id) == ["4", "3", "1"])
        #expect(ConnectionQuery.apply(rows, state: .active, sort: .date, hideDNS: true, text: "c.example").map(\.id) == ["4"])
        #expect(ConnectionQuery.apply([], state: .all, sort: .rate, hideDNS: true, text: "").isEmpty)
    }
}

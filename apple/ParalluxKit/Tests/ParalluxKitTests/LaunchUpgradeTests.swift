@testable import ParalluxKit
import Testing

@Suite struct LaunchUpgradeTests {
    @Test func aStaleExtensionIsReplacedOnLaunchAndTheTunnelComesBack() {
        let all: [LaunchUpgrade.Status] = [.disconnected, .connecting, .connected, .reasserting, .disconnecting]
        for status in all {
            #expect(LaunchUpgrade.action(signed: true, status: status, stale: false) == .none)
            #expect(LaunchUpgrade.action(signed: false, status: status, stale: true) == .none, "unsigned builds have no extension")
            #expect(LaunchUpgrade.action(signed: false, status: status, stale: false) == .none)
        }
        #expect(LaunchUpgrade.action(signed: true, status: .connected, stale: true) == .replaceAndReconnect)
        #expect(LaunchUpgrade.action(signed: true, status: .connecting, stale: true) == .replaceAndReconnect)
        #expect(LaunchUpgrade.action(signed: true, status: .reasserting, stale: true) == .replaceAndReconnect)
        #expect(LaunchUpgrade.action(signed: true, status: .disconnected, stale: true) == .replace)
        #expect(LaunchUpgrade.action(signed: true, status: .disconnecting, stale: true) == .replace, "the user is turning it off")
    }
}

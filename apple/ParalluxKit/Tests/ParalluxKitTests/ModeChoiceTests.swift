import Foundation
import Testing
@testable import ParalluxKit

/// 叠加 can only be chosen with an aggregation server (PLAN decision 27, INV-16).
@Suite struct ModeChoiceTests {
    private let first = UUID()
    private let second = UUID()

    /// INV-16, written out here rather than asked of the code under test.
    private func bondIsBehindAServer(_ settings: LinkSettings, _ servers: [UUID]) -> Bool {
        let inUseIsListed = settings.bondServerID.map(servers.contains) ?? servers.isEmpty
        return inUseIsListed && (settings.mode != .bond || settings.bondServerID != nil)
    }

    private func saved(_ json: String) throws -> LinkSettings {
        try JSONDecoder().decode(LinkSettings.self, from: Data(json.utf8))
    }

    @Test func aFreshInstallStartsInAModeThatNeedsNoServer() throws {
        #expect(LinkSettings.defaultMode == .balance)
        #expect(!LinkSettings.defaultMode.requiresAggregationServer)
        #expect(LinkSettings().mode == .balance)
        #expect(try saved("{}").mode == .balance)
    }

    @Test func choosingBondWithoutAServerChangesNothingAndAsksForOne() {
        for start in [AggregationMode.balance, .failover] {
            var settings = LinkSettings()
            settings.mode = start
            let before = settings
            #expect(settings.choose(.bond, servers: []) == .needsServer)
            #expect(settings == before)
        }
    }

    @Test func choosingBondWithAServerAppliesAndUsesAListedServer() {
        var none = LinkSettings()
        none.mode = .failover
        #expect(none.choose(.bond, servers: [first, second]) == .applied)
        #expect(none.mode == .bond)
        #expect(none.bondServerID == first)

        var kept = LinkSettings()
        kept.bondServerID = second
        #expect(kept.choose(.bond, servers: [first, second]) == .applied)
        #expect(kept.bondServerID == second)

        var stale = LinkSettings()
        stale.bondServerID = UUID()
        #expect(stale.choose(.bond, servers: [first]) == .applied)
        #expect(stale.mode == .bond)
        #expect(stale.bondServerID == first)
    }

    @Test func choosingBalanceOrFailoverNeverNeedsAServer() {
        for mode in [AggregationMode.balance, .failover] {
            for servers in [[], [first]] {
                var settings = LinkSettings()
                settings.mode = mode == .balance ? .failover : .balance
                #expect(settings.choose(mode, servers: servers) == .applied)
                #expect(settings.mode == mode)
            }
        }
    }

    @Test func settingsSavedAsBondWithoutAServerBecomeBalance() throws {
        var bare = try saved(#"{"mode":"bond"}"#)
        bare.serversChanged([])
        #expect(bare.mode == .balance)
        #expect(bare.bondServerID == nil)

        var gone = try saved(#"{"mode":"bond","bondServerID":"\#(UUID().uuidString)"}"#)
        gone.serversChanged([])
        #expect(gone.mode == .balance)
        #expect(gone.bondServerID == nil)

        // A server is there, the saved one is not: 叠加 stays, on a listed server.
        var moved = try saved(#"{"mode":"bond","bondServerID":"\#(UUID().uuidString)"}"#)
        moved.serversChanged([first])
        #expect(moved.mode == .bond)
        #expect(moved.bondServerID == first)
    }

    @Test func removingTheServerInUseMovesToTheNextAndTheLastOneEndsBond() {
        var bonded = LinkSettings()
        bonded.mode = .bond
        bonded.bondServerID = first
        bonded.serversChanged([second])
        #expect(bonded.mode == .bond)
        #expect(bonded.bondServerID == second)
        bonded.serversChanged([])
        #expect(bonded.mode == .balance)
        #expect(bonded.bondServerID == nil)

        // Another mode is never touched by the server list.
        var failover = LinkSettings()
        failover.mode = .failover
        failover.bondServerID = first
        failover.serversChanged([second])
        #expect(failover.mode == .failover)
        #expect(failover.bondServerID == second)
        failover.serversChanged([])
        #expect(failover.mode == .failover)
        #expect(failover.bondServerID == nil)
    }

    @Test func addingAServerAfterAskingForBondFinishesTheSwitch() {
        var asked = LinkSettings()
        asked.mode = .failover
        #expect(asked.choose(.bond, servers: []) == .needsServer)
        asked.serversChanged([first], awaitingBond: true)
        #expect(asked.mode == .bond)
        #expect(asked.bondServerID == first)

        // Nobody asked: the server is ready, the mode stays.
        var quiet = LinkSettings()
        quiet.mode = .failover
        quiet.serversChanged([first])
        #expect(quiet.mode == .failover)
        #expect(quiet.bondServerID == first)

        // A second server does not take over from the one in use.
        quiet.serversChanged([first, second])
        #expect(quiet.bondServerID == first)

        // Asking counts for nothing while the list is still empty.
        var waiting = LinkSettings()
        waiting.mode = .failover
        waiting.serversChanged([], awaitingBond: true)
        #expect(waiting.mode == .failover)
        #expect(waiting.bondServerID == nil)
    }

    @Test func usingAServerOnlyTakesListedOnes() {
        var settings = LinkSettings()
        settings.bondServerID = first
        settings.useServer(second, servers: [first, second])
        #expect(settings.bondServerID == second)
        settings.useServer(UUID(), servers: [first, second])
        #expect(settings.bondServerID == second)
    }

    @Test func aMenuMarksBondAsOpeningSomethingWhileThereIsNoServer() {
        #expect(AggregationMode.bond.menuTitle(hasServer: false) == "叠加…")
        #expect(AggregationMode.bond.menuTitle(hasServer: true) == "叠加")
        for mode in [AggregationMode.balance, .failover] {
            #expect(mode.menuTitle(hasServer: false) == mode.title)
            #expect(mode.menuTitle(hasServer: true) == mode.title)
        }
    }

    /// INV-16 over every way the mode, the server in use and the list change,
    /// from zero servers up to the most the loop allows.
    @Test func anyChoiceSequenceKeepsBondBehindAServer() throws {
        let maxServers = 4
        var rng = SplitMix64(seed: 0xB0_2D)
        var settings = LinkSettings()
        var servers: [UUID] = []
        var sawEmpty = false, sawFull = false, sawBond = false
        for step in 0..<4000 {
            switch rng.int(6) {
            case 0:
                let mode = AggregationMode.allCases[rng.int(AggregationMode.allCases.count)]
                let change = settings.choose(mode, servers: servers)
                #expect((change == .needsServer) == (mode == .bond && servers.isEmpty), "step \(step)")
                if change == .applied { #expect(settings.mode == mode, "step \(step)") }
            case 1:
                if servers.count < maxServers { servers.append(UUID()) }
                settings.serversChanged(servers, awaitingBond: rng.bool())
            case 2:
                if !servers.isEmpty { servers.remove(at: rng.int(servers.count)) }
                settings.serversChanged(servers)
            case 3:
                let id = servers.isEmpty || rng.int(4) == 0 ? UUID() : servers[rng.int(servers.count)]
                settings.useServer(id, servers: servers)
            case 4:
                // Settings as an earlier build may have saved them.
                let mode = AggregationMode.allCases[rng.int(AggregationMode.allCases.count)].rawValue
                // No server saved, one still on the list, or one that is gone.
                let savedID: UUID? = switch rng.int(3) {
                case 0: nil
                case 1: servers.randomElement(using: &rng)
                default: UUID()
                }
                let field = savedID.map { #","bondServerID":"\#($0.uuidString)""# } ?? ""
                settings = try saved(#"{"mode":"\#(mode)"\#(field)}"#)
                settings.serversChanged(servers)
            default:
                servers.removeAll()
                settings.serversChanged(servers)
            }
            #expect(bondIsBehindAServer(settings, servers), "step \(step): \(settings.mode) \(servers.count) servers")
            sawEmpty = sawEmpty || servers.isEmpty
            sawFull = sawFull || servers.count == maxServers
            sawBond = sawBond || settings.mode == .bond
        }
        // The walk reached both ends of the list and 叠加 itself.
        #expect(sawEmpty && sawFull && sawBond)
    }
}

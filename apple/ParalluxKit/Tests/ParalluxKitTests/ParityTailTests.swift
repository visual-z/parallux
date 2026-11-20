import Foundation
import Testing
@testable import ParalluxKit

@Suite struct DashboardCardsTests {
    @Test func dashboardCardsOrderHideAndReset() {
        var cards = DashboardCards()
        #expect(cards.visible == [.traffic, .routeMode, .profile])
        cards.hidden = [.routeMode]
        #expect(cards.visible == [.traffic, .profile])
        cards.move(fromOffsets: [2], toOffset: 0)
        #expect(cards.order == [.profile, .traffic, .routeMode])
        #expect(cards.visible == [.profile, .traffic])
        cards.hidden = Set(DashboardCard.allCases)
        #expect(cards.visible.isEmpty)
        cards.reset()
        #expect(cards == DashboardCards())
        let decoded = DashboardCards.decode(order: ["profile", "retired-card", "traffic"], hidden: ["traffic", "retired-card"])
        #expect(decoded.order == [.profile, .traffic, .routeMode], "unknown dropped, missing appended")
        #expect(decoded.hidden == [.traffic])
        #expect(DashboardCards.decode(order: [], hidden: []) == DashboardCards())
    }
}

@Suite struct EndpointSummaryTests {
    @Test func endpointSummariesFlagWhatNeedsTheUser() {
        let login = EndpointSummary.line(EndpointStatus(kind: .tailscale, tag: "ts", state: "NeedsLogin", authURL: "https://login.tailscale.com/a/abc"))
        #expect(login.needsUser)
        #expect(login.text.contains("https://login.tailscale.com/a/abc"))
        let running = EndpointSummary.line(EndpointStatus(kind: .tailscale, tag: "ts", state: "Running", stateText: "Running"))
        #expect(!running.needsUser && !running.isError)
        #expect(running.text.contains("已连接"))
        let challenge = EndpointSummary.line(EndpointStatus(kind: .openVPN, tag: "ovpn", state: "auth", challengeID: "c1"))
        #expect(challenge.needsUser)
        let failed = EndpointSummary.line(EndpointStatus(kind: .openConnect, tag: "oc", state: "error", error: "TLS handshake failed"))
        #expect(failed.isError)
        #expect(failed.text.contains("TLS handshake failed"))
        let connecting = EndpointSummary.line(EndpointStatus(kind: .openConnect, tag: "oc", state: "connecting", stateText: "Connecting"))
        #expect(!connecting.needsUser && !connecting.isError)
        #expect(connecting.text.contains("连接中"))
    }
}

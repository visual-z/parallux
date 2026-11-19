import Testing
@testable import ParalluxKit

@Suite struct SidebarTests {
    /// Decision 20 merged 节点 and 规则 into 路由 (design v0.3): eight items.
    @Test func theSidebarShowsEightItemsInThreeSectionsInDesignOrder() {
        #expect(SidebarSection.allCases.map(\.items) == [
            [.overview, .connections, .logs],
            [.links, .aggregationServer, .diagnostics],
            [.profiles, .routing],
        ])
    }

    @Test func onlyTheTrafficSectionHasNoHeader() {
        #expect(SidebarSection.allCases.map(\.title) == [nil, "聚合", "代理"])
    }

    @Test func everyItemHasATitleAndASymbol() {
        for item in SidebarItem.allCases {
            #expect(!item.title.isEmpty, "\(item) has no title")
            #expect(!item.symbol.isEmpty, "\(item) has no symbol")
        }
    }
}

@Suite struct AggregationModeTests {
    @Test func onlyBondingNeedsAnAggregationServer() {
        #expect(AggregationMode.allCases.filter(\.requiresAggregationServer) == [.bond])
    }

    @Test func modesAreTitledAsInTheGlossary() {
        #expect(AggregationMode.allCases.map(\.title) == ["分流", "叠加", "主备"])
    }
}

@Suite struct AppGroupTests {
    @Test func anUnexpandedOrEmptyGroupMeansNoGroup() {
        #expect(AppGroup.resolve(nil) == nil)
        #expect(AppGroup.resolve("") == nil)
        #expect(AppGroup.resolve("$(TeamIdentifierPrefix)io.github.visual-z.parallux") == nil)
    }

    @Test func aGroupWithoutATeamPrefixMeansNoGroup() {
        // Unsigned builds expand $(TeamIdentifierPrefix) to "", leaving the
        // bare bundle id, which is not a usable App Group on macOS.
        #expect(AppGroup.resolve("io.github.visual-z.parallux") == nil)
    }

    @Test func aResolvedGroupIsReturnedVerbatim() {
        #expect(AppGroup.resolve("ABCDE12345.io.github.visual-z.parallux") == "ABCDE12345.io.github.visual-z.parallux")
    }
}

@Suite struct RateFormatTests {
    @Test func ratesAreShownInBitsWithOneDecimalBelowTen() {
        #expect(RateFormat.bitsPerSecond(0) == "0 bps")
        #expect(RateFormat.bitsPerSecond(1) == "8 bps")
        #expect(RateFormat.bitsPerSecond(125) == "1.0 Kbps")
        #expect(RateFormat.bitsPerSecond(76_500_000) == "612 Mbps")
        #expect(RateFormat.bitsPerSecond(-5) == "0 bps")
        #expect(RateFormat.bitsPerSecond(Int64.max).hasSuffix("Gbps"))
    }

    @Test func byteTotalsAreAlwaysNumeric() {
        #expect(RateFormat.bytes(0).first?.isNumber == true)
        #expect(RateFormat.bytes(-1).first?.isNumber == true)
        #expect(RateFormat.bytes(1).first?.isNumber == true)
    }
}

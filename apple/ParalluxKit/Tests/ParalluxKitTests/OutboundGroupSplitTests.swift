import Testing
@testable import ParalluxKit

private func group(_ tag: String, selected: String = "n0", items: [String] = []) -> OutboundGroupModel {
    OutboundGroupModel(tag: tag, type: "selector", selectable: true, selected: selected,
                       items: items.map { .init(tag: $0, type: "AnyTLS", delay: 0) })
}

@Suite struct OutboundGroupSplitTests {
    @Test func anEmptyGroupSnapshotLeavesEveryItemANode() {
        // The disconnect path: CoreSession.stop() empties groups while the
        // picker still holds the items of the previous snapshot.
        let proxy = group("proxy", items: ["DE Auto", "direct"])
        let split = proxy.split(among: [])
        #expect(split.subgroups.isEmpty)
        #expect(split.nodes.map(\.tag) == ["DE Auto", "direct"])
    }

    @Test func aRowKeepsTheGroupFromTheSnapshotItWasSplitAgainst() {
        let proxy = group("proxy", items: ["DE Auto"])
        var groups = [group("DE Auto", selected: "DE-1")]
        let split = proxy.split(among: groups)
        groups[0] = group("DE Auto", selected: "DE-2")
        #expect(split.subgroups.first?.group.tag == "DE Auto")
        #expect(split.subgroups.first?.group.selected == "DE-1")
    }

    @Test func randomSnapshotsPartitionTheItemsIntoRowsAndNodes() {
        // 0, 1 and many: the empty snapshot and a single row are the two edges
        // the disconnect path and a plain picker take.
        #expect(group("proxy").split(among: []).subgroups.isEmpty)
        #expect(group("proxy", items: ["g"]).split(among: [group("g")]).subgroups.map(\.item.tag) == ["g"])
        var rng = SplitMix64(seed: 0x9E37_79B9)
        for _ in 0..<300 {
            // Duplicate tags on purpose: the core lists each group once, but
            // the split must stay deterministic if it ever does not.
            let tags = (0..<rng.int(8)).map { _ in "t\(rng.int(5))" }
            let groups = (0..<rng.int(5)).map { index in
                group("g\(rng.int(5))", selected: "s\(rng.int(3))", items: ["n\(index)"])
            }
            let owner = group("proxy", items: tags)
            let split = owner.split(among: groups)
            let known = Set(groups.map(\.tag))

            // Rows and nodes together are exactly the items, each in its own place.
            #expect(split.subgroups.count + split.nodes.count == tags.count)
            #expect(split.subgroups.map(\.item.tag) == tags.filter(known.contains))
            #expect(split.nodes.map(\.tag) == tags.filter { !known.contains($0) })

            // A row's group is the first group carrying its tag: same value,
            // no second lookup left for the view to do.
            for row in split.subgroups {
                #expect(row.group == groups.first { $0.tag == row.item.tag })
                #expect(row.group.tag == row.item.tag)
            }
        }
    }
}
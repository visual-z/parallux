import ParalluxKit
import SwiftUI

/// The flow diagram's nodes, steadied (docs/tasks/fix-flow-stability.md).
/// The only place the diagram touches AppModel; FlowDiagram itself takes
/// plain values.
///
/// It has memory (FlowSlots): an exit keeps its place while traffic comes
/// and goes, and widths follow smoothed rates. So it is sampled, once a
/// second by SteadyFlowDiagram, not recomputed whenever a view happens to
/// redraw.
@MainActor
final class FlowModel {
    struct Diagram: Equatable {
        var links: [FlowNode] = []
        var exits: [FlowNode] = []
        /// The middle column: rules, and what flows from them to the exits.
        var rules: [FlowNode] = []
        var flows: [FlowLink] = []
        var centre = ""
        /// FlowParticles.intensity of the smoothed total.
        var intensity = 0.0
    }

    /// Named exits shown at once. Why 5: with the labels' 34 pt between
    /// neighbours the overview fits five named exits and 其他 and still has
    /// height left for the bands; on the recorded traffic five seats also
    /// churn least (FlowSlots.retention's measurements).
    static let exitSeats = 5

    /// Rules shown at once. Why 6: one more than the exits because rules
    /// are more varied than the nodes they lead to; past six the middle
    /// column's labels crowd at the overview's usual height. Assumed.
    static let ruleSeats = 6
    /// Why 64: every (rule, node) pair the seated columns can make, with room
    /// to spare (7 × 6 = 42); the pairs are only smoothed, never merged.
    static let pairSeats = 64

    private var exits = FlowSlots(limit: exitSeats)
    private var rules = FlowSlots(limit: ruleSeats)
    private var pairs = FlowSlots(limit: pairSeats)
    private var ruleColors = ColorSeats(palette: FlowPalette.rules.count)
    /// Used for its smoothing only: links keep the order of the links page.
    private var links = FlowSlots(limit: 1)

    /// `time`: seconds on a clock that does not jump (system uptime).
    func sample(_ app: AppModel, at time: TimeInterval) -> Diagram {
        guard let status = app.session.status else { return Diagram() }
        let mode = app.effectiveMode
        // The links traffic uses, in priority order (with 聚合 off that is the
        // one macOS routes through, decision 21); none known, the first link.
        let carrying = app.activeLinks.isEmpty ? Array(app.links.links.prefix(1)) : app.activeLinks
        // Design v0.2 keeps switched-off links in the picture, faded. Only
        // with 聚合 on: off, the other links are not off, just not used.
        let idle = app.linkSettings.value.switches.aggregation ? app.allLinks.filter { !carrying.contains($0) } : []
        let measured = LinkFlow.columns(links: carrying, linkRates: app.linkStats.rates,
                                        totalRate: status.uplink + status.downlink, exits: []).left
        links.limit = max(carrying.count, 1)
        links.update(zip(carrying, measured).map { (id: $0.name, rate: Double($1.rate)) }, at: time)
        let smoothed = Dictionary(uniqueKeysWithValues: links.slots.map { ($0.id, $0.rate) })
        let unhealthy = Set(carrying.map(\.name).filter { app.linkStats.link(ProfileComposer.linkTag($0))?.healthy == false })
        let standings = LinkStanding.all(enabled: carrying.map(\.name), backup: app.linkSettings.value.preferences.backup, unhealthy: unhealthy, mode: mode)
        var linkNodes: [FlowNode] = zip(carrying, measured).map { link, node in
            FlowNode(id: link.name, name: node.title,
                     detail: OverviewCopy.linkDetail(enabled: true, standby: standings[link.name] == .standby, rate: node.rate),
                     rate: smoothed[link.name] ?? 0, color: LinkColors.color(for: link, in: app.links.links))
        }
        linkNodes += idle.map { link in
            FlowNode(id: link.name, name: link.title, detail: OverviewCopy.linkDetail(enabled: false, standby: false, rate: 0),
                     rate: 0, color: LinkColors.color(for: link, in: app.links.links), isDimmed: true)
        }

        // Rules and nodes from the connections: each one says which rule it
        // matched and where it left (fix-overview-layout-and-flow). Every
        // name is passed on; FlowSlots decides who is seated.
        let columns = FlowColumns.make(app.session.connections, ruleName: TrafficLabel.name(connectionRule:), maxRules: Self.pairSeats, maxNodes: Self.pairSeats)
        let named = { (list: [(name: String, rate: Double)]) in list.filter { $0.name != FlowSummary.otherName }.map { (id: $0.name, rate: $0.rate) } }
        rules.update(named(columns.rules), at: time)
        exits.update(named(columns.nodes), at: time)
        let seatedRules = Set(rules.slots.map(\.id)), seatedNodes = Set(exits.slots.map(\.id))
        let seat = { (name: String, seated: Set<String>) in seated.contains(name) ? name : FlowSlots.otherID }
        var pairRates: [String: Double] = [:]
        for flow in columns.flows {
            pairRates[seat(flow.rule, seatedRules) + "\u{1}" + seat(flow.node, seatedNodes), default: 0] += flow.rate
        }
        pairs.update(pairRates.map { (id: $0.key, rate: $0.value) }.sorted { $0.id < $1.id }, at: time)
        let server = mode == .bond ? app.servers.servers.first { $0.id == app.linkSettings.value.bondServerID }?.name : nil
        let exitNodes = exits.slots.map { slot in
            let direct = slot.id == FlowSummary.directName
            let plain = direct || slot.isOther
            // Label and width both follow the smoothed rate: with the latest
            // sample in the label, a node still drawn thick read 「0 bps」
            // (seen on the installed build, 2026-11-20).
            return FlowNode(id: slot.id,
                            name: slot.isOther ? FlowSummary.otherName : direct ? slot.id : OverviewCopy.exitName(node: slot.id, server: server, mode: mode),
                            detail: OverviewCopy.exitDetail(direct: plain, mode: mode, rate: Int64(slot.rate)),
                            rate: slot.rate,
                            color: direct ? FlowPalette.direct : slot.isOther ? FlowPalette.direct.opacity(0.6) : FlowPalette.proxy)
        }
        ruleColors.update(rules.slots.map(\.id), neutral: [FlowSlots.otherID])
        let ruleNodes = rules.slots.map { slot in
            FlowNode(id: slot.id, name: slot.isOther ? FlowSummary.otherName : slot.id,
                     detail: RateFormat.bitsPerSecond(Int64(slot.rate)), rate: slot.rate,
                     color: ruleColors.color(slot.id).map { FlowPalette.rules[$0] } ?? FlowPalette.direct)
        }
        let ruleIndex = Dictionary(uniqueKeysWithValues: rules.slots.enumerated().map { ($1.id, $0) })
        let nodeIndex = Dictionary(uniqueKeysWithValues: exits.slots.enumerated().map { ($1.id, $0) })
        let flowLinks: [FlowLink] = pairs.slots.compactMap { slot in
            let parts = slot.id.split(separator: "\u{1}", maxSplits: 1).map(String.init)
            guard parts.count == 2, let rule = ruleIndex[parts[0]], let node = nodeIndex[parts[1]], slot.rate > 0 else { return nil }
            return FlowLink(id: slot.id, rule: rule, node: node, rate: slot.rate)
        }
        return Diagram(links: linkNodes, exits: exitNodes, rules: ruleNodes, flows: flowLinks, centre: OverviewCopy.centre(mode: mode, rate: measured.map(\.rate).reduce(0, &+)),
                       intensity: FlowParticles.intensity(bytesPerSecond: links.slots.map(\.rate).reduce(0, +)))
    }
}

/// The live flow diagram: FlowModel sampled once a second, like the status
/// stream it follows. The view reads only the sampled value, so it redraws
/// once a second however often the session's connections change.
struct SteadyFlowDiagram: View {
    let app: AppModel
    var isCompact = false
    @State private var model = FlowModel()
    @State private var diagram = FlowModel.Diagram()

    var body: some View {
        // The panel's strip has no room for rule names: two columns there.
        FlowDiagram(links: diagram.links, exits: diagram.exits, rules: isCompact ? [] : diagram.rules, flows: isCompact ? [] : diagram.flows,
                    centerLabel: isCompact ? nil : diagram.centre, intensity: diagram.intensity, isCompact: isCompact)
            .task {
                while !Task.isCancelled {
                    let next = model.sample(app, at: ProcessInfo.processInfo.systemUptime)
                    if next != diagram { diagram = next }
                    try? await Task.sleep(for: .seconds(1))
                }
            }
    }
}

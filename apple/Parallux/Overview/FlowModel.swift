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
        var centre = ""
        /// FlowParticles.intensity of the smoothed total.
        var intensity = 0.0
    }

    /// Named exits shown at once. Why 5: with the labels' 34 pt between
    /// neighbours the overview fits five named exits and 其他 and still has
    /// height left for the bands; on the recorded traffic five seats also
    /// churn least (FlowSlots.retention's measurements).
    static let exitSeats = 5

    private var exits = FlowSlots(limit: exitSeats)
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
        let idle = app.linkSettings.value.switches.aggregation ? app.links.links.filter { !carrying.contains($0) } : []
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
            FlowNode(id: link.name, name: link.kind.title, detail: OverviewCopy.linkDetail(enabled: false, standby: false, rate: 0),
                     rate: 0, color: LinkColors.color(for: link, in: app.links.links), isDimmed: true)
        }

        exits.update(FlowSummary.rates(app.session.connections).map { (id: $0.name, rate: Double($0.rate)) }, at: time)
        let server = mode == .bond ? app.servers.servers.first { $0.id == app.linkSettings.value.bondServerID }?.name : nil
        let exitNodes = exits.slots.map { slot in
            let direct = slot.id == FlowSummary.directName
            let plain = direct || slot.isOther
            // The label prints the latest sample; the width follows the smoothed rate.
            return FlowNode(id: slot.id,
                            name: slot.isOther ? FlowSummary.otherName : direct ? slot.id : OverviewCopy.exitName(node: slot.id, server: server, mode: mode),
                            detail: OverviewCopy.exitDetail(direct: plain, mode: mode, rate: Int64(slot.current)),
                            rate: slot.rate,
                            color: direct ? FlowPalette.direct : slot.isOther ? FlowPalette.direct.opacity(0.6) : FlowPalette.proxy)
        }
        return Diagram(links: linkNodes, exits: exitNodes, centre: OverviewCopy.centre(mode: mode, rate: measured.map(\.rate).reduce(0, &+)),
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
        FlowDiagram(links: diagram.links, exits: diagram.exits, centerLabel: isCompact ? nil : diagram.centre, intensity: diagram.intensity, isCompact: isCompact)
            .task {
                while !Task.isCancelled {
                    let next = model.sample(app, at: ProcessInfo.processInfo.systemUptime)
                    if next != diagram { diagram = next }
                    try? await Task.sleep(for: .seconds(1))
                }
            }
    }
}

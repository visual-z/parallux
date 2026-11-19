import ParalluxKit
import SwiftUI

/// Builds the flow diagram's inputs from the live session and per-link
/// stats. The only place the diagram touches AppModel; FlowDiagram itself
/// takes plain values.
@MainActor
enum FlowModel {
    struct Diagram {
        var links: [FlowNode] = []
        var exits: [FlowNode] = []
        var centre = ""
        /// Bytes per second that fill the diagram's height.
        var capacity = Double(FlowScale.floor)
    }

    static func diagram(_ app: AppModel) -> Diagram {
        guard let status = app.session.status else { return Diagram() }
        let mode = app.effectiveMode
        // The links traffic uses, in priority order (with 聚合 off that is the
        // one macOS routes through, decision 21); none known, the first link.
        let carrying = app.activeLinks.isEmpty ? Array(app.links.links.prefix(1)) : app.activeLinks
        // Design v0.2 keeps switched-off links in the picture, faded. Only
        // with 聚合 on: off, the other links are not off, just not used.
        let idle = app.linkSettings.value.switches.aggregation ? app.links.links.filter { !carrying.contains($0) } : []
        let columns = LinkFlow.columns(links: carrying, linkRates: app.linkStats.rates,
                                       totalRate: status.uplink + status.downlink,
                                       exits: FlowSummary.exits(app.session.connections))
        let unhealthy = Set(carrying.map(\.name).filter { app.linkStats.link(ProfileComposer.linkTag($0))?.healthy == false })
        let standings = LinkStanding.all(enabled: carrying.map(\.name), backup: app.linkSettings.value.preferences.backup, unhealthy: unhealthy, mode: mode)
        var links: [FlowNode] = zip(carrying, columns.left).map { link, node in
            FlowNode(id: link.name, name: node.title,
                     detail: OverviewCopy.linkDetail(enabled: true, standby: standings[link.name] == .standby, rate: node.rate),
                     rate: Double(node.rate), color: LinkColors.color(for: link, in: app.links.links))
        }
        links += idle.map { link in
            FlowNode(id: link.name, name: link.kind.title, detail: OverviewCopy.linkDetail(enabled: false, standby: false, rate: 0),
                     rate: 0, color: LinkColors.color(for: link, in: app.links.links), isDimmed: true)
        }

        let server = mode == .bond ? app.servers.servers.first { $0.id == app.linkSettings.value.bondServerID }?.name : nil
        let exits = columns.right.map { node in
            let direct = node.title == FlowSummary.directName
            let other = node.title == FlowSummary.otherName
            return FlowNode(id: node.id,
                            name: direct || other ? node.title : OverviewCopy.exitName(node: node.title, server: server, mode: mode),
                            detail: OverviewCopy.exitDetail(direct: direct || other, mode: mode, rate: node.rate),
                            rate: Double(node.rate),
                            color: direct ? FlowPalette.direct : other ? FlowPalette.direct.opacity(0.6) : FlowPalette.proxy)
        }

        let total = columns.left.map(\.rate).reduce(0, &+)
        // Full scale follows the busiest second still in the history, and
        // never sits below what is drawn right now (the link counters and the
        // core's total are separate measurements).
        let peak = app.session.rateHistory.elements.map { $0.uplink &+ $0.downlink }.max() ?? 0
        return Diagram(links: links, exits: exits, centre: OverviewCopy.centre(mode: mode, rate: total),
                       capacity: Double(FlowScale.capacity(peak: max(peak, total))))
    }
}

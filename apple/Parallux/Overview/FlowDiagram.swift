import ParalluxKit
import SwiftUI

/// One column entry of the flow diagram.
struct FlowNode: Identifiable, Equatable {
    var id: String { name }
    var name: String
    var detail: String
    var rate: Double
    var color: Color
}

/// Links → aggregation bar → exits, band width = live rate (design v0.2).
/// Pure geometry comes from SankeyLayout (INV-3); this view only paints it.
struct FlowDiagram: View {
    let links: [FlowNode]
    let exits: [FlowNode]
    var centerLabel: String?
    var showsLabels = true

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let labelWidth: CGFloat = showsLabels ? min(140, size.width * 0.2) : 0
            let leftX = labelWidth + 4
            let rightX = size.width - labelWidth - 4
            let centerX = (leftX + rightX) / 2
            let bar: CGFloat = showsLabels ? 6 : 4
            let layout = SankeyLayout.make(left: links.map(\.rate), right: exits.map(\.rate),
                                           height: Double(size.height), gap: showsLabels ? 18 : 6)
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    for band in layout.bands {
                        let color = links[band.from].color
                        var path = Path()
                        let l0 = CGFloat(band.left.lower), l1 = CGFloat(band.left.upper)
                        let r0 = CGFloat(band.right.lower), r1 = CGFloat(band.right.upper)
                        let midX = (leftX + rightX) / 2
                        path.move(to: CGPoint(x: leftX + bar, y: l0))
                        path.addCurve(to: CGPoint(x: rightX, y: r0), control1: CGPoint(x: midX, y: l0), control2: CGPoint(x: midX, y: r0))
                        path.addLine(to: CGPoint(x: rightX, y: r1))
                        path.addCurve(to: CGPoint(x: leftX + bar, y: l1), control1: CGPoint(x: midX, y: r1), control2: CGPoint(x: midX, y: l1))
                        path.closeSubpath()
                        context.fill(path, with: .color(color.opacity(0.55)))
                    }
                    for (index, span) in layout.left.enumerated() where span.length > 0 {
                        context.fill(Path(roundedRect: CGRect(x: leftX, y: span.lower, width: bar, height: span.length), cornerRadius: 2),
                                     with: .color(links[index].color))
                    }
                    for (index, span) in layout.right.enumerated() where span.length > 0 {
                        context.fill(Path(roundedRect: CGRect(x: rightX, y: span.lower, width: bar, height: span.length), cornerRadius: 2),
                                     with: .color(exits[index].color))
                    }
                    if layout.total.length > 0 {
                        context.fill(Path(roundedRect: CGRect(x: centerX - bar / 2, y: layout.total.lower, width: bar, height: layout.total.length), cornerRadius: 2),
                                     with: .color(.primary.opacity(0.9)))
                    }
                }
                if showsLabels {
                    ForEach(Array(links.enumerated()), id: \.offset) { index, node in
                        label(node, alignment: .trailing)
                            .frame(width: labelWidth, alignment: .trailing)
                            .position(x: labelWidth / 2, y: mid(layout.left, index, size.height))
                    }
                    ForEach(Array(exits.enumerated()), id: \.offset) { index, node in
                        label(node, alignment: .leading)
                            .frame(width: labelWidth, alignment: .leading)
                            .position(x: size.width - labelWidth / 2, y: mid(layout.right, index, size.height))
                    }
                    if let centerLabel, layout.total.length > 0 {
                        Text(centerLabel).font(.caption).foregroundStyle(.secondary)
                            .position(x: centerX, y: max(8, CGFloat(layout.total.lower) - 10))
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private func mid(_ spans: [Span], _ index: Int, _ height: CGFloat) -> CGFloat {
        guard index < spans.count else { return height / 2 }
        return CGFloat((spans[index].lower + spans[index].upper) / 2)
    }

    private func label(_ node: FlowNode, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 1) {
            Text(node.name).font(.callout.weight(.medium)).lineLimit(1)
            Text(node.detail).font(.caption).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
        }
    }

    private var accessibilityText: String {
        let left = links.map { "\($0.name) \($0.detail)" }.joined(separator: "，")
        let right = exits.map { "\($0.name) \($0.detail)" }.joined(separator: "，")
        return "流向：\(left) 到 \(right)"
    }
}

/// Builds the diagram's columns from the live session.
@MainActor
enum FlowModel {
    static let linkColors: [Color] = [.cyan, .orange, .pink, .green]

    static func links(_ app: AppModel) -> [FlowNode] {
        guard let status = app.session.status, let link = app.defaultLink.link else { return [] }
        let rate = Double(status.uplink + status.downlink)
        return [FlowNode(name: link.kind, detail: RateFormat.bitsPerSecond(Int64(rate)), rate: rate, color: linkColors[0])]
    }

    static func exits(_ app: AppModel) -> [FlowNode] {
        FlowSummary.exits(app.session.connections).map { exit in
            FlowNode(name: exit.name, detail: RateFormat.bitsPerSecond(exit.rate), rate: Double(exit.rate),
                     color: exit.name == FlowSummary.directName ? .gray : exit.name == FlowSummary.otherName ? .secondary : .green)
        }
    }
}

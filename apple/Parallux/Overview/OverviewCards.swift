import AppKit
import Charts
import ParalluxKit
import SwiftUI

/// The overview's three cards. They take values and bindings only, so they
/// can be rendered on their own with any numbers; OverviewView feeds them
/// from the live session.
///
/// Every figure has a row of its own, label on the left and value on the
/// right (CardRow). No card joins several figures into one sentence: such a
/// sentence is what got cut off, or broke in the middle, when a card was
/// narrow (docs/tasks/fix-overview-responsive.md).

/// Lays the cards out in rows by the width it is given (OverviewGrid,
/// INV-15). Cards of one row are equally wide and as tall as the tallest of
/// them; rows have their own heights.
struct OverviewCardGrid: Layout {
    private func rows(_ subviews: Subviews, width: CGFloat) -> [Range<Int>] {
        OverviewGrid.rows(count: subviews.count, width: Double(width))
    }

    private func cardWidth(_ row: Range<Int>, width: CGFloat) -> CGFloat {
        max(0, (width - CGFloat(row.count - 1) * CGFloat(OverviewGrid.spacing)) / CGFloat(row.count))
    }

    /// The row's height: its tallest card at the row's card width.
    private func height(_ row: Range<Int>, _ subviews: Subviews, cardWidth: CGFloat) -> CGFloat {
        row.map { subviews[$0].sizeThatFits(ProposedViewSize(width: cardWidth, height: nil)).height }.max() ?? 0
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        // Asked for its ideal size, it answers with everything in one row.
        let ideal = CGFloat(subviews.count) * CGFloat(OverviewGrid.minimumCardWidth) + CGFloat(max(subviews.count - 1, 0)) * CGFloat(OverviewGrid.spacing)
        let width = proposal.width.map { $0.isFinite ? $0 : ideal } ?? ideal
        let rows = rows(subviews, width: width)
        let heights = rows.map { height($0, subviews, cardWidth: cardWidth($0, width: width)) }
        return CGSize(width: width, height: heights.reduce(0, +) + CGFloat(max(rows.count - 1, 0)) * CGFloat(OverviewGrid.spacing))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(subviews, width: bounds.width) {
            let width = cardWidth(row, width: bounds.width)
            let height = height(row, subviews, cardWidth: width)
            for (column, index) in row.enumerated() {
                let x = bounds.minX + CGFloat(column) * (width + CGFloat(OverviewGrid.spacing))
                subviews[index].place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(width: width, height: height))
            }
            y += height + CGFloat(OverviewGrid.spacing)
        }
    }
}

/// The design's `.card`: a quiet filled rectangle on the opaque content
/// layer. No glass and no shadow (copy-and-style.md §2).
struct OverviewCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.callout.weight(.medium)).foregroundStyle(.secondary)
            content
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        // The grid decides the width and the row's height; the card fills both.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DesignMetrics.cardFill, in: RoundedRectangle(cornerRadius: DesignMetrics.cardRadius))
    }
}

/// One figure of a card: the label on the left, the value on the right.
/// The value is never cut off or wrapped; when the two do not fit side by
/// side the value moves under the label, and only the label may shorten.
struct CardRow: View {
    let label: String
    let value: String
    /// A value that is a name rather than a number may wrap to two lines.
    var valueIsText = false

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                labelText.fixedSize()
                Spacer(minLength: 0)
                valueText.fixedSize()
            }
            VStack(alignment: .leading, spacing: 1) {
                labelText
                if valueIsText { valueText.lineLimit(2).truncationMode(.middle) } else { valueText.fixedSize() }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var labelText: some View {
        Text(label).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
    }

    private var valueText: some View {
        Text(value).font(.subheadline.weight(.medium)).monospacedDigit().lineLimit(valueIsText ? nil : 1)
    }
}

struct TrafficCard: View {
    /// Bytes per second, both directions.
    let rate: Int64
    /// Oldest first; the chart keeps `window` slots so the line grows from the left.
    let history: [Int64]
    let window: Int
    let downlinkTotal: Int64
    let uplinkTotal: Int64

    /// Why 412: two minimum card widths and the gap between them
    /// (OverviewGrid). From there on the card is the one that has a row to
    /// itself in a narrow window, and it lies flat so the row is short and
    /// the cards below stay on screen.
    static let flatFromWidth = CGFloat(2 * OverviewGrid.minimumCardWidth + OverviewGrid.spacing)

    var body: some View {
        OverviewCard(title: DashboardCard.traffic.title) {
            ViewThatFits(in: .horizontal) {
                // Flat: the rate, the chart taking the room between, the totals.
                HStack(alignment: .center, spacing: 16) {
                    rateText.fixedSize()
                    chart
                    VStack(spacing: 4) { totals }.frame(width: 150)
                }
                .frame(minWidth: Self.flatFromWidth - 28)
                // Upright: the rate, the chart taking the spare height, the totals.
                VStack(alignment: .leading, spacing: 6) {
                    rateText
                    chart
                    totals
                }
            }
        }
    }

    private var rateText: some View {
        Text(RateFormat.bitsPerSecond(rate)).font(.title.weight(.semibold)).monospacedDigit()
            .lineLimit(1).minimumScaleFactor(0.7)
    }

    /// The part of this card that can grow: it takes the room the row's
    /// tallest card leaves. 46 is its smallest and its ideal height, so this
    /// card never makes the row taller.
    private var chart: some View {
        Chart(Array(history.enumerated()), id: \.offset) { index, value in
            AreaMark(x: .value("t", index), y: .value("速率", value)).foregroundStyle(.tint.opacity(0.14))
            LineMark(x: .value("t", index), y: .value("速率", value)).foregroundStyle(.tint)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
        }
        .chartXAxis(.hidden).chartYAxis(.hidden).chartLegend(.hidden)
        .chartXScale(domain: 0...max(window - 1, 1))
        .frame(minHeight: 46, idealHeight: 46, maxHeight: .infinity)
        .accessibilityHidden(true)
    }

    /// This session's totals, each on its own row.
    @ViewBuilder private var totals: some View {
        CardRow(label: "下载", value: "↓ \(RateFormat.bytes(downlinkTotal))")
        CardRow(label: "上传", value: "↑ \(RateFormat.bytes(uplinkTotal))")
    }
}

struct RouteModeCard: View {
    /// The clash modes the running configuration offers.
    let modes: [String]
    @Binding var mode: String
    /// The most-hit rule (OverviewCopy.topRuleParts); nil before any rule was hit.
    var topRule: OverviewCopy.TopRule?
    /// Decision 21: 聚合 and 代理 sit with the other mode controls.
    @Binding var aggregation: Bool
    var aggregationDisabled = false
    @Binding var proxy: Bool
    var proxyDisabled = false
    @Binding var systemProxy: Bool
    var systemProxyDisabled = false

    var body: some View {
        OverviewCard(title: DashboardCard.routeMode.title) {
            if !modes.isEmpty {
                FillSegmentedControl(labels: modes.map(RouteMode.title), selection: Binding(
                    get: { modes.firstIndex(of: mode) ?? -1 },
                    set: { if modes.indices.contains($0) { mode = modes[$0] } }
                ))
                .accessibilityLabel(DashboardCard.routeMode.title)
                .padding(.bottom, 4)
            }
            if let topRule {
                // The share has its place on the label's row; the rule, by
                // the name the diagram gives it, and where it leads each get
                // a line of the full width. The condition itself is in the
                // tooltip.
                VStack(alignment: .leading, spacing: 1) {
                    CardRow(label: "命中最多", value: topRule.percent)
                    Text(topRule.name).font(.subheadline.weight(.medium)).lineLimit(1)
                    if !topRule.exit.isEmpty {
                        Text("→ \(topRule.exit)").font(.subheadline).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                }
                .help(topRule.route)
                .padding(.bottom, 4)
            }
            row("聚合", isOn: $aggregation).disabled(aggregationDisabled)
            row("代理", isOn: $proxy).disabled(proxyDisabled)
            row("系统 HTTP 代理", isOn: $systemProxy).disabled(systemProxyDisabled)
                .help("修改操作系统的代理设置")
        }
    }

    /// Design: the label on the left in the card's quiet type, the switch on the right.
    private func row(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title).font(.callout.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch).controlSize(.small)
    }
}

struct ProfileCard: View {
    let name: String?
    /// 「远程」「每 1 小时更新」「51 分钟前更新」: the parts of the profile's
    /// description, one per line so none is cut in the middle.
    let details: [String]
    let connections: Int?
    let memory: Int64?
    /// Traffic used over the subscription's quota (UsageSummary); nil without a profile.
    var usage: UsageSummary?

    var body: some View {
        OverviewCard(title: DashboardCard.profile.title) {
            if let name {
                Text(name).font(.title3.weight(.semibold)).lineLimit(1).truncationMode(.middle).help(name)
                ViewThatFits(in: .horizontal) {
                    Text(details.joined(separator: " · ")).fixedSize()
                    VStack(alignment: .leading, spacing: 1) { ForEach(details, id: \.self) { Text($0).lineLimit(1) } }
                }
                .font(.subheadline).foregroundStyle(.secondary)
            } else {
                Text("无配置").font(.title3.weight(.semibold)).foregroundStyle(.secondary)
            }
            // The figures sit at the card's foot; the spacer takes whatever
            // height the row's tallest card adds.
            Spacer(minLength: 2)
            if let connections { CardRow(label: "连接", value: "\(connections)") }
            if let memory { CardRow(label: "内存", value: RateFormat.bytes(memory)) }
            if let usage {
                CardRow(label: usage.label, value: usage.value)
                // Used share of the quota; an empty track when there is no
                // quota to take a share of.
                ProgressView(value: usage.fraction ?? 0)
                    .progressViewStyle(.linear)
                    .accessibilityHidden(true)
                if let note = usage.note {
                    Text(note).font(.caption).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
                }
            }
        }
    }
}

/// A segmented control that fills the width it is given, every segment
/// equally wide (design: the route mode control spans its card). SwiftUI's
/// segmented Picker keeps its natural width on macOS, so this wraps the
/// system control itself rather than drawing one.
struct FillSegmentedControl: NSViewRepresentable {
    let labels: [String]
    @Binding var selection: Int

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(labels: labels, trackingMode: .selectOne, target: context.coordinator,
                                         action: #selector(Coordinator.changed(_:)))
        control.segmentDistribution = .fillEqually
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.parent = self
        if control.segmentCount != labels.count { control.segmentCount = labels.count }
        for (index, label) in labels.enumerated() where control.label(forSegment: index) != label {
            control.setLabel(label, forSegment: index)
        }
        if control.selectedSegment != selection { control.selectedSegment = selection }
        // An AppKit control does not pick up SwiftUI's .disabled by itself.
        if control.isEnabled != context.environment.isEnabled { control.isEnabled = context.environment.isEnabled }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView control: NSSegmentedControl, context: Context) -> CGSize? {
        let natural = control.intrinsicContentSize
        return CGSize(width: max(proposal.width ?? natural.width, 0), height: natural.height)
    }

    @MainActor final class Coordinator: NSObject {
        var parent: FillSegmentedControl
        init(_ parent: FillSegmentedControl) { self.parent = parent }
        @objc func changed(_ sender: NSSegmentedControl) { parent.selection = sender.selectedSegment }
    }
}

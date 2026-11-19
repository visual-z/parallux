import AppKit
import Charts
import ParalluxKit
import SwiftUI

/// The overview's three cards as design v0.2 lays them out. They take values
/// and bindings only, so they can be rendered on their own with any numbers;
/// OverviewView feeds them from the live session.

/// A row of cards of equal height; in a window too narrow for them side by
/// side they stack (docs/design/copy-and-style.md §2, 响应式).
struct OverviewCardRow<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) { content }.fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 12) { content }
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
        // Why 190: the narrowest a card can be before 「本次会话 ↓ … · ↑ …」
        // truncates; below three of these the row stacks.
        .frame(minWidth: 190, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .quaternarySystemFill), in: RoundedRectangle(cornerRadius: 14))
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

    var body: some View {
        OverviewCard(title: DashboardCard.traffic.title) {
            Text(RateFormat.bitsPerSecond(rate)).font(.title.weight(.semibold)).monospacedDigit()
            Chart(Array(history.enumerated()), id: \.offset) { index, value in
                AreaMark(x: .value("t", index), y: .value("速率", value)).foregroundStyle(.tint.opacity(0.14))
                LineMark(x: .value("t", index), y: .value("速率", value)).foregroundStyle(.tint)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            .chartXAxis(.hidden).chartYAxis(.hidden).chartLegend(.hidden)
            .chartXScale(domain: 0...max(window - 1, 1))
            .frame(height: 46)
            .accessibilityHidden(true)
            Text("本次会话 ↓ \(RateFormat.bytes(downlinkTotal)) · ↑ \(RateFormat.bytes(uplinkTotal))")
                .font(.subheadline).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
        }
    }
}

struct RouteModeCard: View {
    /// The clash modes the running configuration offers (often just one).
    let modes: [String]
    @Binding var mode: String
    /// 「命中最多：…」 (OverviewCopy.topRule); nil before any rule was hit.
    var topRule: String?
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
                Text(topRule).font(.subheadline).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
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
            Text(title).font(.callout.weight(.medium)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch).controlSize(.small)
    }
}

struct ProfileCard: View {
    let name: String?
    let detail: String
    let connections: Int?
    let memory: Int64?

    var body: some View {
        OverviewCard(title: DashboardCard.profile.title) {
            if let name {
                Text(name).font(.title3.weight(.semibold)).lineLimit(1)
                Text(detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            } else {
                Text("无配置").font(.title3.weight(.semibold)).foregroundStyle(.secondary)
            }
            if let connections, let memory {
                Text("连接 \(connections) · 内存 \(RateFormat.bytes(memory))")
                    .font(.subheadline).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
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

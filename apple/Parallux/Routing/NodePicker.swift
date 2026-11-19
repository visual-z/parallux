import ParalluxKit
import SwiftUI

/// The inspector beside the route map: one exit, the traffic that uses it,
/// and its node picker.
struct ExitInspector: View {
    let model: RoutingModel
    let exit: String?
    let reroute: (TrafficClass) -> Void
    @Environment(AppModel.self) private var app

    var body: some View {
        if let exit {
            let map = model.map(app: app)
            let users = map.classes.filter { $0.exit == exit }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("代理组").font(.caption).foregroundStyle(.secondary)
                        Text(exit).font(.title3.weight(.semibold))
                        ChainView(chain: model.chain(exit, app: app))
                    }
                    if !users.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("规则").font(.caption).foregroundStyle(.secondary)
                            ForEach(users) { item in
                                HStack {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(item.name).font(.callout)
                                        Text(item.rate > 0 ? RateFormat.bitsPerSecond(item.rate) : "暂无流量").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button("编辑规则…") { reroute(item) }.controlSize(.small)
                                }
                                .padding(.vertical, 3)
                            }
                        }
                    }
                    if let group = app.session.groups.first(where: { $0.tag == exit }) {
                        NodePicker(group: group)
                    } else if exit.hasPrefix("direct") {
                        GroupBox {
                            Text("\(app.effectiveMode?.title ?? "直接连接") · \(app.enabledLinks.map(\.kind.title).joined(separator: " + "))")
                                .font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(16)
            }
        } else {
            ContentUnavailableView("选择一个出口", systemImage: "arrow.triangle.branch")
        }
    }
}

/// One group as a picker: region filter, latency sort and distribution,
/// sub-groups as rows that show their own current pick (design v0.3).
struct NodePicker: View {
    let group: OutboundGroupModel
    @Environment(AppModel.self) private var app
    @State private var region: String?
    @State private var expanded: String?

    private var groupsByTag: [String: OutboundGroupModel] {
        Dictionary(app.session.groups.map { ($0.tag, $0) }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        let session = app.session
        let subgroups = group.items.filter { groupsByTag[$0.tag] != nil }
        let nodes = group.items.filter { groupsByTag[$0.tag] == nil }
        let regions = Self.regions(nodes)
        let shown = nodes.filter { region == nil || NodeTraits.infer($0.tag).region == region }
            .sorted { a, b in
                let da = a.delay > 0 ? a.delay : .max, db = b.delay > 0 ? b.delay : .max
                return da != db ? da < db : a.tag < b.tag
            }
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(group.tag).font(.headline)
                KindBadge(type: group.type)
                if session.testing.contains(group.tag) { ProgressView().controlSize(.mini) }
                Spacer()
                Button("测速", systemImage: "bolt") { session.urlTest(group: group.tag) }
                    .labelStyle(.iconOnly).disabled(session.testing.contains(group.tag)).help("延迟测试")
            }
            if group.type == "urltest" { AutoExplanation(group: group) }
            if regions.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        RegionChip(title: "全部", count: nodes.count, on: region == nil) { region = nil }
                        ForEach(regions, id: \.0) { name, count in
                            RegionChip(title: name, count: count, on: region == name) { region = region == name ? nil : name }
                        }
                    }
                }
            }
            LatencyHistogram(delays: nodes.map(\.delay))
            if !subgroups.isEmpty {
                Text("代理组").font(.caption).foregroundStyle(.secondary)
                ForEach(subgroups) { item in
                    let sub = groupsByTag[item.tag]!
                    let current = sub.items.first { $0.tag == sub.selected }
                    NodeRow(title: item.tag, detail: sub.selected,
                            delay: current?.delay ?? 0, selected: item.tag == group.selected, chevron: expanded == item.tag ? .down : .right)
                        .onTapGesture { if group.selectable { session.select(group: group.tag, outbound: item.tag) } }
                        .contextMenu { Button(expanded == item.tag ? "收起" : "在这里展开") { expanded = expanded == item.tag ? nil : item.tag } }
                    if expanded == item.tag {
                        NodePicker(group: sub).padding(.leading, 12)
                    }
                }
                if !nodes.isEmpty { Text("按延迟排序").font(.caption).foregroundStyle(.secondary) }
            }
            LazyVStack(spacing: 2) {
                ForEach(shown) { item in
                    let traits = NodeTraits.infer(item.tag)
                    NodeRow(title: item.tag, detail: [item.type, traits.multiplier].compactMap { $0 }.joined(separator: " · "),
                            delay: item.delay, selected: item.tag == group.selected, chevron: nil)
                        .onTapGesture {
                            // An automatic group cannot be pointed at a node; the panel explains how to pin one.
                            if group.selectable { session.select(group: group.tag, outbound: item.tag) }
                        }
                }
            }
        }
    }

    static func regions(_ nodes: [OutboundGroupModel.Item]) -> [(String, Int)] {
        var counts: [String: Int] = [:]
        var order: [String] = []
        for node in nodes {
            let region = NodeTraits.infer(node.tag).region
            if counts[region] == nil { order.append(region) }
            counts[region, default: 0] += 1
        }
        // Most nodes first; 其他 always last.
        let sorted = order.sorted { a, b in
            if a == NodeTraits.otherRegion { return false }
            if b == NodeTraits.otherRegion { return true }
            let ca = counts[a] ?? 0
            let cb = counts[b] ?? 0
            return ca > cb
        }
        return sorted.map { ($0, counts[$0] ?? 0) }
    }
}

private struct AutoExplanation: View {
    let group: OutboundGroupModel
    var body: some View {
        let current = group.items.first { $0.tag == group.selected }
        GroupBox {
            VStack(alignment: .leading, spacing: 4) {
                Text("当前节点：\(group.selected)\(current.map { $0.delay > 0 ? " · \($0.delay) ms" : "" } ?? "")").font(.callout.weight(.medium))
                Text("根据 URL 测试延迟选择代理").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct RegionChip: View {
    let title: String
    let count: Int
    let on: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text("\(title) \(count)").font(.caption).padding(.horizontal, 9).padding(.vertical, 3)
                .foregroundStyle(on ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .background(on ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Bars of how many nodes fall in each 100 ms bucket, coloured by grade.
private struct LatencyHistogram: View {
    let delays: [Int32]
    var body: some View {
        let tested = delays.filter { $0 > 0 }.sorted()
        // Why 12 buckets of 100 ms: covers the 0–1200 ms range where choices matter; slower ones pile into the last.
        let buckets = (0..<12).map { index in tested.filter { min(Int($0) / 100, 11) == index }.count }
        let peak = max(buckets.max() ?? 1, 1)
        VStack(alignment: .leading, spacing: 4) {
            Text(tested.isEmpty ? "还没有测速" : "延迟分布 · \(tested.count)/\(delays.count) 个节点已测 · 中位 \(tested[tested.count / 2]) ms")
                .font(.caption).foregroundStyle(.secondary)
            if !tested.isEmpty {
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(Array(buckets.enumerated()), id: \.offset) { index, count in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(LatencyGrade(milliseconds: Int32(index * 100 + 1)).color.opacity(count > 0 ? 0.7 : 0.15))
                            .frame(height: 4 + 30 * CGFloat(count) / CGFloat(peak))
                    }
                }
                .frame(height: 34, alignment: .bottom)
                .accessibilityLabel("延迟分布")
            }
        }
    }
}

struct NodeRow: View {
    enum Chevron { case right, down }
    let title: String
    let detail: String
    let delay: Int32
    let selected: Bool
    let chevron: Chevron?

    var body: some View {
        let grade = LatencyGrade(milliseconds: delay)
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout).lineLimit(1)
                if !detail.isEmpty { Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer(minLength: 6)
            if delay > 0 {
                Capsule().fill(.quaternary).frame(width: 54, height: 4)
                    .overlay(alignment: .leading) { Capsule().fill(grade.color).frame(width: 54 * min(1, CGFloat(delay) / 1200), height: 4) }
            }
            Text(delay > 0 ? "\(delay) ms" : "—").font(.caption.weight(.semibold)).monospacedDigit()
                .foregroundStyle(grade.color).frame(width: 58, alignment: .trailing)
            if let chevron { Image(systemName: chevron == .down ? "chevron.down" : "chevron.right").font(.caption2).foregroundStyle(.tertiary) }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(selected ? AnyShapeStyle(.tint.opacity(0.14)) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

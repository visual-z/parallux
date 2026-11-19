import ParalluxKit
import SwiftUI

/// 分组 view: the classic Clash-style list the author asked to keep — every
/// group with its pick, collapsible node grids, per-group test. Improved only
/// where the old one was unreadable: the collapsed state shows the flattened
/// chain and a latency summary instead of anonymous dots.
struct GroupsView: View {
    let search: String
    @Environment(AppModel.self) private var app

    var body: some View {
        let session = app.session
        if session.groups.isEmpty {
            ContentUnavailableView("暂无可用代理组", systemImage: "square.grid.2x2")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(session.groups) { group in
                        ClassicGroup(group: group, search: search)
                    }
                }
                .padding(20)
            }
        }
    }
}

private struct ClassicGroup: View {
    let group: OutboundGroupModel
    let search: String
    @Environment(AppModel.self) private var app
    @AppStorage private var collapsed: Bool

    init(group: OutboundGroupModel, search: String) {
        self.group = group
        self.search = search
        _collapsed = AppStorage(wrappedValue: group.items.count > 24, "nodes.collapsed.\(group.tag)")
    }

    static func allTags(_ groups: [OutboundGroupModel]) -> Set<String> {
        var tags = Set(groups.map(\.tag))
        for group in groups { tags.formUnion(group.items.map(\.tag)) }
        return tags
    }

    private var items: [OutboundGroupModel.Item] {
        search.isEmpty ? group.items : group.items.filter { $0.tag.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        let session = app.session
        let groupTags = Set(session.groups.map(\.tag))
        let chain = ExitChain.flatten(group.tag, groups: session.groups, outbounds: Self.allTags(session.groups))
        if !items.isEmpty || search.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Button {
                        withAnimation(.snappy) { collapsed.toggle() }
                    } label: {
                        Image(systemName: "chevron.right").rotationEffect(.degrees(collapsed && search.isEmpty ? 0 : 90))
                    }
                    .buttonStyle(.borderless)
                    .help(collapsed ? "展开" : "折叠")
                    Text(group.tag).font(.headline)
                    KindBadge(type: group.type)
                    Text("\(group.items.count)").font(.caption).foregroundStyle(.secondary)
                        .padding(.horizontal, 6).background(.quaternary, in: Capsule())
                    if session.testing.contains(group.tag) { ProgressView().controlSize(.mini) }
                    Spacer()
                    if collapsed && search.isEmpty { ChainView(chain: chain) }
                    Button("测速", systemImage: "bolt") { session.urlTest(group: group.tag) }
                        .labelStyle(.iconOnly).buttonStyle(.borderless)
                        .disabled(session.testing.contains(group.tag)).help("延迟测试")
                }
                if collapsed && search.isEmpty {
                    LatencySummary(items: group.items)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 8)], spacing: 8) {
                        ForEach(items) { item in
                            ClassicCard(item: item, isGroup: groupTags.contains(item.tag), selected: item.tag == group.selected)
                                .onTapGesture { if group.selectable { session.select(group: group.tag, outbound: item.tag) } }
                        }
                    }
                }
            }
        }
    }
}

/// Collapsed group: counts per latency grade instead of unlabelled dots.
private struct LatencySummary: View {
    let items: [OutboundGroupModel.Item]
    var body: some View {
        let grades = items.map { LatencyGrade(milliseconds: $0.delay) }
        HStack(spacing: 12) {
            ForEach([LatencyGrade.fast, .medium, .slow, .untested], id: \.self) { grade in
                let count = grades.filter { $0 == grade }.count
                if count > 0 {
                    Label("\(count)", systemImage: "circle.fill").foregroundStyle(grade.color)
                        .font(.caption).labelStyle(.titleAndIcon).imageScale(.small)
                        .help(Self.title(grade))
                }
            }

        }
    }

    static func title(_ grade: LatencyGrade) -> String {
        switch grade {
        case .fast: "低于 400 ms"
        case .medium: "400–800 ms"
        case .slow: "800 ms 以上"
        case .untested: "未测速"
        }
    }
}

private struct ClassicCard: View {
    let item: OutboundGroupModel.Item
    let isGroup: Bool
    let selected: Bool

    var body: some View {
        let grade = LatencyGrade(milliseconds: item.delay)
        let traits = NodeTraits.infer(item.tag)
        VStack(alignment: .leading, spacing: 6) {
            Text(item.tag).font(.callout.weight(.medium)).lineLimit(1)
            HStack {
                Text(isGroup ? "分组" : [item.type, traits.multiplier].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Text(item.delay > 0 ? "\(item.delay) ms" : "—").font(.caption.weight(.semibold)).monospacedDigit().foregroundStyle(grade.color)
            }
        }
        .padding(10)
        .background(selected ? AnyShapeStyle(.tint.opacity(0.14)) : AnyShapeStyle(.background), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: selected ? 1.5 : 1))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

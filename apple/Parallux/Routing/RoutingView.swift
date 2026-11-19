import ParalluxKit
import SwiftUI

/// 主窗口「路由」(decision 20, design v0.3): one page, two views of the same
/// routes plus an explainer. Route map starts from traffic; Groups is the
/// classic Clash-style list; 试一下 explains one target.
struct RoutingView: View {
    @Environment(AppModel.self) private var app
    @State private var model = RoutingModel()
    @AppStorage("routing.view") private var view: RoutingModel.View = .map
    @State private var search = ""
    @State private var selectedExit: String?
    @State private var showInspector = true
    @State private var rerouting: TrafficClass?
    @State private var explainTarget = ""

    var body: some View {
        Group {
            if !app.session.isRunning {
                ContentUnavailableView {
                    Label("未连接", systemImage: "arrow.triangle.branch")
                } description: {
                    Text("内核暂不可用")
                } actions: {
                    Button("连接") { Task { await app.setOn(true) } }.buttonStyle(.borderedProminent)
                }
            } else {
                switch view {
                case .map:
                    RouteMapView(model: model, search: search, selectedExit: $selectedExit, reroute: { rerouting = $0 })
                case .groups:
                    GroupsView(search: search)
                case .explain:
                    ExplainView(model: model, target: $explainTarget, reroute: { rerouting = $0 })
                }
            }
        }
        .navigationSubtitle(subtitle)
        .searchable(text: $search, placement: .toolbar, prompt: "搜索")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("视图", selection: $view) {
                    ForEach(RoutingModel.View.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            ToolbarItem { RouteModeMenu() }
            ToolbarItem {
                Button("延迟测试", systemImage: "bolt") {
                    app.session.urlTest(groups: app.session.groups.map(\.tag))
                }
                .disabled(!app.session.isRunning || !app.session.testing.isEmpty)
                .help("延迟测试")
            }
            if view == .map {
                ToolbarItem {
                    Button("检查器", systemImage: "sidebar.trailing") { showInspector.toggle() }.help("显示检查器")
                }
            }
        }
        .inspector(isPresented: Binding(get: { showInspector && view == .map && app.session.isRunning }, set: { showInspector = $0 })) {
            ExitInspector(model: model, exit: selectedExit ?? model.profile.final ?? model.profile.rules.compactMap(\.outbound).first, reroute: { rerouting = $0 })
                .inspectorColumnWidth(min: 300, ideal: 340, max: 420)
        }
        .sheet(item: $rerouting) { item in RerouteSheet(model: model, item: item) }
        .task(id: app.profiles.store.selectedID) { await model.load(app) }
        .onAppear(perform: consumePendingTarget)
        .onReceive(NotificationCenter.default.publisher(for: .explainRoute)) { _ in consumePendingTarget() }
        .onAppear { app.session.retainConnections() }
        .onDisappear { app.session.releaseConnections() }
    }

    private func consumePendingTarget() {
        guard let target = app.pendingExplainTarget else { return }
        app.pendingExplainTarget = nil
        explainTarget = target
        view = .explain
    }

    private var subtitle: String {
        let profile = model.profile
        guard app.session.isRunning else { return "" }
        return "\(RouteMode.title(app.session.routeMode ?? "")) · \(profile.rules.filter { $0.outbound != nil }.count) 条规则 · \(app.session.groups.count) 个代理组"
    }
}

extension Notification.Name {
    /// Open 路由 › 试一下 for AppModel.pendingExplainTarget (connections inspector).
    static let explainRoute = Notification.Name("parallux.explainRoute")
}

// MARK: route map

/// Traffic classes → exits, band width = share of the traffic (same language
/// as the overview). Sampled once a second from RoutingModel.steadyMap, so
/// rows keep their place while connections come and go.
private struct RouteMapView: View {
    let model: RoutingModel
    let search: String
    @Binding var selectedExit: String?
    let reroute: (TrafficClass) -> Void
    @Environment(AppModel.self) private var app
    @State private var selectedClass: String?
    @State private var map = RoutingModel.SteadyMap()
    /// Shows the rules folded away past RouteMap.maxClasses.
    @State private var showsAll = false

    private func matches(_ item: TrafficClass) -> Bool {
        search.isEmpty || item.name.localizedCaseInsensitiveContains(search) || item.condition.localizedCaseInsensitiveContains(search)
            || item.exit.localizedCaseInsensitiveContains(search)
    }

    var body: some View {
        let active = map.active.filter(matches), idle = map.idle.filter(matches)
        // Everything with traffic, then idle rules up to the limit; a search shows every match.
        let room = showsAll || !search.isEmpty ? idle.count : max(0, RouteMap.maxClasses - active.count)
        let classes = active + idle.prefix(room)
        let hidden = idle.count - min(room, idle.count)
        let focus = classes.first { $0.id == selectedClass }
        Group {
            if map.isEmpty {
                ContentUnavailableView {
                    Label("暂无规则", systemImage: "arrow.triangle.branch")
                } description: {
                    Text(model.profileError ?? "所有流量走默认出口")
                }
            } else if classes.isEmpty {
                ContentUnavailableView.search(text: search)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        RouteColumns(classes: classes, idle: Set(idle.map(\.id)), shares: map.shares, focus: focus, selectedExit: $selectedExit,
                                     select: { item in
                                         selectedClass = selectedClass == item.id ? nil : item.id
                                         if selectedClass != nil { selectedExit = item.exit }
                                     }, reroute: reroute, chain: { model.chain($0, app: app) })
                        if hidden > 0 || showsAll, search.isEmpty {
                            Button(showsAll ? "收起没有流量的规则" : "显示其余 \(hidden) 条规则") { showsAll.toggle() }
                                .buttonStyle(.bordered).buttonBorderShape(.capsule)
                        }
                    }
                    .padding(.horizontal, DesignMetrics.pageInset).padding(.vertical, 12)
                }
            }
        }
        // Once a second, like the connections stream it follows; again at once when the profile or its overrides change.
        .task(id: model.profile) {
            while !Task.isCancelled {
                let next = model.steadyMap(app: app, at: ProcessInfo.processInfo.systemUptime)
                if next != map { map = next }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

private struct LatencyLegend: View {
    var body: some View {
        HStack(spacing: 6) {
            Text("延迟")
            Circle().fill(LatencyGrade.fast.color).frame(width: 6, height: 6).help("延迟良好 · 400 ms 以内")
            Circle().fill(LatencyGrade.medium.color).frame(width: 6, height: 6).help("延迟中等 · 400–800 ms")
            Circle().fill(LatencyGrade.slow.color).frame(width: 6, height: 6).help("延迟较高 · 800 ms 以上")
        }
    }
}

extension LatencyGrade {
    var color: Color {
        switch self {
        case .untested: .secondary
        case .fast: .green
        case .medium: .orange
        case .slow: .red
        }
    }
}

/// Measured row frames, for drawing the bands between the two columns.
private struct RowFrame: Equatable {
    var id: String
    var rect: CGRect
}

private struct RowFrameKey: PreferenceKey {
    static let defaultValue: [RowFrame] = []
    static func reduce(value: inout [RowFrame], nextValue: () -> [RowFrame]) { value += nextValue() }
}

private extension View {
    func reportFrame(_ id: String, in space: String) -> some View {
        background(GeometryReader { proxy in
            Color.clear.preference(key: RowFrameKey.self, value: [RowFrame(id: id, rect: proxy.frame(in: .named(space)))])
        })
    }
}

private struct RouteColumns: View {
    let classes: [TrafficClass]
    /// Classes without traffic lately: drawn quieter.
    let idle: Set<String>
    /// Share of the smoothed traffic by class id.
    let shares: [String: Double]
    let focus: TrafficClass?
    @Binding var selectedExit: String?
    let select: (TrafficClass) -> Void
    let reroute: (TrafficClass) -> Void
    let chain: (String) -> ExitChain
    @State private var frames: [RowFrame] = []
    private static let palette: [Color] = [.red, .purple, .blue, .teal, .orange, .pink, .indigo, .mint, .brown, .cyan, .green, .yellow]

    /// By the rule's place in the profile, not its place on screen: a class
    /// keeps its colour when rows come and go.
    private func color(_ item: TrafficClass) -> Color {
        if item.exit.hasPrefix("direct") || item.exit == "直连" { return .gray }
        return Self.palette[(item.ruleIndex ?? Self.palette.count - 1) % Self.palette.count]
    }

    /// Exits of the rows shown, in the order the rows first use them.
    private var exits: [String] {
        var result: [String] = []
        for item in classes where !result.contains(item.exit) { result.append(item.exit) }
        return result
    }

    /// Why 22 and 2: a band as thick as a row would hide its neighbours; one
    /// thinner than 2 pt cannot be seen. The square root keeps a class with a
    /// tenth of the traffic at a third of the width, still readable.
    private func width(_ item: TrafficClass) -> CGFloat {
        guard let share = shares[item.id], share > 0 else { return 1 }
        return max(2, 22 * CGFloat(share.squareRoot()))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                for item in classes {
                    guard let from = frames.first(where: { $0.id == "c-" + item.id })?.rect,
                          let to = frames.first(where: { $0.id == "e-" + item.exit })?.rect else { continue }
                    let start = CGPoint(x: from.maxX, y: from.midY)
                    let end = CGPoint(x: to.minX, y: to.midY)
                    let mid = (start.x + end.x) / 2
                    var path = Path()
                    path.move(to: start)
                    path.addCurve(to: end, control1: CGPoint(x: mid, y: start.y), control2: CGPoint(x: mid, y: end.y))
                    let dimmed = focus != nil && focus?.id != item.id
                    let carries = (shares[item.id] ?? 0) > 0
                    let shade = carries ? color(item) : Color.secondary
                    context.stroke(path, with: .color(shade.opacity(dimmed ? 0.08 : carries ? 0.5 : 0.25)),
                                   style: StrokeStyle(lineWidth: width(item), lineCap: .round))
                }
            }
            .allowsHitTesting(false)
            ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("流量类别").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        Spacer()
                        Text("宽度 = 流量占比").font(.caption).foregroundStyle(.tertiary)
                    }
                    ForEach(classes) { item in
                        TrafficRow(item: item, tint: color(item), selected: focus?.id == item.id,
                                   dimmed: focus != nil && focus?.id != item.id, quiet: idle.contains(item.id))
                            .reportFrame("c-" + item.id, in: "routes")
                            .onTapGesture { select(item) }
                            .contextMenu {
                                Button("编辑规则…") { reroute(item) }
                                Button("当前节点") { selectedExit = item.exit }
                            }
                    }
                }
                // Why 150, and why the ideal width is pinned to it: ViewThatFits
                // picks a branch by its ideal size, and a column's ideal width
                // is its longest line of text (a rule can name a dozen rule
                // sets). Left to the content, two columns never "fitted" beside
                // the inspector and the page fell back to the plain list with
                // no bands at all. 150 is the narrowest a row reads at.
                .frame(minWidth: 150, idealWidth: 150, maxWidth: .infinity)
                // The bands need room to curve; fixed so both columns can grow.
                Color.clear.frame(width: 56)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("出口").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        Spacer()
                        LatencyLegend().font(.caption).foregroundStyle(.tertiary)
                    }
                    ForEach(exits, id: \.self) { exit in
                        ExitRow(exit: exit, chain: chain(exit), selected: selectedExit == exit,
                                dimmed: focus != nil && focus?.exit != exit)
                            .reportFrame("e-" + exit, in: "routes")
                            .onTapGesture { selectedExit = exit }
                    }
                }
                .frame(minWidth: 150, idealWidth: 150, maxWidth: .infinity)
            }
            // Too narrow for two columns and the bands: a plain list, the exit under each rule.
            VStack(alignment: .leading, spacing: 6) {
                ForEach(classes) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        TrafficRow(item: item, tint: color(item), selected: focus?.id == item.id, dimmed: false, quiet: idle.contains(item.id))
                        ChainView(chain: chain(item.exit)).padding(.leading, 12)
                    }
                    .onTapGesture { selectedExit = item.exit }
                    .contextMenu { Button("编辑规则…") { reroute(item) } }
                }
            }
            }
        }
        .coordinateSpace(name: "routes")
        .onPreferenceChange(RowFrameKey.self) { frames = $0 }
        .animation(.snappy, value: focus?.id)
        // Rows that change section slide to their new place instead of jumping.
        .animation(.easeInOut(duration: 0.35), value: classes.map(\.id))
    }
}

private struct TrafficRow: View {
    let item: TrafficClass
    let tint: Color
    let selected: Bool
    let dimmed: Bool
    /// No traffic lately (design: 没流量的类别淡显).
    var quiet = false

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5).fill(tint).frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(item.name).font(.body).lineLimit(1)
                    if item.overridden {
                        Text("已覆写").font(.caption2.weight(.semibold)).foregroundStyle(.tint)
                            .padding(.horizontal, 5).padding(.vertical, 1).background(.tint.opacity(0.15), in: Capsule())
                    }
                }
                Text(item.condition).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 4)
            Text(item.rate > 0 ? RateFormat.bitsPerSecond(item.rate) : "—").font(.callout).monospacedDigit()
                .foregroundStyle(item.rate > 0 ? .primary : .tertiary)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(selected ? AnyShapeStyle(.selection.opacity(0.35)) : AnyShapeStyle(.fill.quinary), in: RoundedRectangle(cornerRadius: 8))
        .help("\(item.connections) 个连接 · \(item.exit)")
        .opacity(dimmed ? 0.35 : quiet ? 0.6 : 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(item.exit)
    }
}

private struct ExitRow: View {
    let exit: String
    let chain: ExitChain
    let selected: Bool
    let dimmed: Bool
    @Environment(AppModel.self) private var app

    var body: some View {
        let group = app.session.groups.first { $0.tag == exit }
        let last = chain.last.flatMap { tag in app.session.groups.flatMap(\.items).first { $0.tag == tag } }
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(exit).font(.body.weight(.medium))
                if let group { KindBadge(type: group.type) }
                Spacer()
                if let last, last.delay > 0 {
                    Text("\(last.delay) ms").font(.caption.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(LatencyGrade(milliseconds: last.delay).color)
                }
            }
            if chain.hops.count > 1 || chain.ending != .node {
                ChainView(chain: chain)
            } else if exit.hasPrefix("direct") {
                Text("直接连接 (DIRECT)").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(selected ? AnyShapeStyle(.selection.opacity(0.35)) : AnyShapeStyle(.fill.quinary), in: RoundedRectangle(cornerRadius: 8))
        .opacity(dimmed ? 0.35 : 1)
        .contentShape(Rectangle())
    }
}

struct KindBadge: View {
    let type: String
    var body: some View {
        // CVR strategies: select = 手动选择代理, url-test = 根据 URL 测试延迟选择代理 (short forms).
        Text(type == "urltest" ? "URLTest" : type == "selector" ? "Selector" : type == "direct" ? "Direct" : type)
            .font(.caption2).foregroundStyle(.secondary)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
    }
}

/// proxy › DE Auto › DE-1 AnyTLS, the last hop highlighted.
struct ChainView: View {
    let chain: ExitChain
    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(chain.hops.enumerated()), id: \.offset) { index, hop in
                if index > 0 { Image(systemName: "chevron.compact.right").font(.caption2).foregroundStyle(.tertiary) }
                let isLast = index == chain.hops.count - 1
                Text(hop).font(.caption.weight(isLast ? .semibold : .regular)).lineLimit(1)
                    .foregroundStyle(isLast ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(isLast ? AnyShapeStyle(.tint.opacity(0.14)) : AnyShapeStyle(.quaternary), in: RoundedRectangle(cornerRadius: 5))
            }
            switch chain.ending {
            case .cycle: Label("循环引用", systemImage: "exclamationmark.triangle").font(.caption2).foregroundStyle(.orange)
            case .tooDeep: Label("层级过深", systemImage: "exclamationmark.triangle").font(.caption2).foregroundStyle(.orange)
            case .missing: Label("出站不存在", systemImage: "exclamationmark.triangle").font(.caption2).foregroundStyle(.red)
            case .node: EmptyView()
            }
        }
    }
}

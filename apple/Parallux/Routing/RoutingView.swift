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
                ContentUnavailableView("未连接", systemImage: "arrow.triangle.branch",
                                       description: Text("连接后显示路由、分组与实时流量。"))
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
        .searchable(text: $search, placement: .toolbar, prompt: "搜索规则、分组或节点")
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
                Button("全部测速", systemImage: "bolt") {
                    for group in app.session.groups { app.session.urlTest(group: group.tag) }
                }
                .disabled(!app.session.isRunning || !app.session.testing.isEmpty)
                .help("对每个分组测速")
            }
            if view == .map {
                ToolbarItem {
                    Button("检查器", systemImage: "sidebar.trailing") { showInspector.toggle() }
                }
            }
        }
        .inspector(isPresented: Binding(get: { showInspector && view == .map && app.session.isRunning }, set: { showInspector = $0 })) {
            ExitInspector(model: model, exit: selectedExit ?? model.map(app: app).exits.first, reroute: { rerouting = $0 })
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
        return "\(RouteMode.title(app.session.routeMode ?? "")) · \(profile.rules.filter { $0.outbound != nil }.count) 条路由规则 · \(app.session.groups.count) 个分组"
    }
}

extension Notification.Name {
    /// Open 路由 › 试一下 for AppModel.pendingExplainTarget (connections inspector).
    static let explainRoute = Notification.Name("parallux.explainRoute")
}

// MARK: route map

/// Traffic classes → exits, band width = live rate (same language as the overview).
private struct RouteMapView: View {
    let model: RoutingModel
    let search: String
    @Binding var selectedExit: String?
    let reroute: (TrafficClass) -> Void
    @Environment(AppModel.self) private var app
    @State private var selectedClass: String?

    var body: some View {
        let map = model.map(app: app)
        let classes = map.classes.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.condition.localizedCaseInsensitiveContains(search) || $0.exit.localizedCaseInsensitiveContains(search) }
        let focus = classes.first { $0.id == selectedClass }
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) {
                    Label("宽度 = 实时速率", systemImage: "line.3.horizontal")
                    Label("点一类流量只看它的路径", systemImage: "hand.tap")
                    LatencyLegend()
                }
                .font(.caption).foregroundStyle(.secondary).labelStyle(.titleOnly)
                if map.classes.isEmpty {
                    ContentUnavailableView("没有路由规则", systemImage: "arrow.triangle.branch",
                                           description: Text(model.profileError ?? "当前配置没有 route.rules，所有流量走默认出口。"))
                } else {
                    RouteColumns(classes: classes, exits: map.exits, focus: focus, selectedExit: $selectedExit,
                                 select: { item in
                                     selectedClass = selectedClass == item.id ? nil : item.id
                                     if selectedClass != nil { selectedExit = item.exit }
                                 }, reroute: reroute, chain: { model.chain($0, app: app) })
                    if map.hiddenCount > 0 {
                        Text("另有 \(map.hiddenCount) 类流量 · \(RateFormat.bitsPerSecond(map.hiddenRate))（在「试一下」或规则表里查看）")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(20)
        }
    }
}

private struct LatencyLegend: View {
    var body: some View {
        HStack(spacing: 6) {
            Text("延迟")
            Text("<400").foregroundStyle(LatencyGrade.fast.color)
            Text("<800").foregroundStyle(LatencyGrade.medium.color)
            Text("≥800 ms").foregroundStyle(LatencyGrade.slow.color)
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
    let exits: [String]
    let focus: TrafficClass?
    @Binding var selectedExit: String?
    let select: (TrafficClass) -> Void
    let reroute: (TrafficClass) -> Void
    let chain: (String) -> ExitChain
    @State private var frames: [RowFrame] = []
    private static let palette: [Color] = [.red, .purple, .blue, .teal, .orange, .pink, .indigo, .mint, .brown, .cyan, .green, .yellow]

    private func color(_ item: TrafficClass) -> Color {
        if item.exit.hasPrefix("direct") || item.exit == "直连" { return .gray }
        let index = classes.firstIndex(of: item) ?? 0
        return Self.palette[index % Self.palette.count]
    }

    var body: some View {
        let maxRate = max(classes.map(\.rate).max() ?? 1, 1)
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
                    // Width grows with the square root of the rate so one heavy
                    // download does not flatten every other band.
                    let width = item.rate > 0 ? max(2, 22 * sqrt(Double(item.rate) / Double(maxRate))) : 1
                    let dimmed = focus != nil && focus?.id != item.id
                    let shade = item.rate > 0 ? color(item) : Color.secondary
                    context.stroke(path, with: .color(shade.opacity(dimmed ? 0.08 : 0.5)), style: StrokeStyle(lineWidth: width, lineCap: .round))
                }
            }
            .allowsHitTesting(false)
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("流量类别").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(classes) { item in
                        TrafficRow(item: item, tint: color(item), selected: focus?.id == item.id, dimmed: focus != nil && focus?.id != item.id)
                            .reportFrame("c-" + item.id, in: "routes")
                            .onTapGesture { select(item) }
                            .contextMenu {
                                Button("改走…") { reroute(item) }
                                Button("查看出口") { selectedExit = item.exit }
                            }
                    }
                }
                .frame(minWidth: 220, maxWidth: 320)
                Spacer(minLength: 96)
                VStack(alignment: .leading, spacing: 8) {
                    Text("出口").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(exits, id: \.self) { exit in
                        ExitRow(exit: exit, chain: chain(exit), selected: selectedExit == exit,
                                dimmed: focus != nil && focus?.exit != exit)
                            .reportFrame("e-" + exit, in: "routes")
                            .onTapGesture { selectedExit = exit }
                    }
                }
                .frame(minWidth: 220, maxWidth: 300)
            }
        }
        .coordinateSpace(name: "routes")
        .onPreferenceChange(RowFrameKey.self) { frames = $0 }
        .animation(.snappy, value: focus?.id)
    }
}

private struct TrafficRow: View {
    let item: TrafficClass
    let tint: Color
    let selected: Bool
    let dimmed: Bool

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2).fill(tint).frame(width: 4)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.name).font(.callout.weight(.medium)).lineLimit(1)
                    if item.overridden {
                        Text("已覆盖").font(.caption2.weight(.semibold)).foregroundStyle(.tint)
                            .padding(.horizontal, 5).padding(.vertical, 1).background(.tint.opacity(0.15), in: Capsule())
                    }
                }
                Text(item.condition).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 2) {
                Text(item.rate > 0 ? RateFormat.bitsPerSecond(item.rate) : "—").font(.caption).monospacedDigit()
                if item.connections > 0 { Text("\(item.connections) 条").font(.caption2).foregroundStyle(.secondary) }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: selected ? 2 : 1))
        .opacity(dimmed ? 0.35 : 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("走 \(item.exit)")
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
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(exit).font(.callout.weight(.semibold))
                if let group { KindBadge(type: group.type) }
                Spacer()
                if let last, last.delay > 0 {
                    Text("\(last.delay) ms").font(.caption.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(LatencyGrade(milliseconds: last.delay).color)
                }
            }
            if chain.hops.count > 1 || chain.ending != .node { ChainView(chain: chain) }
        }
        .padding(10)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: selected ? 2 : 1))
        .opacity(dimmed ? 0.35 : 1)
        .contentShape(Rectangle())
    }
}

struct KindBadge: View {
    let type: String
    var body: some View {
        Text(type == "urltest" ? "自动" : type == "selector" ? "手动" : type == "direct" ? "直连" : type)
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

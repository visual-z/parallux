/// The main window's sidebar destinations, in display order.
///
/// Grouping follows the v0.2 design (PLAN decision 7): the unlabeled group is
/// traffic you watch, "聚合" is what Parallux adds to sing-box, "代理" is SFM's
/// proxy surface. Settings is deliberately absent: it lives in its own window
/// (⌘,) per the macOS HIG.
public enum SidebarItem: String, CaseIterable, Identifiable, Sendable {
    case overview, connections, logs
    case links, aggregationServer, diagnostics
    case profiles, outbounds, rules

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .overview: "概览"
        case .connections: "连接"
        case .logs: "日志"
        case .links: "线路"
        case .aggregationServer: "聚合服务器"
        case .diagnostics: "诊断"
        case .profiles: "配置"
        case .outbounds: "节点"
        case .rules: "规则"
        }
    }

    /// SF Symbol name. All nine were checked with `NSImage(systemSymbolName:)`
    /// on macOS 27.2 (2026-11-18); re-check when changing one.
    public var symbol: String {
        switch self {
        case .overview: "gauge.with.dots.needle.67percent"
        case .connections: "arrow.left.arrow.right"
        case .logs: "list.bullet.rectangle"
        case .links: "cable.connector"
        case .aggregationServer: "server.rack"
        case .diagnostics: "stethoscope"
        case .profiles: "doc.text"
        case .outbounds: "globe"
        case .rules: "arrow.triangle.branch"
        }
    }

    public var section: SidebarSection {
        switch self {
        case .overview, .connections, .logs: .traffic
        case .links, .aggregationServer, .diagnostics: .aggregation
        case .profiles, .outbounds, .rules: .proxy
        }
    }
}

public enum SidebarSection: CaseIterable, Identifiable, Sendable {
    case traffic, aggregation, proxy

    public var id: Self { self }

    /// Section header; nil means the group is shown without a header.
    public var title: String? {
        switch self {
        case .traffic: nil
        case .aggregation: "聚合"
        case .proxy: "代理"
        }
    }

    public var items: [SidebarItem] {
        SidebarItem.allCases.filter { $0.section == self }
    }
}

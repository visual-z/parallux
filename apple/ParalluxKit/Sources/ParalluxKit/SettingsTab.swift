/// Tabs of the Settings window (⌘,), in display order. Covers SFM's settings
/// (docs/research/sfm-parity.md) plus Parallux's own aggregation page.
public enum SettingsTab: String, CaseIterable, Identifiable, Sendable {
    case general, aggregation, tunnel, onDemand, core, remoteControl, about

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .general: "通用"
        case .aggregation: "聚合"
        case .tunnel: "隧道"
        case .onDemand: "按需连接"
        case .core: "内核"
        case .remoteControl: "远程控制"
        case .about: ""
        }
    }

    public var symbol: String {
        switch self {
        case .general: "gearshape"
        case .aggregation: "cable.connector"
        case .tunnel: "network.badge.shield.half.filled"
        case .onDemand: "wifi"
        case .core: "cpu"
        case .remoteControl: "desktopcomputer"
        case .about: ""
        }
    }
}

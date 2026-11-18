import AppIntents
import NetworkExtension
import ParalluxKit
import SwiftUI
import WidgetKit

/// The widget extension: a status widget and a Control Center toggle
/// (docs/tasks/feat-system-integration.md).
@main
struct ParalluxWidgetBundle: WidgetBundle {
    var body: some Widget {
        StatusWidget()
        TunnelToggleControl()
    }
}

/// Reads the snapshot the app writes into the App Group.
enum SnapshotSource {
    static var defaults: UserDefaults? {
        AppGroup.identifier(in: .main).flatMap(UserDefaults.init(suiteName:))
    }

    static func load() -> WidgetSnapshot? {
        WidgetSnapshot.decode(defaults?.data(forKey: WidgetSnapshot.defaultsKey))
    }
}

// MARK: status widget

struct StatusEntry: TimelineEntry {
    let date: Date
    /// nil: no App Group (unsigned build) or no snapshot yet.
    let snapshot: WidgetSnapshot?
}

struct StatusProvider: TimelineProvider {
    /// Why 5 min: the app reloads timelines on every state change, so the
    /// timeline only has to notice a quit app turning the snapshot stale.
    static let refresh: TimeInterval = 5 * 60

    func placeholder(in _: Context) -> StatusEntry {
        StatusEntry(date: Date(), snapshot: WidgetSnapshot(connected: true, mode: "bond", linkCount: 3, rate: 76_500_000, profileName: nil, updatedAt: Date()))
    }

    func getSnapshot(in context: Context, completion: @escaping (StatusEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : StatusEntry(date: Date(), snapshot: SnapshotSource.load()))
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<StatusEntry>) -> Void) {
        let now = Date()
        let entry = StatusEntry(date: now, snapshot: SnapshotSource.load())
        completion(Timeline(entries: [entry], policy: .after(now.addingTimeInterval(Self.refresh))))
    }
}

struct StatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "io.github.visual-z.parallux.widget.status", provider: StatusProvider()) { entry in
            StatusWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Parallux")
        .description("连接状态、聚合方式、线路数与实时速率。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct StatusWidgetView: View {
    let entry: StatusEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let snapshot = entry.snapshot, !snapshot.isStale(now: entry.date) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: snapshot.connected ? "point.3.connected.trianglepath.dotted" : "pause.circle")
                    Text(snapshot.connected ? "已连接" : "未连接").font(.headline)
                }
                if snapshot.connected {
                    Text(modeTitle(snapshot)).font(.caption).foregroundStyle(.secondary)
                    Text(RateFormat.bitsPerSecond(snapshot.rate)).font(.title3.weight(.semibold)).monospacedDigit()
                }
                if family == .systemMedium, let profile = snapshot.profileName {
                    Text(profile).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Parallux").font(.headline)
                Text(entry.snapshot == nil ? "打开 Parallux 后显示状态" : "Parallux 未在运行")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func modeTitle(_ snapshot: WidgetSnapshot) -> String {
        let mode = snapshot.mode.flatMap(AggregationMode.init(rawValue:))?.title
        return [mode, "\(snapshot.linkCount) 条线路"].compactMap { $0 }.joined(separator: " · ")
    }
}

// MARK: Control Center toggle

/// Starts or stops the VPN configuration from the widget process, as SFM's
/// ServiceToggleControl does. Starting passes no options: the extension
/// reuses the start options it persisted on the last connection
/// (PacketTunnelProvider resolveStartOptions); before any connection there
/// are none and the start fails with a hint.
enum TunnelSwitch {
    static func manager() async throws -> NETunnelProviderManager? {
        try await NETunnelProviderManager.loadAllFromPreferences().first
    }

    static func isOn() async -> Bool {
        guard let status = try? await manager()?.connection.status else { return false }
        return [.connecting, .connected, .reasserting].contains(status)
    }

    struct NotSetUp: LocalizedError {
        var errorDescription: String? { "请先在 Parallux 里连接一次" }
    }

    static func set(_ on: Bool) async throws {
        guard let manager = try await manager() else { throw NotSetUp() }
        if on {
            if !manager.isEnabled {
                manager.isEnabled = true
                try await manager.saveToPreferences()
            }
            try manager.connection.startVPNTunnel()
        } else {
            if manager.isOnDemandEnabled {
                manager.isOnDemandEnabled = false
                try await manager.saveToPreferences()
            }
            manager.connection.stopVPNTunnel()
        }
    }
}

struct TunnelToggleControl: ControlWidget {
    static let kind = "io.github.visual-z.parallux.widget.toggle"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind, provider: Provider()) { isOn in
            ControlWidgetToggle("Parallux", isOn: isOn, action: ToggleTunnelControlIntent()) { on in
                Label(on ? "已连接" : "未连接", systemImage: "point.3.connected.trianglepath.dotted")
                    .controlWidgetActionHint(on ? "断开" : "连接")
            }
        }
        .displayName("Parallux")
        .description("连接或断开 Parallux。")
    }

    struct Provider: ControlValueProvider {
        var previewValue: Bool { false }
        func currentValue() async throws -> Bool { await TunnelSwitch.isOn() }
    }
}

struct ToggleTunnelControlIntent: SetValueIntent {
    static let title: LocalizedStringResource = "切换 Parallux"

    @Parameter(title: "已连接")
    var value: Bool

    func perform() async throws -> some IntentResult {
        try await TunnelSwitch.set(value)
        return .result()
    }
}

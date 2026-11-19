import ParalluxKit
import SwiftUI

/// The rows of the links, profiles and aggregation server pages and the log
/// box, as design v0.2 draws them. Values and closures only; the pages bind
/// them to the app.

/// Links page: disc, name and interface, addresses, state and rate, more menu, switch.
struct LinkRowView: View {
    struct Status {
        var text: String
        var tone: DesignTag.Tone
    }

    let symbol: String
    let color: Color
    let name: String
    /// 「仅备用」 when the link only waits.
    var badge: String?
    let detail: String
    /// 「IP 地址 …」「外部地址 …」.
    let addresses: [String]
    let status: Status
    /// Rate and active connections; empty while disconnected.
    let activity: String
    @Binding var isOn: Bool
    @Binding var isBackupOnly: Bool

    var body: some View {
        HStack(spacing: 12) {
            DesignIconDisc(symbol: symbol, color: color, isOn: isOn)
            // Wide windows give the addresses their own column; narrow ones
            // put them under the name instead of overflowing.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    names.frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)
                    addressColumn.frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: 2) {
                    names
                    addressColumn
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(alignment: .trailing, spacing: 2) {
                Text(status.text).foregroundStyle(statusColor)
                if !activity.isEmpty { Text(activity).foregroundStyle(.secondary).monospacedDigit() }
            }
            .font(.subheadline).lineLimit(1)
            // A fixed width, so the name and address columns start at the same
            // x in every row whatever the state reads.
            .frame(width: 136, alignment: .trailing)
            DesignMoreMenu {
                Toggle("仅备用", isOn: $isBackupOnly).disabled(!isOn)
            }
            Toggle("启用", isOn: $isOn).toggleStyle(.switch).labelsHidden()
        }
    }

    private var statusColor: AnyShapeStyle {
        switch status.tone {
        case .good: AnyShapeStyle(FlowPalette.proxy)
        case .bad: AnyShapeStyle(.red)
        case .accent: AnyShapeStyle(.tint)
        case .plain: AnyShapeStyle(.secondary)
        }
    }

    private var names: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                Text(name).fontWeight(.semibold).lineLimit(1)
                if let badge { DesignTag(text: badge) }
            }
            Text(detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private var addressColumn: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(addresses, id: \.self) { Text($0).lineLimit(1) }
        }
        .font(.subheadline).foregroundStyle(.secondary).monospacedDigit().textSelection(.enabled)
    }
}

/// Profiles page: kind glyph, name with 「使用中」, what it is, 更新 for remote ones, more menu.
struct ProfileRowView<MenuContent: View>: View {
    let symbol: String
    let name: String
    let inUse: Bool
    let detail: String
    var isUpdating = false
    /// nil for profiles that cannot be updated (local, iCloud).
    var update: (() -> Void)?
    @ViewBuilder var menu: MenuContent

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(inUse ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary)).frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(name).fontWeight(.semibold).lineLimit(1)
                    if inUse { DesignTag(text: "使用中", tone: .accent) }
                }
                Text(detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if isUpdating { ProgressView().controlSize(.small) }
            if let update {
                Button("更新", systemImage: "arrow.clockwise", action: update).designPill().disabled(isUpdating)
            }
            DesignMoreMenu { menu }
        }
    }
}

/// Aggregation server page: glyph, name and address, state tag, latency, 启用 for the others.
struct ServerRowView: View {
    let name: String
    let address: String
    let tag: String
    let tone: DesignTag.Tone
    /// 「12 ms」, or empty when not measured.
    let latency: String
    let latencyColor: Color
    let inUse: Bool
    let enable: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "server.rack").foregroundStyle(inUse ? AnyShapeStyle(FlowPalette.proxy) : AnyShapeStyle(.tertiary)).frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).fontWeight(.semibold).lineLimit(1)
                Text(address).font(.subheadline).foregroundStyle(.secondary).monospacedDigit().lineLimit(1).textSelection(.enabled)
            }
            Spacer(minLength: 8)
            DesignTag(text: tag, tone: tone)
            if !latency.isEmpty { Text(latency).font(.callout).monospacedDigit().foregroundStyle(latencyColor) }
            if !inUse { Button("启用", action: enable).designPill() }
            DesignMoreMenu {
                Button("删除", role: .destructive, action: delete)
            }
        }
    }
}

/// One line of the log box (the design's `.log`): the level in its colour, then the message.
struct LogLineView: View {
    let level: LogLevel
    let message: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(level.title).fontWeight(.semibold).foregroundStyle(color).frame(width: 44, alignment: .leading)
            Text(message).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.subheadline.monospaced())
        .padding(.vertical, 2)
    }

    /// Design: info in the accent colour, warnings orange, errors red, the rest dim.
    private var color: AnyShapeStyle {
        if level <= .error { return AnyShapeStyle(.red) }
        switch level {
        case .warn: return AnyShapeStyle(.orange)
        case .info: return AnyShapeStyle(.tint)
        default: return AnyShapeStyle(.tertiary)
        }
    }
}

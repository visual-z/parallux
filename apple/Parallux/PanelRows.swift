import SwiftUI

/// The menu bar panel's building blocks, laid out as design v0.2's panel:
/// flat rows under a small section title, sections parted by a hairline.
/// Every control is a system control; only the arrangement is the design's.
/// They take values and bindings, so they can be rendered on their own.

/// A titled group of rows (the design's `.p-sec`).
struct PanelSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).padding(.bottom, 4)
            content
        }
        .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 4)
    }
}

/// The hairline between sections (the design's `.p-sep`).
struct PanelSeparator: View {
    var body: some View { Divider().padding(.horizontal, 16).padding(.vertical, 6) }
}

/// One link: a round switch filled with the link's colour while it is on,
/// the name with its 主/备 tag, the interface underneath, and on the right
/// what it carries.
struct PanelLinkRow: View {
    let symbol: String
    let name: String
    var badge: String?
    let detail: String
    let trailing: String
    let color: Color
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 10) {
            Toggle(isOn: $isOn) {
                Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
            }
            .toggleStyle(RoundSwitchStyle(color: color))
            .accessibilityLabel(name)
            .help(isOn ? "停用\(name)" : "启用\(name)")
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(name).lineLimit(1)
                    if let badge {
                        Text(badge).font(.caption2).foregroundStyle(.secondary)
                            .padding(.horizontal, 5).background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                    }
                }
                Text(detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(trailing).font(.callout).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
        }
        .frame(minHeight: 36)
    }
}

/// The design's round link switch (`.cbtn`): 28 pt, filled with the link's
/// colour and a white glyph while on, a quiet grey disc while off. The one
/// control in the panel that is drawn rather than taken from the system: a
/// system button-style Toggle loses its tint whenever its window is not key
/// (rendered both ways on 2026-11-19, on and off came out the same grey), and
/// whether a link is in use has to be readable at a glance.
struct RoundSwitchStyle: ToggleStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            configuration.label
                .foregroundStyle(configuration.isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .frame(width: 28, height: 28)
                .background(configuration.isOn ? AnyShapeStyle(color) : AnyShapeStyle(.quaternary), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(configuration.isOn ? .isSelected : [])
    }
}

/// 聚合 or 代理 (decision 21): a glyph, the name over one line of what it
/// stands for, the system switch on the right.
struct PanelSwitchRow: View {
    let symbol: String
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 14)).foregroundStyle(.secondary).frame(width: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                    Text(detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .toggleStyle(.switch).controlSize(.small)
        .frame(minHeight: 36)
    }
}

/// A label with its control on the right (the design's `.prow`).
struct PanelRow<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack(spacing: 8) {
            Text(title)
            Spacer(minLength: 8)
            trailing
        }
        .frame(minHeight: 30)
    }
}

/// The mini flow strip: the diagram across the whole width, the rates
/// printed over its top right corner; a click opens the main window.
struct PanelStrip<Diagram: View>: View {
    let download: String
    let upload: String
    let action: () -> Void
    @ViewBuilder var diagram: Diagram

    var body: some View {
        Button(action: action) {
            diagram
                .frame(height: 64)
                .overlay(alignment: .topTrailing) {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(download).font(.callout.weight(.semibold))
                        Text("↑ " + upload).font(.caption).foregroundStyle(.secondary)
                    }
                    .monospacedDigit().padding(.trailing, 10).padding(.top, 6)
                }
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
                .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .help("打开主窗口")
    }
}

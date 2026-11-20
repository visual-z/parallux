import ParalluxKit
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

// MARK: Node page

/// The panel's node page as design v0.2 lays it out: a round back button
/// with the title centred, a pill search field beside a round test button,
/// then folding groups of flat rows straight on the panel (no list box, no
/// separators; a row lights up under the pointer). Values and closures only,
/// so it can be rendered on its own.
struct PanelNodeListView: View {
    let sections: [PanelNodeList.Section]
    @Binding var search: String
    /// A delay test is running: the test button waits.
    var isTesting = false
    /// Milliseconds to the colour of its latency grade.
    let delayColor: (Int32) -> Color
    let back: () -> Void
    let testAll: () -> Void
    let toggle: (String) -> Void
    let select: (_ group: String, _ node: String) -> Void

    @FocusState private var searchFocused: Bool

    /// Why 420: design v0.2's cap for the list; taller and the panel would
    /// not fit a 13-inch display under the menu bar together with the header.
    static let maxListHeight: CGFloat = 420

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("节点").font(.headline)
                HStack {
                    Button("返回", systemImage: "chevron.backward", action: back)
                        .labelStyle(.iconOnly).buttonBorderShape(.circle)
                        .keyboardShortcut(.cancelAction)
                        .help("返回")
                    Spacer()
                }
            }
            .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 8)

            HStack(spacing: 6) {
                DesignSearchField(prompt: "搜索", text: $search, height: 28, focus: $searchFocused)
                Button("延迟测试", systemImage: "bolt", action: testAll)
                    .labelStyle(.iconOnly).buttonBorderShape(.circle)
                    .disabled(isTesting || sections.isEmpty)
                    .help("延迟测试")
            }
            .padding(.horizontal, 12).padding(.bottom, 6)

            if sections.isEmpty {
                Group {
                    if search.trimmingCharacters(in: .whitespaces).isEmpty {
                        ContentUnavailableView("暂无可用代理组", systemImage: "globe")
                    } else {
                        ContentUnavailableView.search(text: search)
                    }
                }
                .frame(height: 200)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        // One flat list with ids unique across groups: the same
                        // node usually sits in several groups, and rows that
                        // share an id in one lazy stack are not all drawn.
                        ForEach(lines) { line in
                            if let item = line.item {
                                row(item, in: line.section)
                            } else {
                                groupHeader(line.section)
                            }
                        }
                    }
                    .padding(.horizontal, 8).padding(.bottom, 8)
                }
                .frame(height: listHeight)
            }
        }
        .onAppear { searchFocused = true }
    }

    /// A group header (`item` nil) or one of its nodes.
    private struct Line: Identifiable {
        let section: PanelNodeList.Section
        let item: OutboundGroupModel.Item?
        // U+0000 cannot occur in a tag, so a group and a node never collide.
        var id: String { item.map { "\(section.tag)\u{0}\($0.tag)" } ?? section.tag }
    }

    private var lines: [Line] {
        sections.flatMap { section in
            [Line(section: section, item: nil)] + (section.isOpen ? section.items.map { Line(section: section, item: $0) } : [])
        }
    }

    /// As tall as its rows, up to the cap: a short list does not leave the panel half empty.
    private var listHeight: CGFloat {
        let rows = sections.reduce(0) { $0 + ($1.isOpen ? $1.items.count : 0) }
        return min(Self.maxListHeight, CGFloat(sections.count) * 30 + CGFloat(rows) * 28 + 8)
    }

    private func groupHeader(_ section: PanelNodeList.Section) -> some View {
        Button {
            toggle(section.tag)
        } label: {
            HStack(spacing: 6) {
                Text(section.subtitle.isEmpty ? section.tag : "\(section.tag) · \(section.subtitle)").lineLimit(1)
                Spacer(minLength: 8)
                Image(systemName: "chevron.down").font(.caption2.weight(.bold))
                    .rotationEffect(.degrees(section.isOpen ? 0 : -90))
            }
            .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            .padding(.horizontal, 8).frame(height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(section.isOpen ? "已展开" : "已折叠")
    }

    private func row(_ item: OutboundGroupModel.Item, in section: PanelNodeList.Section) -> some View {
        let picked = item.tag == section.selected
        return Button {
            select(section.tag, item.tag)
        } label: {
            HStack(spacing: 8) {
                // Only the check carries the accent; the name keeps its colour (design).
                Image(systemName: "checkmark").font(.caption.weight(.semibold))
                    .foregroundStyle(section.selectable ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .opacity(picked ? 1 : 0).frame(width: 16)
                Text(item.tag).lineLimit(1)
                Spacer(minLength: 8)
                Text(verbatim: item.delay > 0 ? "\(item.delay) ms" : "—")
                    .font(.callout).monospacedDigit().foregroundStyle(delayColor(item.delay))
            }
        }
        .buttonStyle(PanelRowButtonStyle())
        // A urltest group picks for itself: its rows show the pick but cannot be chosen.
        .allowsHitTesting(section.selectable)
        .accessibilityAddTraits(picked ? .isSelected : [])
    }
}

/// A flat row that lights up under the pointer (the design's `.nitem:hover`).
struct PanelRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Row(configuration: configuration) }

    private struct Row: View {
        let configuration: Configuration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .padding(.horizontal, 8).frame(height: 28)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(configuration.isPressed ? AnyShapeStyle(.tertiary) : hovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
                            in: RoundedRectangle(cornerRadius: 8))
                .contentShape(RoundedRectangle(cornerRadius: 8))
                .onHover { hovering = $0 }
        }
    }
}

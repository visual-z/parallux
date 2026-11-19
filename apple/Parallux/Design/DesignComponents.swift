import AppKit
import ParalluxKit
import SwiftUI

/// The containers design v0.2 builds its pages from (decision 22): a page
/// with one margin, the rounded list card, tags, section headers, code
/// blocks, notes. One implementation for every page, so rows, radii and
/// margins cannot drift apart. Controls inside them stay system controls.
/// Everything here takes values and closures only.
enum DesignMetrics {
    /// Why 20: the system's own margin around a grouped Form, so the pages
    /// that still hold a Form (diagnostics) line up with the ones that do not.
    static let pageInset: CGFloat = 20
    /// The design's `.list` and `.card` radius.
    static let cardRadius: CGFloat = 14
    /// The design's `--content2`: a quiet fill on the opaque content layer.
    static var cardFill: Color { Color(nsColor: .quaternarySystemFill) }
}

/// A scrolling page with the design's margins.
struct DesignPage<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DesignMetrics.pageInset).padding(.vertical, 16)
        }
    }
}

/// The design's `.list`: rows on one rounded card, parted by hairlines.
/// With `move`, a row can be dragged onto another to take its place
/// (ListReorder decides where it lands).
struct DesignList<Item, Row: View>: View {
    let items: [Item]
    let id: (Item) -> String
    /// (dragged row, row it was dropped on).
    var move: ((String, String) -> Void)?
    @ViewBuilder let row: (Item) -> Row

    @State private var target: String?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                if index > 0 { Divider() }
                cell(item)
            }
        }
        .background(DesignMetrics.cardFill, in: RoundedRectangle(cornerRadius: DesignMetrics.cardRadius))
        .clipShape(RoundedRectangle(cornerRadius: DesignMetrics.cardRadius))
    }

    @ViewBuilder private func cell(_ item: Item) -> some View {
        let key = id(item)
        let content = row(item)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        if let move {
            content
                // Where the dragged row will land.
                .overlay(alignment: .top) { if target == key { Rectangle().fill(.tint).frame(height: 2) } }
                .draggable(key)
                .dropDestination(for: String.self) { dropped, _ in
                    // Text dragged in from elsewhere is not one of these rows.
                    guard let dragged = dropped.first, dragged != key, items.contains(where: { id($0) == dragged }) else { return false }
                    move(dragged, key)
                    return true
                } isTargeted: { inside in
                    if inside { target = key } else if target == key { target = nil }
                }
        } else {
            content
        }
    }
}

/// The design's `.tag`.
struct DesignTag: View {
    enum Tone { case plain, good, accent, bad }
    let text: String
    var tone = Tone.plain

    var body: some View {
        Text(text).font(.caption2.weight(.medium)).lineLimit(1)
            .foregroundStyle(foreground)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(background, in: RoundedRectangle(cornerRadius: 5))
    }

    private var foreground: AnyShapeStyle {
        switch tone {
        case .plain: AnyShapeStyle(.secondary)
        case .good: AnyShapeStyle(FlowPalette.proxy)
        case .accent: AnyShapeStyle(.tint)
        case .bad: AnyShapeStyle(.red)
        }
    }

    private var background: AnyShapeStyle {
        switch tone {
        case .plain: AnyShapeStyle(.quaternary)
        case .good: AnyShapeStyle(FlowPalette.proxy.opacity(0.18))
        case .accent: AnyShapeStyle(.tint.opacity(0.14))
        case .bad: AnyShapeStyle(.red.opacity(0.14))
        }
    }
}

/// The design's `.gh`: a section title with something on the right.
struct DesignSectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(title).font(.headline).lineLimit(1)
            Spacer(minLength: 8)
            trailing
        }
        .padding(.top, 16).padding(.bottom, 8)
    }
}

extension DesignSectionHeader where Trailing == Text {
    /// A title with a line of secondary text on the right.
    init(title: String, detail: String) {
        self.init(title: title) { Text(detail).font(.subheadline).foregroundStyle(.secondary) }
    }
}

/// The design's `.code`: selectable monospaced text on a card; long lines scroll sideways.
struct DesignCode: View {
    let text: String
    /// Dimmed text after the code on its last line (the design's inline comment).
    var comment: String?

    var body: some View {
        ScrollView(.horizontal) {
            (Text(text) + Text(comment.map { "   " + $0 } ?? "").foregroundStyle(.tertiary))
                .font(.subheadline.monospaced()).lineSpacing(3).textSelection(.enabled)
                .padding(.horizontal, 14).padding(.vertical, 12)
        }
        .scrollIndicators(.never)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignMetrics.cardFill, in: RoundedRectangle(cornerRadius: 12))
    }
}

/// The design's `.note`.
struct DesignNote: View {
    let text: String
    var body: some View {
        Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

/// The design's `.warnline`.
struct DesignWarning: View {
    let text: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .font(.callout)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// The design's `.kv`: labels on the left, values on the right.
struct DesignKeyValues: View {
    let rows: [(key: String, value: String)]
    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 5) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    Text(row.key).foregroundStyle(.secondary).gridColumnAlignment(.leading)
                    Text(row.value).textSelection(.enabled).multilineTextAlignment(.trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .font(.callout)
    }
}

/// The design's `.cbtn` as a marker: a link's glyph on a disc of its colour, grey when the link is off.
struct DesignIconDisc: View {
    let symbol: String
    let color: Color
    var isOn = true
    var body: some View {
        Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
            .foregroundStyle(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .frame(width: 28, height: 28)
            .background(isOn ? AnyShapeStyle(color) : AnyShapeStyle(.quaternary), in: Circle())
    }
}

/// The design's `.drow`: a label, a bar as long as its share, the value.
struct DesignMeterRow: View {
    let label: String
    /// 0...1.
    let fraction: Double
    let color: Color
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Text(label).lineLimit(1).frame(width: 130, alignment: .leading)
            GeometryReader { proxy in
                Capsule().fill(.quaternary)
                    .overlay(alignment: .leading) {
                        Capsule().fill(color).frame(width: max(0, min(1, fraction)) * proxy.size.width)
                    }
            }
            .frame(height: 14)
            Text(value).monospacedDigit().lineLimit(1).frame(width: 84, alignment: .trailing)
        }
        .font(.callout)
    }
}

extension View {
    /// The design's `.pill-btn`: a system button with a capsule border, at the
    /// regular control size; `primary` fills it with the accent colour.
    @ViewBuilder func designPill(primary: Bool = false) -> some View {
        if primary {
            buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
        } else {
            buttonStyle(.bordered).buttonBorderShape(.capsule)
        }
    }
}

/// The design's `.icon-btn` as a pull-down: 「⋯」 on a 28 pt disc, the whole
/// disc clickable. A borderless Menu draws only its glyph and is about as
/// easy to hit (the author's screenshots, docs/tasks/fix-ui-details.md).
struct DesignMoreMenu<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        Menu {
            content
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 13, weight: .semibold))
                .frame(width: 28, height: 28)
                .background(.quaternary, in: Circle())
                .contentShape(Circle())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .accessibilityLabel("更多")
        .help("更多")
    }
}

/// The design's `.icon-btn`: one glyph on a 28 pt disc, the whole disc
/// clickable. For actions that have no room for a title (test, delete);
/// the title is the tooltip and the accessibility label.
struct DesignIconButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
                .frame(width: 28, height: 28)
                .background(.quaternary, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .help(title)
    }
}

/// The design's `.field`: a magnifier and a text field on a capsule, with a
/// clear button once there is text. Used by the panel's node page and 试一下.
struct DesignSearchField: View {
    let prompt: String
    @Binding var text: String
    var symbol = "magnifyingglass"
    var monospaced = false
    /// Points; 28 in the panel, 32 on a page.
    var height: CGFloat = 32
    var focus: FocusState<Bool>.Binding?
    var submit: () -> Void = {}

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).foregroundStyle(.secondary)
            field.textFieldStyle(.plain).font(monospaced ? .body.monospaced() : .body).onSubmit(submit)
            if !text.isEmpty {
                Button("清除", systemImage: "xmark.circle.fill") { text = "" }
                    .labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 10).frame(height: height)
        .background(.quaternary, in: Capsule())
    }

    @ViewBuilder private var field: some View {
        if let focus {
            TextField(prompt, text: $text).focused(focus)
        } else {
            TextField(prompt, text: $text)
        }
    }
}

/// Lays its subviews out left to right and wraps to the next line when the
/// width runs out (chips, tags). Rows are as tall as their tallest subview.
struct FlowingRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        return CGSize(width: rows.map(\.width).max() ?? 0,
                      height: rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.items {
                // Nothing is wider than the row: a long host truncates inside its chip.
                let size = subviews[index].sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: min(size.width, bounds.width), height: size.height))
                x += min(size.width, bounds.width) + spacing
            }
            y += row.height + spacing
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [(items: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(items: [Int], width: CGFloat, height: CGFloat)] = []
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil))
            let item = min(size.width, width)
            if let last = rows.indices.last, rows[last].width + spacing + item <= width {
                rows[last].items.append(index)
                rows[last].width += spacing + item
                rows[last].height = max(rows[last].height, size.height)
            } else {
                rows.append(([index], item, size.height))
            }
        }
        return rows
    }
}

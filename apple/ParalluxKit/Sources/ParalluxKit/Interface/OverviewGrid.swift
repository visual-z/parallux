import Foundation

/// How the overview's cards share the width they are given (INV-15).
///
/// The cards used to stay in one row down to the window's minimum width,
/// each squeezed to a third of it, and their text was cut off. Now a card
/// shares a row only while every card in that row keeps its minimum width.
/// The row that is not full is the first one: with three cards in a narrow
/// window the first takes the full width and the other two sit side by side.
///
/// It goes by the width the layout is offered, not the window's, so the
/// sidebar being wide, narrow or hidden needs no rule of its own.
public enum OverviewGrid {
    /// Why 200: the longest label–value row of the cards (「本次会话已用」
    /// with 「999.9 MB / 无限」 at subheadline size) is about 190 pt, plus
    /// the card's padding, rounded. Assumed from that estimate; if a value
    /// is ever cut off at this width, raise it.
    public static let minimumCardWidth: Double = 200
    public static let spacing: Double = 12

    /// The cards of each row, as index ranges, top to bottom.
    public static func rows(count: Int, width: Double) -> [Range<Int>] {
        guard count > 0 else { return [] }
        // NaN and negative widths fall through to one column.
        let fitting = width.isFinite ? ((width + spacing) / (minimumCardWidth + spacing)).rounded(.down) : (width > 0 ? Double(count) : 1)
        let columns = max(1, min(count, fitting >= 1 ? Int(min(fitting, Double(count))) : 1))
        // Filled from the end, so only the first row can be short.
        let first = count % columns == 0 ? columns : count % columns
        var rows = [0..<first]
        var start = first
        while start < count {
            rows.append(start..<(start + columns))
            start += columns
        }
        return rows
    }
}

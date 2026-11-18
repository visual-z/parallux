import AppKit

/// The 18 pt monochrome template glyphs of the design: shape, not colour,
/// tells the state. The system tints them for light, dark and highlight.
public enum MenuBarIcon {
    public enum State: CaseIterable, Sendable {
        /// Three faint parallel lines.
        case disconnected
        /// Three solid parallel lines.
        case balance
        /// Three lines merging into one.
        case bond
        /// One solid line, two dashed.
        case failover
        /// A broken line with a corner badge.
        case degraded
    }

    public static let pointSize: CGFloat = 18

    public static func image(for state: State) -> NSImage {
        NSImage(size: NSSize(width: 1, height: 1))
    }
}

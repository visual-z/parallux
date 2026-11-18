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

    /// Why 1.5: the design's stroke weight at 18 pt.
    static let lineWidth: CGFloat = 1.5

    public static func image(for state: State) -> NSImage {
        let image = NSImage(size: NSSize(width: pointSize, height: pointSize), flipped: true) { _ in
            draw(state)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = description(state)
        return image
    }

    static func description(_ state: State) -> String {
        switch state {
        case .disconnected: "Parallux 未连接"
        case .balance: "Parallux 分流"
        case .bond: "Parallux 叠加"
        case .failover: "Parallux 主备"
        case .degraded: "Parallux 线路异常"
        }
    }

    /// Three rows at y = 5, 9, 13 between x = 3 and 15.
    private static func draw(_ state: State) {
        let rows: [CGFloat] = [5, 9, 13]
        NSColor.black.setStroke()
        NSColor.black.setFill()
        func line(_ y: CGFloat, from x0: CGFloat = 3, to x1: CGFloat = 15, alpha: CGFloat = 1, dashed: Bool = false) {
            let path = NSBezierPath()
            path.lineWidth = lineWidth
            path.lineCapStyle = .round
            if dashed { path.setLineDash([2, 2.5], count: 2, phase: 0) }
            path.move(to: NSPoint(x: x0, y: y))
            path.line(to: NSPoint(x: x1, y: y))
            NSColor.black.withAlphaComponent(alpha).setStroke()
            path.stroke()
        }
        switch state {
        case .disconnected:
            for y in rows { line(y, alpha: 0.35) }
        case .balance:
            for y in rows { line(y) }
        case .bond:
            let path = NSBezierPath()
            path.lineWidth = lineWidth
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            for y in rows {
                path.move(to: NSPoint(x: 3, y: y))
                path.curve(to: NSPoint(x: 10, y: 9), controlPoint1: NSPoint(x: 7, y: y), controlPoint2: NSPoint(x: 7, y: 9))
            }
            path.move(to: NSPoint(x: 10, y: 9))
            path.line(to: NSPoint(x: 15, y: 9))
            path.stroke()
        case .failover:
            line(5)
            line(9, dashed: true)
            line(13, dashed: true)
        case .degraded:
            line(5)
            line(9, to: 7)
            line(9, from: 10, to: 11)
            line(13)
            NSBezierPath(ovalIn: NSRect(x: 12.5, y: 11.5, width: 5, height: 5)).fill()
        }
    }
}

import AppKit
import ParalluxKit
import SwiftUI

/// One column entry of the flow diagram.
struct FlowNode: Identifiable, Equatable {
    var id: String
    var name: String
    var detail: String
    /// Bytes per second.
    var rate: Double
    var color: Color
    /// A link that is switched off: drawn faded (design v0.2).
    var isDimmed = false
}

/// Colours of the flow diagram, from design v0.2's light and dark palettes.
/// Chart colours are the one place hex values are allowed
/// (docs/design/copy-and-style.md §2); everything else is semantic.
enum FlowPalette {
    static let wifi = dynamic(light: 0x2FA6C4, dark: 0x40C8E0)
    static let wired = dynamic(light: 0xF08C00, dark: 0xFF9F0A)
    static let cellular = dynamic(light: 0xF2385F, dark: 0xFF375F)
    static let proxy = dynamic(light: 0x30A14E, dark: 0x30D158)
    static let direct = dynamic(light: 0x8E8E93, dark: 0x98989D)

    /// The design's `--band`: bands are a wash of the link colour so the
    /// particles on top stay readable.
    static func bandOpacity(_ scheme: ColorScheme) -> Double { scheme == .dark ? 0.42 : 0.38 }

    private static func dynamic(light: Int, dark: Int) -> Color {
        func color(_ hex: Int) -> NSColor {
            NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? color(dark) : color(light)
        })
    }
}

/// Links → centre bar → exits, band width = live rate against `capacity`
/// (design v0.2). Geometry comes from SankeyLayout (INV-3, INV-7) and the dots
/// from FlowParticles (INV-8); this view only paints them. It takes plain
/// values, so it can be rendered on its own with any numbers.
struct FlowDiagram: View {
    let links: [FlowNode]
    let exits: [FlowNode]
    var centerLabel: String?
    /// The rate that fills the height (FlowScale).
    var capacity: Double
    /// The menu bar panel's strip: no labels, thinner bars.
    var isCompact = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @State private var motion = FlowMotion()
    @State private var windowIsVisible = true

    /// PLAN §5: the animation costs nothing while nobody can see it.
    private var animates: Bool { !reduceMotion && windowIsVisible }

    var body: some View {
        GeometryReader { proxy in
            let metrics = Metrics(size: proxy.size, isCompact: isCompact)
            ZStack(alignment: .topLeading) {
                // 30 fps: the dots move about 2 pt a frame, smooth enough, at half
                // the cost of the display's rate.
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !animates)) { timeline in
                    Canvas { context, _ in
                        let frame = motion.frame(at: timeline.date, links: links.map(\.rate), exits: exits.map(\.rate),
                                                 capacity: capacity, metrics: metrics, animated: animates)
                        draw(frame, metrics: metrics, in: &context)
                    }
                }
                if !isCompact { labels(metrics) }
            }
        }
        .background(WindowVisibility(isVisible: $windowIsVisible))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    /// The text next to the nodes and above the centre bar. Laid out from the
    /// real rates and kept out of the animated Canvas: drawn there they were
    /// rasterised again on every frame, which cost more than the particles.
    /// They glide to a new place in about the time the bands take to ease.
    private func labels(_ m: Metrics) -> some View {
        let layout = SankeyLayout.make(left: links.map(\.rate), right: exits.map(\.rate), height: Double(m.region), gap: m.gap, capacity: capacity)
        let mid = { (span: Span) in m.inset + CGFloat((span.lower + span.upper) / 2) }
        return ZStack(alignment: .topLeading) {
            ForEach(Array(zip(links, layout.left)), id: \.0.id) { node, span in
                label(node, alignment: .trailing).frame(width: m.leftLabelWidth, alignment: .trailing)
                    .position(x: m.leftX - 12 - m.leftLabelWidth / 2, y: mid(span))
            }
            ForEach(Array(zip(exits, layout.right)), id: \.0.id) { node, span in
                label(node, alignment: .leading).frame(width: m.rightLabelWidth, alignment: .leading)
                    .position(x: m.rightX + m.bar + 12 + m.rightLabelWidth / 2, y: mid(span))
            }
            if let centerLabel {
                Text(centerLabel).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).monospacedDigit().lineLimit(1).fixedSize()
                    .position(x: m.centreX + m.bar / 2, y: max(8, m.centreTop(layout.total) - 12))
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: layout)
    }

    private func label(_ node: FlowNode, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(node.name).font(.body.weight(.semibold)).foregroundStyle(node.isDimmed ? .tertiary : .primary).lineLimit(1)
            Text(node.detail).font(.subheadline).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
        }
    }

    private func draw(_ frame: FlowMotion.Frame, metrics m: Metrics, in context: inout GraphicsContext) {
        let layout = frame.layout
        let y = { (value: Double) in m.inset + CGFloat(value) }
        let middle = m.inset + m.region / 2
        func mid(_ span: Span) -> CGFloat { y((span.lower + span.upper) / 2) }
        /// A node is drawn at least 6 pt tall so an idle link is still a thing you can see.
        func nodeRect(x: CGFloat, _ span: Span, centre: CGFloat) -> CGRect {
            span.length >= 6 ? CGRect(x: x, y: y(span.lower), width: m.bar, height: CGFloat(span.length))
                : CGRect(x: x, y: centre - 3, width: m.bar, height: 6)
        }

        // Bands, in two legs that meet on the centre bar.
        for band in layout.bands where band.left.length >= 0.3 {
            let fill = GraphicsContext.Shading.color(links[band.from].color.opacity(FlowPalette.bandOpacity(scheme)))
            context.fill(leg(from: m.leftX + m.bar, band.left, to: m.centreX, band.center, offset: m.inset), with: fill)
            context.fill(leg(from: m.centreX + m.bar, band.center, to: m.rightX, band.right, offset: m.inset), with: fill)
        }

        // A link that carries nothing keeps a dashed line to the bar: it is there, waiting.
        for (index, span) in layout.left.enumerated() where span.length < 0.3 && index < links.count {
            var path = Path()
            let start = CGPoint(x: m.leftX + m.bar, y: mid(span)), end = CGPoint(x: m.centreX, y: middle)
            let midX = (start.x + end.x) / 2
            path.move(to: start)
            path.addCurve(to: end, control1: CGPoint(x: midX, y: start.y), control2: CGPoint(x: midX, y: end.y))
            context.stroke(path, with: .style(.tertiary), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
        }

        // Particles ride the bands; on a dark background they add light instead
        // of covering. Filled as one path per link and opacity step, not one
        // fill per dot: a full diagram has hundreds of them every frame.
        if !frame.particles.isEmpty {
            let side: CGFloat = isCompact ? 1.6 : 2
            let steps = 4
            var paths = [Path](repeating: Path(), count: links.count * steps)
            for particle in frame.particles {
                guard particle.from < links.count,
                      let band = layout.bands.first(where: { $0.from == particle.from && $0.to == particle.to }) else { continue }
                let first = particle.progress < 1
                let t = first ? particle.progress : particle.progress - 1
                let x0 = first ? m.leftX + m.bar : m.centreX + m.bar, x1 = first ? m.centreX : m.rightX
                let point = CGPoint(x: x0 + (x1 - x0) * CGFloat(FlowParticles.run(t)), y: y(FlowParticles.y(of: particle, in: band)))
                // Fades in and out over the first and last eighth of a leg.
                let opacity = min(1, particle.progress * 8, (2 - particle.progress) * 8)
                let step = min(steps - 1, Int(opacity * Double(steps)))
                paths[particle.from * steps + step].addRect(CGRect(x: point.x - side / 2, y: point.y - side / 2, width: side, height: side))
            }
            var dots = context
            if scheme == .dark { dots.blendMode = .plusLighter }
            for (index, path) in paths.enumerated() where !path.isEmpty {
                dots.opacity = 0.9 * Double(index % steps + 1) / Double(steps)
                dots.fill(path, with: .color(links[index / steps].color))
            }
        }

        // Nodes.
        for (index, span) in layout.left.enumerated() where index < links.count {
            context.fill(Path(roundedRect: nodeRect(x: m.leftX, span, centre: mid(span)), cornerRadius: 2),
                         with: .color(links[index].color.opacity(links[index].isDimmed ? 0.3 : 1)))
        }
        context.fill(Path(roundedRect: nodeRect(x: m.centreX, m.centreSpan(layout.total), centre: middle), cornerRadius: 2), with: .style(.primary))
        for (index, span) in layout.right.enumerated() where index < exits.count {
            context.fill(Path(roundedRect: nodeRect(x: m.rightX, span, centre: mid(span)), cornerRadius: 2), with: .color(exits[index].color))
        }
    }

    /// One leg of a band: both edges are cubic curves with their control
    /// points at mid-x, the shape FlowParticles.rise/run are derived from.
    private func leg(from x0: CGFloat, _ a: Span, to x1: CGFloat, _ b: Span, offset: CGFloat) -> Path {
        let midX = (x0 + x1) / 2
        let a0 = offset + CGFloat(a.lower), a1 = offset + CGFloat(a.upper)
        let b0 = offset + CGFloat(b.lower), b1 = offset + CGFloat(b.upper)
        var path = Path()
        path.move(to: CGPoint(x: x0, y: a0))
        path.addCurve(to: CGPoint(x: x1, y: b0), control1: CGPoint(x: midX, y: a0), control2: CGPoint(x: midX, y: b0))
        path.addLine(to: CGPoint(x: x1, y: b1))
        path.addCurve(to: CGPoint(x: x0, y: a1), control1: CGPoint(x: midX, y: b1), control2: CGPoint(x: midX, y: a1))
        path.closeSubpath()
        return path
    }

    private var accessibilityText: String {
        let left = links.map { "\($0.name) \($0.detail)" }.joined(separator: "，")
        let right = exits.map { "\($0.name) \($0.detail)" }.joined(separator: "，")
        return "流向：\(left) 到 \(right)"
    }

    /// Where things sit, from design v0.2's canvas code. The label columns
    /// narrow with the window so the bands keep some room at the minimum width.
    struct Metrics: Equatable {
        var leftX: CGFloat
        var centreX: CGFloat
        var rightX: CGFloat
        var bar: CGFloat
        /// Clear space above and below the nodes (centre label, half a label).
        var inset: CGFloat
        var region: CGFloat
        /// Least distance between neighbouring nodes: a two-line label.
        var gap: Double
        var leftLabelWidth: CGFloat
        var rightLabelWidth: CGFloat

        init(size: CGSize, isCompact: Bool) {
            bar = isCompact ? 4 : 8
            inset = isCompact ? 8 : 34
            region = max(1, size.height - inset * 2)
            gap = isCompact ? 4 : 34
            leftX = isCompact ? 10 : min(150, size.width * 0.24)
            // The compact strip keeps its right 104 pt for the rate printed over it.
            rightX = max(leftX + bar * 3, isCompact ? size.width - 104 : size.width - min(200, size.width * 0.3))
            centreX = (leftX + rightX) / 2
            leftLabelWidth = max(0, leftX - 16)
            rightLabelWidth = max(0, size.width - rightX - bar - 12)
        }

        /// The centre bar's extent; with no traffic it is a stub in the middle.
        func centreSpan(_ total: Span) -> Span {
            total.length > 0 ? total : Span(Double(region) / 2, Double(region) / 2)
        }

        /// The y of the drawn centre bar's top edge (it is never shorter than 6 pt).
        func centreTop(_ total: Span) -> CGFloat {
            let span = centreSpan(total)
            return span.length >= 6 ? inset + CGFloat(span.lower) : inset + region / 2 - 3
        }
    }
}

/// What moves between frames: the rates as currently drawn (they ease towards
/// the real ones so a new sample does not jump) and the particles. A class
/// held in @State: the Canvas advances it while drawing, which must not
/// invalidate the view.
private final class FlowMotion {
    struct Frame {
        var layout: SankeyLayout
        var particles: [FlowParticles.Particle]
    }

    private var shownLinks: [Double] = []
    private var shownExits: [Double] = []
    private var particles = FlowParticles()
    private var last: Date?
    private var generator = SystemRandomNumberGenerator()

    func frame(at date: Date, links: [Double], exits: [Double], capacity: Double, metrics: FlowDiagram.Metrics, animated: Bool) -> Frame {
        // The Canvas may draw the same instant twice; a zero step changes nothing.
        let dt = animated ? min(max(last.map { date.timeIntervalSince($0) } ?? 0, 0), FlowParticles.longestStep) : 0
        last = animated ? date : nil
        shownLinks = ease(shownLinks, towards: links, dt: dt, animated: animated)
        shownExits = ease(shownExits, towards: exits, dt: dt, animated: animated)
        let layout = SankeyLayout.make(left: shownLinks, right: shownExits, height: Double(metrics.region), gap: metrics.gap, capacity: capacity)
        if animated {
            particles.step(by: dt, bands: layout.bands, using: &generator)
        } else {
            particles = FlowParticles()
        }
        return Frame(layout: layout, particles: particles.particles)
    }

    /// The design's `shown += (target - shown) * dt * 3`: most of the way in a
    /// third of a second. Without animation, or when the set of nodes changed,
    /// the drawn rates are simply the real ones.
    private func ease(_ shown: [Double], towards target: [Double], dt: Double, animated: Bool) -> [Double] {
        guard animated, shown.count == target.count else { return target }
        return zip(shown, target).map { $0 + ($1 - $0) * min(1, dt * 3) }
    }
}

/// Reports whether the window this view sits in is visible at all (not
/// closed, minimised or fully covered), so the diagram can stop animating.
private struct WindowVisibility: NSViewRepresentable {
    @Binding var isVisible: Bool

    func makeNSView(context: Context) -> Probe {
        let probe = Probe()
        probe.onChange = { visible in
            // Reported from AppKit callbacks that can fire during a SwiftUI update.
            DispatchQueue.main.async { if isVisible != visible { isVisible = visible } }
        }
        return probe
    }

    func updateNSView(_ view: Probe, context: Context) {}

    final class Probe: NSView {
        var onChange: (Bool) -> Void = { _ in }

        // Selector-based observation: AppKit drops it when the view goes
        // away, so there is nothing to undo in deinit.
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self, name: NSWindow.didChangeOcclusionStateNotification, object: nil)
            if let window {
                NotificationCenter.default.addObserver(self, selector: #selector(report), name: NSWindow.didChangeOcclusionStateNotification, object: window)
            }
            report()
        }

        @objc private func report() { onChange(window?.occlusionState.contains(.visible) ?? false) }
    }
}

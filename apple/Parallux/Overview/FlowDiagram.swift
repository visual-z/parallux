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

/// Traffic from one rule to one node (three-column diagram).
struct FlowLink: Equatable {
    var id: String
    var rule: Int
    var node: Int
    /// Bytes per second.
    var rate: Double
}

/// Colours of the flow diagram, from design v0.2's light and dark palettes.
/// Chart colours are the one place hex values are allowed
/// (docs/design/copy-and-style.md §2); everything else is semantic.
enum FlowPalette {
    /// The rules of the middle column, one each (ColorSeats). Why these: none
    /// is a link colour (cyan, orange, pink) or an exit colour (green, grey),
    /// so a rule's bar never reads as a link or a node; eight is more than
    /// the overview shows at once (FlowModel.ruleSeats + 其他).
    static let rules: [Color] = [.purple, .blue, .indigo, .teal, .yellow, .red, .brown, .mint]

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

/// Links → rules → nodes (or links → one bar → exits in the panel), band
/// width = share of the traffic (design v0.2; by share since
/// docs/tasks/fix-flow-stability.md, three columns since
/// docs/tasks/fix-overview-layout-and-flow.md). Geometry comes from SankeyLayout (INV-3, INV-7) and the dots
/// from FlowParticles (INV-8); this view only paints them. It takes plain
/// values, so it can be rendered on its own with any numbers.
struct FlowDiagram: View {
    let links: [FlowNode]
    let exits: [FlowNode]
    /// The middle column, and what flows from it to `exits`: with rules the
    /// picture is links → rules → nodes (fix-overview-layout-and-flow);
    /// without, links → one bar → exits (the panel's strip).
    var rules: [FlowNode] = []
    var flows: [FlowLink] = []
    var centerLabel: String?
    /// How busy the dots are, 0...1 (FlowParticles.intensity): widths are
    /// shares, so this is what shows how much traffic there is.
    var intensity = 1.0
    /// The menu bar panel's strip: no labels, thinner bars.
    var isCompact = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @State private var motion = FlowMotion()
    @State private var windowIsVisible = true
    /// True for FlowEase.duration after the rates changed: the only time the
    /// bands and nodes need redrawing.
    @State private var isEasing = false

    /// Seconds between frames. Why 1/60: the dots travel 80–140 pt a second,
    /// so 30 fps moved them 3–5 pt a frame (more than their own size) and
    /// looked stepped; above 60 the eye gains little for dots this small and
    /// the cost grows with the rate (Metal layer, 900 dots: 60 fps 3.2%,
    /// 120 fps 4.8% of a core; docs/tasks/perf-flow-animation.md).
    static let frameInterval = 1.0 / 60

    /// PLAN §5: the animation costs nothing while nobody can see it.
    private var animates: Bool { !reduceMotion && windowIsVisible }

    var body: some View {
        GeometryReader { proxy in
            let metrics = Metrics(size: proxy.size, isCompact: isCompact)
            let target = FlowMotion.Target(linkIDs: links.map(\.id), links: links.map(\.rate), exitIDs: exits.map(\.id), exits: exits.map(\.rate),
                                           ruleIDs: rules.map(\.id), flowIDs: flows.map(\.id), flowRules: flows.map(\.rule),
                                           flowNodes: flows.map(\.node), flowRates: flows.map(\.rate), intensity: intensity)
            ZStack(alignment: .topLeading) {
                // Everything that moves is one GPU layer (FlowLayer); SwiftUI
                // adds the labels on top, placed for the new sample at once.
                if FlowPipeline.shared != nil {
                    FlowLayer(motion: motion, input: .init(
                        target: target, metrics: metrics, linkColors: links.map(\.color), dimmedLinks: links.map(\.isDimmed),
                        exitColors: exits.map(\.color), ruleColors: rules.map(\.color), easing: animates && isEasing, isVisible: windowIsVisible, reduceMotion: reduceMotion,
                        dotSide: isCompact ? 1.6 : 2, isDark: scheme == .dark))
                        // An NSView would otherwise take the clicks meant for the panel's strip button.
                        .allowsHitTesting(false)
                } else {
                    // No GPU to draw with: a still picture of the current sample.
                    Canvas { context, _ in
                        drawBandsAndNodes(target.layout(metrics), metrics: metrics, in: &context)
                    }
                }
                if !isCompact { labels(metrics, target: target) }
            }
            // A new sample starts an ease; when it is over the layer stops redrawing the bands.
            .task(id: target) {
                isEasing = true
                do {
                    try await Task.sleep(for: .seconds(FlowEase.duration))
                    isEasing = false
                } catch {}  // superseded by a newer sample, which keeps it on
            }
        }
        .background(WindowVisibility(isVisible: $windowIsVisible))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    /// The text next to the nodes (and, with three columns, the column
    /// headers), at the places the new sample gives them. They do not ride
    /// the 0.4 s ease: moving text every frame was the costliest part of the
    /// old Canvas, and the nodes' centres shift by a few points at most from
    /// one second to the next.
    private func labels(_ m: Metrics, target: FlowMotion.Target) -> some View {
        let layout = target.layout(m)
        let mid = { (span: Span) in m.inset + CGFloat((span.lower + span.upper) / 2) }
        let middleWidth = max(0, m.rightX - m.centreX - m.bar - 28)
        return ZStack(alignment: .topLeading) {
            ForEach(Array(zip(links, layout.left)), id: \.0.id) { node, span in
                label(node, alignment: .trailing).frame(width: m.leftLabelWidth, alignment: .trailing)
                    .position(x: m.leftX - 12 - m.leftLabelWidth / 2, y: mid(span))
            }
            // A rule's name sits beside its bar, over the bands that leave
            // it, on a plate so it stays readable (the author's reference).
            ForEach(Array(zip(rules, layout.middle)), id: \.0.id) { node, span in
                label(node, alignment: .leading)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.background.opacity(0.78), in: RoundedRectangle(cornerRadius: 6))
                    .frame(width: middleWidth, alignment: .leading)
                    .position(x: m.centreX + m.bar + 8 + middleWidth / 2, y: mid(span))
            }
            ForEach(Array(zip(exits, layout.right)), id: \.0.id) { node, span in
                label(node, alignment: .leading).frame(width: m.rightLabelWidth, alignment: .leading)
                    .position(x: m.rightX + m.bar + 12 + m.rightLabelWidth / 2, y: mid(span))
            }
            if rules.isEmpty {
                if let centerLabel {
                    Text(centerLabel).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).monospacedDigit().lineLimit(1).fixedSize()
                        .position(x: m.centreX + m.bar / 2, y: max(8, m.centreTop(layout.total) - 12))
                }
            } else {
                // Column headers (the reference's 「Source / Node / …」): what each column is.
                header(centerLabel.map { "线路 · \($0)" } ?? "线路").frame(width: m.leftX + m.bar, alignment: .trailing)
                    .position(x: (m.leftX + m.bar) / 2, y: 8)
                header("规则").frame(width: middleWidth, alignment: .leading)
                    .position(x: m.centreX + middleWidth / 2, y: 8)
                header("出口").frame(width: m.rightLabelWidth + m.bar + 12, alignment: .leading)
                    .position(x: m.rightX + (m.rightLabelWidth + m.bar + 12) / 2, y: 8)
            }
        }
    }

    private func header(_ text: String) -> some View {
        Text(text).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
    }

    private func label(_ node: FlowNode, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(node.name).font(.body.weight(.semibold)).foregroundStyle(node.isDimmed ? .tertiary : .primary).lineLimit(1)
            Text(node.detail).font(.subheadline).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
        }
    }

    /// The picture without a GPU: bands, idle links' dashed lines and the
    /// three columns of nodes, as FlowLayer draws them from FlowMesh.
    private func drawBandsAndNodes(_ layout: SankeyLayout, metrics m: Metrics, in context: inout GraphicsContext) {
        let y = { (value: Double) in m.inset + CGFloat(value) }
        let middle = m.inset + m.region / 2
        func mid(_ span: Span) -> CGFloat { y((span.lower + span.upper) / 2) }
        /// A node is drawn at least 6 pt tall so an idle link is still a thing you can see.
        func nodeRect(x: CGFloat, _ span: Span, centre: CGFloat) -> CGRect {
            span.length >= 6 ? CGRect(x: x, y: y(span.lower), width: m.bar, height: CGFloat(span.length))
                : CGRect(x: x, y: centre - 3, width: m.bar, height: 6)
        }

        // Bands, in two legs that meet on the centre bar.
        for band in layout.bands where band.left.length >= 0.3 && band.from < links.count {
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

        for (index, span) in layout.left.enumerated() where index < links.count {
            context.fill(Path(roundedRect: nodeRect(x: m.leftX, span, centre: mid(span)), cornerRadius: 2),
                         with: .color(links[index].color.opacity(links[index].isDimmed ? 0.3 : 1)))
        }
        if layout.middle.isEmpty {
            context.fill(Path(roundedRect: nodeRect(x: m.centreX, m.centreSpan(layout.total), centre: middle), cornerRadius: 2), with: .style(.primary))
        } else {
            for (index, span) in layout.middle.enumerated() where index < rules.count {
                context.fill(Path(roundedRect: nodeRect(x: m.centreX, span, centre: mid(span)), cornerRadius: 2), with: .color(rules[index].color))
            }
        }
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

        /// The same columns for FlowMesh.
        var meshFrame: FlowMesh.Frame {
            FlowMesh.Frame(leftX: Double(leftX), centreX: Double(centreX), rightX: Double(rightX), bar: Double(bar), inset: Double(inset), region: Double(region))
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

/// What moves between frames: the rates as currently drawn (FlowEase) and the
/// particles (FlowParticles). A class held in @State: FlowLayer advances it
/// while drawing, which must not invalidate the view. Main thread only (the
/// layer's display link fires on the main run loop).
final class FlowMotion {
    /// What the diagram should show once it has settled. Rates are only
    /// compared within a side (widths are shares); the ids say which node a
    /// rate belongs to when the set changes.
    struct Target: Equatable {
        var linkIDs: [String]
        var links: [Double]
        var exitIDs: [String]
        var exits: [Double]
        /// Three columns when not empty: the rules, and the flows from them to the exits.
        var ruleIDs: [String] = []
        var flowIDs: [String] = []
        var flowRules: [Int] = []
        var flowNodes: [Int] = []
        var flowRates: [Double] = []
        var intensity = 1.0

        /// The layout for these rates (flows given separately: eased ones while animating).
        func layout(_ metrics: FlowDiagram.Metrics, links: [Double]? = nil, flows: [Double]? = nil, exits: [Double]? = nil) -> SankeyLayout {
            if ruleIDs.isEmpty {
                return SankeyLayout.make(leftShares: links ?? self.links, rightShares: exits ?? self.exits, height: Double(metrics.region), gap: metrics.gap)
            }
            let rates = flows ?? flowRates
            let triples = flowRules.indices.map { (rule: flowRules[$0], node: flowNodes[$0], rate: $0 < rates.count ? rates[$0] : 0) }
            return SankeyLayout.make(links: links ?? self.links, rules: ruleIDs.count, nodes: exitIDs.count, flows: triples,
                                     height: Double(metrics.region), gap: metrics.gap)
        }
        /// Bands exist only with traffic on both sides; without them there is nothing to animate.
        var hasTraffic: Bool { links.contains { $0 > 0 } && exits.contains { $0 > 0 } }
    }

    struct Frame {
        var layout: SankeyLayout
        var particles: [FlowParticles.Particle]
    }

    private var linkEase = FlowEase()
    private var exitEase = FlowEase()
    private var particleModel = FlowParticles()
    private var easedAt: Date?
    private var steppedAt: Date?
    private var generator = SystemRandomNumberGenerator()

    /// The settled layout last computed, and what it was computed for: between
    /// samples nothing changes, and the layer asks 60 times a second.
    private var settled: (target: Target, metrics: FlowDiagram.Metrics, layout: SankeyLayout)?

    private var linkIDs: [String] = []
    private var exitIDs: [String] = []
    private var flowEase = FlowEase()
    private var flowIDs: [String] = []

    /// A node that just appeared grows from nothing and the others make room,
    /// rather than the whole picture jumping to the new set.
    private func retarget(_ ease: inout FlowEase, ids: inout [String], to target: [Double], _ newIDs: [String]) {
        guard ids != newIDs else { return ease.retarget(target) }
        let drawn = Dictionary(zip(ids, ease.value), uniquingKeysWith: { first, _ in first })
        ease.retarget(target, from: newIDs.map { drawn[$0] ?? 0 })
        ids = newIDs
    }

    /// The layout to draw at `date`; time only moves forward.
    func layout(at date: Date, target: Target, metrics: FlowDiagram.Metrics, easing: Bool) -> SankeyLayout {
        retarget(&linkEase, ids: &linkIDs, to: target.links, target.linkIDs)
        retarget(&exitEase, ids: &exitIDs, to: target.exits, target.exitIDs)
        retarget(&flowEase, ids: &flowIDs, to: target.flowRates, target.flowIDs)
        if easing {
            let dt = max(0, easedAt.map { date.timeIntervalSince($0) } ?? 0)
            linkEase.advance(by: dt)
            exitEase.advance(by: dt)
            flowEase.advance(by: dt)
            easedAt = max(date, easedAt ?? date)
        } else {
            // Not animating (or the ease is over): draw the sample itself.
            linkEase.finish()
            exitEase.finish()
            flowEase.finish()
            easedAt = nil
        }
        let isSettled = linkEase.isSettled && exitEase.isSettled && flowEase.isSettled
        if isSettled, let settled, settled.target == target, settled.metrics == metrics { return settled.layout }
        let layout = target.layout(metrics, links: linkEase.value, flows: flowEase.value, exits: exitEase.value)
        settled = isSettled ? (target, metrics, layout) : nil
        return layout
    }

    /// The particles at `date`, on the layout drawn at that moment.
    func particles(at date: Date, target: Target, metrics: FlowDiagram.Metrics, easing: Bool) -> Frame {
        let layout = layout(at: date, target: target, metrics: metrics, easing: easing)
        // A long gap (the layer was gone while idle) is clamped inside step(by:).
        let dt = max(0, steppedAt.map { date.timeIntervalSince($0) } ?? 0)
        steppedAt = max(date, steppedAt ?? date)
        particleModel.step(by: dt, bands: layout.bands, intensity: target.intensity, using: &generator)
        return Frame(layout: layout, particles: particleModel.particles)
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

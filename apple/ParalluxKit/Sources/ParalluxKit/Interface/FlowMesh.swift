import Foundation

/// The flow diagram as triangles for the GPU (perf-flow-animation): bands,
/// the dashed lines of idle links, and the three columns of nodes. Pure
/// geometry in view points, origin top left; the view supplies the colours
/// for each `Paint` and draws the pieces in order (bands and dashes under the
/// particles, nodes over them).
public enum FlowMesh {
    public enum Paint: Equatable, Sendable {
        /// A band, in its link's colour (translucent).
        case band(link: Int)
        /// A link's node.
        case link(Int)
        /// An exit's node.
        case exit(Int)
        /// The centre bar.
        case centre
        /// The dashed lines from links that carry nothing.
        case idle
    }

    public struct Piece: Equatable, Sendable {
        public var paint: Paint
        /// Three vertices per triangle.
        public var triangles: [SIMD2<Float>]
    }

    /// Where the columns sit (FlowDiagram.Metrics): the left edges of the
    /// three bars, the bar width, and the nodes' vertical area.
    public struct Frame: Equatable, Sendable {
        public var leftX: Double, centreX: Double, rightX: Double, bar: Double, inset: Double, region: Double
        public init(leftX: Double, centreX: Double, rightX: Double, bar: Double, inset: Double, region: Double) {
            self.leftX = leftX; self.centreX = centreX; self.rightX = rightX; self.bar = bar; self.inset = inset; self.region = region
        }
    }

    /// Why 60 000: the bound on what one frame hands to the GPU. A full
    /// diagram (25 bands, two legs, 48 steps, 6 vertices each) is 14 400;
    /// four times that is still under 2 MB of vertex data. Bands and dashes
    /// past it are left out; nodes are always drawn. Derived, not measured.
    public static let maxVertices = 60_000
    /// A band thinner than this is not drawn; its link gets a dashed line instead (design v0.2).
    public static let thinnest = 0.3
    /// A node is drawn at least this tall, so an idle link is still a thing you can see.
    public static let shortestNode = 6.0
    /// How far a band's edge may stray from the true curve, in points:
    /// a tenth of a point is under a quarter pixel at 2x.
    static let tolerance = 0.1
    static let segments = 4...48
    /// Corner radius of the nodes (design: 2 pt).
    static let cornerRadius = 2.0
    /// The design's `[3, 4]` dash, 1 pt thick.
    static let dash = (on: 3.0, off: 4.0, width: 1.0)

    public static func make(_ layout: SankeyLayout, frame f: Frame) -> [Piece] {
        var pieces: [Piece] = []
        var budget = maxVertices
        func add(_ paint: Paint, _ triangles: [SIMD2<Float>], bounded: Bool) {
            guard !triangles.isEmpty else { return }
            if bounded {
                guard triangles.count <= budget else { return }
                budget -= triangles.count
            }
            pieces.append(Piece(paint: paint, triangles: triangles))
        }
        let middle = f.inset + f.region / 2
        let mid = { (span: Span) in f.inset + (span.lower + span.upper) / 2 }

        // Bands, in two legs that meet on the centre bar.
        for band in layout.bands where band.left.length >= thinnest {
            add(.band(link: band.from),
                leg(from: f.leftX + f.bar, band.left, to: f.centreX, band.center, inset: f.inset)
                    + leg(from: f.centreX + f.bar, band.center, to: f.rightX, band.right, inset: f.inset),
                bounded: true)
        }
        // A link that carries nothing keeps a dashed line to the bar: it is there, waiting.
        var dashes: [SIMD2<Float>] = []
        for span in layout.left where span.length < thinnest {
            dashes += dashed(from: (f.leftX + f.bar, mid(span)), to: (f.centreX, middle))
        }
        add(.idle, dashes, bounded: true)

        for (index, span) in layout.left.enumerated() { add(.link(index), node(x: f.leftX, span, f), bounded: false) }
        let total = layout.total.length > 0 ? layout.total : Span(f.region / 2, f.region / 2)
        add(.centre, node(x: f.centreX, total, f), bounded: false)
        for (index, span) in layout.right.enumerated() { add(.exit(index), node(x: f.rightX, span, f), bounded: false) }
        return pieces
    }

    /// One leg of a band between two bars. Both edges are the same curve one
    /// thickness apart (a cubic whose control points sit at mid-x: the
    /// parametrisation FlowParticles.rise/run), sampled at the same
    /// parameters, so the strip covers exactly thickness × width.
    static func leg(from x0: Double, _ a: Span, to x1: Double, _ b: Span, inset: Double) -> [SIMD2<Float>] {
        let thickness = a.length
        let climb = b.lower - a.lower
        // A chord over 1/n of the parameter strays at most |climb| · 6 / (8 n²)
        // from the curve (rise″ ≤ 6); take the n that keeps it within tolerance.
        let wanted = Int((abs(climb) * 0.75 / tolerance).squareRoot().rounded(.up))
        let count = min(segments.upperBound, max(segments.lowerBound, wanted))
        var triangles: [SIMD2<Float>] = []
        triangles.reserveCapacity(count * 6)
        var px = x0, py = inset + a.lower
        for step in 1...count {
            let t = Double(step) / Double(count)
            let x = x0 + (x1 - x0) * FlowParticles.run(t)
            let y = inset + a.lower + climb * FlowParticles.rise(t)
            quad(&triangles, (px, py), (x, y), (x, y + thickness), (px, py + thickness))
            px = x
            py = y
        }
        return triangles
    }

    /// A bar with its corners cut twice each: at 2 pt that reads as rounded.
    static func node(x: Double, _ span: Span, _ f: Frame) -> [SIMD2<Float>] {
        let centre = f.inset + (span.lower + span.upper) / 2
        let top = span.length >= shortestNode ? f.inset + span.lower : centre - shortestNode / 2
        let bottom = span.length >= shortestNode ? f.inset + span.upper : centre + shortestNode / 2
        let r = min(cornerRadius, f.bar / 2, (bottom - top) / 2)
        let k = r * (1 - 0.5.squareRoot())  // where a 45° point of the corner arc sits
        let outline: [(Double, Double)] = [
            (x + r, top), (x + f.bar - r, top), (x + f.bar - k, top + k), (x + f.bar, top + r),
            (x + f.bar, bottom - r), (x + f.bar - k, bottom - k), (x + f.bar - r, bottom), (x + r, bottom),
            (x + k, bottom - k), (x, bottom - r), (x, top + r), (x + k, top + k),
        ]
        let hub = (x + f.bar / 2, (top + bottom) / 2)
        var triangles: [SIMD2<Float>] = []
        triangles.reserveCapacity(outline.count * 3)
        for (index, point) in outline.enumerated() {
            let next = outline[(index + 1) % outline.count]
            triangles += [vertex(hub), vertex(point), vertex(next)]
        }
        return triangles
    }

    /// Dashes along the same curve a band would take.
    static func dashed(from start: (Double, Double), to end: (Double, Double)) -> [SIMD2<Float>] {
        let steps = segments.upperBound
        var triangles: [SIMD2<Float>] = []
        var previous = start
        var travelled = 0.0
        let period = dash.on + dash.off
        for step in 1...steps {
            let t = Double(step) / Double(steps)
            let point = (start.0 + (end.0 - start.0) * FlowParticles.run(t), start.1 + (end.1 - start.1) * FlowParticles.rise(t))
            let dx = point.0 - previous.0, dy = point.1 - previous.1
            let length = (dx * dx + dy * dy).squareRoot()
            defer { previous = point; travelled += length }
            guard length > 0 else { continue }
            // Half the dash width, across the direction of travel.
            let nx = -dy / length * dash.width / 2, ny = dx / length * dash.width / 2
            // The stretches of this chord that fall in the "on" part of the pattern.
            var position = 0.0
            while position < length {
                let phase = (travelled + position).truncatingRemainder(dividingBy: period)
                let run = min(length - position, (phase < dash.on ? dash.on : period) - phase)
                if phase < dash.on {
                    let a = (previous.0 + dx * position / length, previous.1 + dy * position / length)
                    let b = (previous.0 + dx * (position + run) / length, previous.1 + dy * (position + run) / length)
                    quad(&triangles, (a.0 + nx, a.1 + ny), (b.0 + nx, b.1 + ny), (b.0 - nx, b.1 - ny), (a.0 - nx, a.1 - ny))
                }
                // Always forward: a run shorter than this could not end the loop.
                position += max(run, 1e-6)
            }
        }
        return triangles
    }

    private static func quad(_ triangles: inout [SIMD2<Float>], _ a: (Double, Double), _ b: (Double, Double), _ c: (Double, Double), _ d: (Double, Double)) {
        triangles += [vertex(a), vertex(b), vertex(c), vertex(a), vertex(c), vertex(d)]
    }

    private static func vertex(_ point: (Double, Double)) -> SIMD2<Float> { SIMD2(Float(point.0), Float(point.1)) }
}

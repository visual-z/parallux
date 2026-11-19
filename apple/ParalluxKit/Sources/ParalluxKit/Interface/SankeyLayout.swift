import Foundation

/// A vertical extent in points.
public struct Span: Equatable, Sendable {
    public var lower: Double
    public var upper: Double
    public var length: Double { upper - lower }
    public init(_ lower: Double, _ upper: Double) {
        self.lower = lower
        self.upper = upper
    }
}

/// Geometry of the overview's flow diagram: links on the left, exits on the
/// right, every band's thickness proportional to its rate (INV-3).
///
/// Left and right share one scale so both columns are equally tall; the
/// design's centre bar spans `total`, and every band crosses it. Rates on the
/// right are rescaled to the left's sum (they come from a different counter
/// and may disagree slightly).
///
/// Two geometries, chosen by `capacity`:
/// - none: the traffic fills the height and nodes are stacked `gap` apart.
/// - given: design v0.2. A rate takes `rate / capacity` of the height (so a
///   quiet network draws thin bands), links are spread over the whole height,
///   exits open out around the middle, and `gap` is only the least distance
///   between neighbours (room for their labels). INV-7.
public struct SankeyLayout: Equatable, Sendable {
    public struct Band: Equatable, Sendable {
        public var from: Int
        public var to: Int
        public var left: Span
        public var right: Span
        public var rate: Double
        /// Where the band crosses the centre bar: bands tile `total` exit by
        /// exit, link by link within an exit (design v0.2's order).
        public var center = Span(0, 0)
    }

    /// How far apart the exits' centres spread, as a share of the height.
    /// Why 0.5: design v0.2 puts two exits at 30% and 70% of a 330 pt canvas,
    /// which is half of the 262 pt the nodes may use. Smaller crowds the
    /// labels; larger pulls the bands into steep S-curves. Read off the design.
    public static let exitCentreSpread = 0.5

    public var left: [Span] = []
    public var right: [Span] = []
    public var bands: [Band] = []
    public var total = Span(0, 0)

    /// The least share of the height a node with traffic gets (fix-flow-stability).
    public static let thinnestShare = 0.02

    /// Width by share (fix-flow-stability): stub.
    public static func make(leftShares: [Double], rightShares: [Double], height: Double, gap: Double) -> SankeyLayout { SankeyLayout() }

    public static func make(left: [Double], right: [Double], height: Double, gap: Double, capacity: Double? = nil) -> SankeyLayout {
        let clean = { (rates: [Double]) in rates.map { $0.isFinite && $0 > 0 ? $0 : 0 } }
        let leftRates = clean(left)
        var rightRates = clean(right)
        let total = leftRates.reduce(0, +)
        let rightTotal = rightRates.reduce(0, +)
        let designed = capacity != nil
        let place = { (heights: [Double], isExit: Bool) -> [Span] in
            guard designed else { return stack(heights, gap: gap, height: height) }
            return isExit ? open(heights, gap: gap, height: height) : spread(heights, height: height)
        }
        var layout = SankeyLayout()
        guard total > 0, rightTotal > 0 else {
            layout.left = place(leftRates.map { _ in 0 }, false)
            layout.right = place(rightRates.map { _ in 0 }, true)
            return layout
        }
        rightRates = rightRates.map { $0 * total / rightTotal }
        // One scale for both columns so they are equally tall; the column with
        // more nodes spends more on gaps, so it bounds the scale.
        let gaps = gap * Double(max(leftRates.count, rightRates.count) - 1)
        var scale = max(0, height - gaps) / total
        if let capacity, capacity.isFinite, capacity > 0 { scale = min(scale, height / capacity) }
        layout.left = place(leftRates.map { $0 * scale }, false)
        layout.right = place(rightRates.map { $0 * scale }, true)
        let start = (height - total * scale) / 2
        layout.total = Span(start, start + total * scale)

        // Each link's traffic is split over the exits in proportion to them.
        // A link is cut in exit order, an exit in link order, and the centre
        // bar exit by exit: bands to the same exit stay together on the bar.
        var leftCursor = layout.left.map(\.lower)
        var centerCursor = layout.total.lower
        for (j, exit) in rightRates.enumerated() where exit > 0 {
            var rightCursor = layout.right[j].lower
            for (i, rate) in leftRates.enumerated() where rate > 0 {
                let flow = rate * exit / total
                let thickness = flow * scale
                layout.bands.append(Band(from: i, to: j, left: Span(leftCursor[i], leftCursor[i] + thickness),
                                         right: Span(rightCursor, rightCursor + thickness), rate: flow,
                                         center: Span(centerCursor, centerCursor + thickness)))
                leftCursor[i] += thickness
                rightCursor += thickness
                centerCursor += thickness
            }
        }
        layout.checkInvariants(height: height)
        return layout
    }

    /// Stacks heights top to bottom with gaps, centred vertically.
    private static func stack(_ heights: [Double], gap: Double, height: Double) -> [Span] {
        let used = heights.reduce(0, +) + gap * Double(max(heights.count - 1, 0))
        var cursor = max(0, (height - used) / 2)
        return heights.map { length in
            defer { cursor += length + gap }
            return Span(cursor, cursor + length)
        }
    }

    /// Links (design): the first node touches the top, the last the bottom,
    /// the free height is shared equally between neighbours. One node sits in
    /// the middle.
    private static func spread(_ heights: [Double], height: Double) -> [Span] {
        guard heights.count > 1 else { return stack(heights, gap: 0, height: height) }
        let free = max(0, height - heights.reduce(0, +))
        return stack(heights, gap: free / Double(heights.count - 1), height: height)
    }

    /// Exits (design): centred, their centres `exitCentreSpread` of the height
    /// apart from first to last when they are thin; never closer than `gap`,
    /// never past the edges.
    private static func open(_ heights: [Double], gap: Double, height: Double) -> [Span] {
        guard heights.count > 1 else { return stack(heights, gap: 0, height: height) }
        let between = Double(heights.count - 1)
        let used = heights.reduce(0, +)
        // Centre spacing minus the average node: exact for two exits.
        let natural = exitCentreSpread * height / between - used / Double(heights.count)
        let widest = max(0, height - used) / between
        return stack(heights, gap: min(max(gap, natural), widest), height: height)
    }

    /// INV-3 and INV-7 (docs/INVARIANTS.md).
    func checkInvariants(height: Double) {
        #if DEBUG
        let leftSum = left.map(\.length).reduce(0, +)
        let rightSum = right.map(\.length).reduce(0, +)
        let slack = 1e-6 * max(1, leftSum)
        assert(abs(leftSum - rightSum) <= slack, "INV-3: columns differ")
        assert(abs(bands.map(\.center.length).reduce(0, +) - total.length) <= slack, "INV-7: the centre bar is not the sum of its bands")
        assert((left + right + [total]).allSatisfy { $0.lower >= -slack && $0.upper <= height + slack }, "INV-7: a node leaves the drawing area")
        #endif
    }
}

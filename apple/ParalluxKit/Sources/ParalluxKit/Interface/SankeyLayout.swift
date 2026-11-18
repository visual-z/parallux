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
/// design's centre bar spans `total`. Rates on the right are rescaled to the
/// left's sum (they come from a different counter and may disagree slightly).
public struct SankeyLayout: Equatable, Sendable {
    public struct Band: Equatable, Sendable {
        public var from: Int
        public var to: Int
        public var left: Span
        public var right: Span
        public var rate: Double
    }

    public var left: [Span] = []
    public var right: [Span] = []
    public var bands: [Band] = []
    public var total = Span(0, 0)

    public static func make(left: [Double], right: [Double], height: Double, gap: Double) -> SankeyLayout {
        let clean = { (rates: [Double]) in rates.map { $0.isFinite && $0 > 0 ? $0 : 0 } }
        let leftRates = clean(left)
        var rightRates = clean(right)
        let total = leftRates.reduce(0, +)
        let rightTotal = rightRates.reduce(0, +)
        var layout = SankeyLayout()
        guard total > 0, rightTotal > 0 else {
            layout.left = stack(leftRates.map { _ in 0 }, gap: gap, height: height)
            layout.right = stack(rightRates.map { _ in 0 }, gap: gap, height: height)
            return layout
        }
        rightRates = rightRates.map { $0 * total / rightTotal }
        // One scale for both columns so they are equally tall; the column with
        // more nodes spends more on gaps, so it sets the scale.
        let gaps = gap * Double(max(leftRates.count, rightRates.count) - 1)
        let scale = max(0, height - gaps) / total
        layout.left = stack(leftRates.map { $0 * scale }, gap: gap, height: height)
        layout.right = stack(rightRates.map { $0 * scale }, gap: gap, height: height)
        let start = (height - total * scale) / 2
        layout.total = Span(start, start + total * scale)

        // Each link's traffic is split over the exits in proportion to them;
        // the left node is cut in exit order, the right node in link order.
        var rightCursor = layout.right.map(\.lower)
        for (i, rate) in leftRates.enumerated() where rate > 0 {
            var leftCursor = layout.left[i].lower
            for (j, exit) in rightRates.enumerated() where exit > 0 {
                let flow = rate * exit / total
                let thickness = flow * scale
                layout.bands.append(Band(from: i, to: j, left: Span(leftCursor, leftCursor + thickness),
                                         right: Span(rightCursor[j], rightCursor[j] + thickness), rate: flow))
                leftCursor += thickness
                rightCursor[j] += thickness
            }
        }
        layout.checkInvariants()
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

    /// INV-3 (docs/INVARIANTS.md).
    func checkInvariants() {
        #if DEBUG
        let leftSum = left.map(\.length).reduce(0, +)
        let rightSum = right.map(\.length).reduce(0, +)
        assert(abs(leftSum - rightSum) <= 1e-6 * max(1, leftSum), "INV-3: columns differ")
        #endif
    }
}

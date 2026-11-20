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
    /// The rules of a three-column layout;
    /// empty in the two-column one, which draws `total` as one bar instead.
    public var middle: [Span] = []

    /// Three columns, links → rules → nodes.
    ///
    /// Connections say which rule they matched and where they left, not
    /// which link carried them, so each rule's traffic is split over the
    /// links by the links' shares. The columns are laid out on one scale
    /// (ColumnLayout, INV-12) and then cut into continuous bands, one per
    /// link → rule → node path, so the two-leg drawing (FlowMesh, the dots)
    /// draws them as it draws the two-column picture: `left` on the link,
    /// `center` on the rule, `right` on the node.
    ///
    /// Several paths can join the same link and node through different
    /// rules, so a band's `to` here is its own index (an id for the dots),
    /// not the node; its colour still comes from `from`, the link.
    public static func make(links: [Double], rules: Int, nodes: Int, flows: [(rule: Int, node: Int, rate: Double)],
                            height: Double, gap: Double) -> SankeyLayout {
        let linkRates = links.map { $0.isFinite && $0 > 0 ? $0 : 0 }
        let linkTotal = linkRates.reduce(0, +)
        let clean = flows.filter { $0.rate.isFinite && $0.rate > 0 && $0.rule >= 0 && $0.rule < rules && $0.node >= 0 && $0.node < nodes }
        var ruleTotal = [Double](repeating: 0, count: max(rules, 0))
        for flow in clean { ruleTotal[flow.rule] += flow.rate }
        // Stage 0 carries each rule's traffic split by link share, so both stages add up to the same total.
        var stages: [ColumnLayout.Link] = []
        if linkTotal > 0 {
            for (link, rate) in linkRates.enumerated() where rate > 0 {
                for (rule, total) in ruleTotal.enumerated() where total > 0 {
                    stages.append(.init(stage: 0, from: link, to: rule, rate: total * rate / linkTotal))
                }
            }
            for flow in clean { stages.append(.init(stage: 1, from: flow.rule, to: flow.node, rate: flow.rate)) }
        }
        let columns = ColumnLayout.make(nodes: [links.count, max(rules, 0), max(nodes, 0)], links: stages, height: height, gap: gap)
        var layout = SankeyLayout()
        layout.left = columns.columns[0]
        layout.middle = columns.columns[1]
        layout.right = columns.columns[2]
        if let first = layout.middle.first, let last = layout.middle.last { layout.total = Span(first.lower, last.upper) }
        // Cut every rule along its height where an incoming or outgoing band
        // starts or ends; each piece is one continuous band.
        for (rule, node) in layout.middle.enumerated() where node.length > 0 {
            let incoming = columns.bands.filter { $0.stage == 0 && $0.to == rule }.sorted { $0.end.lower < $1.end.lower }
            let outgoing = columns.bands.filter { $0.stage == 1 && $0.from == rule }.sorted { $0.start.lower < $1.start.lower }
            var i = 0, o = 0, position = node.lower
            while i < incoming.count, o < outgoing.count {
                let a = incoming[i], b = outgoing[o]
                let next = min(a.end.upper, b.start.upper)
                let thickness = next - position
                if thickness > 1e-9 {
                    let inA = position - a.end.lower, inB = position - b.start.lower
                    layout.bands.append(Band(from: a.from, to: layout.bands.count,
                                             left: Span(a.start.lower + inA, a.start.lower + inA + thickness),
                                             right: Span(b.end.lower + inB, b.end.lower + inB + thickness),
                                             rate: thickness, center: Span(position, next)))
                }
                position = next
                if a.end.upper <= next + 1e-9 { i += 1 }
                if b.start.upper <= next + 1e-9 { o += 1 }
            }
        }
        return layout
    }

    /// The least share of a side's height a node with traffic gets.
    /// Why 2%: on the overview's 262 pt that is about
    /// 4.5 pt (less when many exits share the height), enough to see a band
    /// and its colour; without a floor an exit carrying a thousandth of the
    /// traffic showed a rate and no band at all. Chosen by eye.
    public static let thinnestShare = 0.02

    /// Width by share: each side always
    /// fills the height the gaps leave, a node as tall as its share of its
    /// own side. Absolute rates do not matter, and the two sides need not
    /// agree (links are measured on the interface, exits from connections).
    /// Links are spread over the height, exits opened around the middle, as
    /// in the capacity layout.
    public static func make(leftShares: [Double], rightShares: [Double], height: Double, gap: Double) -> SankeyLayout {
        let clean = { (rates: [Double]) in rates.map { $0.isFinite && $0 > 0 ? $0 : 0 } }
        let leftRates = clean(leftShares), rightRates = clean(rightShares)
        var layout = SankeyLayout()
        guard leftRates.contains(where: { $0 > 0 }), rightRates.contains(where: { $0 > 0 }) else {
            layout.left = spread(leftRates.map { _ in 0 }, height: height)
            layout.right = open(rightRates.map { _ in 0 }, gap: gap, height: height)
            return layout
        }
        // The column with more nodes spends more on gaps, so it sets the room.
        let room = max(0, height - gap * Double(max(leftRates.count, rightRates.count) - 1))
        let leftParts = shares(leftRates), rightParts = shares(rightRates)
        layout.left = spread(leftParts.map { $0 * room }, height: height)
        layout.right = open(rightParts.map { $0 * room }, gap: gap, height: height)
        let start = (height - room) / 2
        layout.total = Span(start, start + room)
        var leftCursor = layout.left.map(\.lower)
        var centerCursor = layout.total.lower
        for (j, exit) in rightParts.enumerated() where exit > 0 {
            var rightCursor = layout.right[j].lower
            for (i, link) in leftParts.enumerated() where link > 0 {
                let thickness = link * exit * room
                layout.bands.append(Band(from: i, to: j, left: Span(leftCursor[i], leftCursor[i] + thickness),
                                         right: Span(rightCursor, rightCursor + thickness), rate: leftRates[i] * exit,
                                         center: Span(centerCursor, centerCursor + thickness)))
                leftCursor[i] += thickness
                rightCursor += thickness
                centerCursor += thickness
            }
        }
        layout.checkInvariants(height: height)
        return layout
    }

    /// Each rate's share of the total, with every non-zero one raised to at
    /// least `thinnestShare`; what the small ones gain the others give up in
    /// proportion, so the shares still add up to one and keep their order.
    static func shares(_ rates: [Double]) -> [Double] {
        let total = rates.reduce(0, +)
        guard total > 0 else { return rates.map { _ in 0 } }
        let positive = rates.filter { $0 > 0 }.count
        let floor = min(thinnestShare, 1 / Double(positive))
        var parts = rates.map { $0 / total }
        var floored = Set<Int>()
        // Raising one node shrinks the rest, which may push another under the
        // floor: repeat until nothing moves (at most once per node).
        while true {
            let free = 1 - floor * Double(floored.count)
            let rest = parts.indices.filter { rates[$0] > 0 && !floored.contains($0) }.map { rates[$0] }.reduce(0, +)
            var changed = false
            for index in parts.indices where rates[index] > 0 && !floored.contains(index) {
                let part = rest > 0 ? rates[index] / rest * free : 0
                if part < floor {
                    floored.insert(index)
                    changed = true
                } else {
                    parts[index] = part
                }
            }
            for index in floored { parts[index] = floor }
            if !changed { return parts }
        }
    }

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

/// A flow diagram with any number of columns (INV-12).
public struct ColumnLayout: Equatable, Sendable {
    public struct Link: Equatable, Sendable {
        /// Between column `stage` and `stage + 1`.
        public var stage: Int
        public var from: Int
        public var to: Int
        public var rate: Double
        public init(stage: Int, from: Int, to: Int, rate: Double) {
            self.stage = stage; self.from = from; self.to = to; self.rate = rate
        }
    }

    public struct Band: Equatable, Sendable {
        public var stage: Int
        public var from: Int
        public var to: Int
        public var start: Span
        public var end: Span
    }

    /// Nodes per column, top to bottom.
    public var columns: [[Span]] = []
    public var bands: [Band] = []

    /// One scale for the whole diagram: a band is `rate × scale` thick at
    /// both ends, a node is as tall as the bands through it, and the busiest
    /// column fills the height its gaps leave. Callers make the stages
    /// agree (FlowColumns gives every stage the same total); where they do
    /// not, the thinner column is simply shorter.
    /// - Parameters:
    ///   - nodes: how many nodes each column has.
    ///   - links: flows between neighbouring columns, all in one unit.
    public static func make(nodes: [Int], links: [Link], height: Double, gap: Double) -> ColumnLayout {
        let count = nodes.count
        var layout = ColumnLayout()
        let clean = links.filter { $0.rate.isFinite && $0.rate > 0 && $0.stage >= 0 && $0.stage < count - 1
            && $0.from >= 0 && $0.from < nodes[$0.stage] && $0.to >= 0 && $0.to < nodes[$0.stage + 1] }
        guard count >= 2, !clean.isEmpty else {
            layout.columns = nodes.map { Self.spread([Double](repeating: 0, count: $0), height: height, gap: gap) }
            return layout
        }
        // What passes through each node: the larger of its inflow and outflow
        // (they are equal when the stages agree).
        var out = nodes.map { [Double](repeating: 0, count: $0) }, inn = out
        for link in clean {
            out[link.stage][link.from] += link.rate
            inn[link.stage + 1][link.to] += link.rate
        }
        let through = (0..<count).map { c in (0..<nodes[c]).map { max(out[c][$0], inn[c][$0]) } }
        // The scale that lets every column fit its own height after gaps.
        let scale = (0..<count).compactMap { c -> Double? in
            let total = through[c].reduce(0, +)
            guard total > 0 else { return nil }
            return max(0, height - gap * Double(max(nodes[c] - 1, 0))) / total
        }.min() ?? 0
        layout.columns = through.map { column in Self.spread(column.map { $0 * scale }, height: height, gap: gap) }
        // Cut each node by its links: outgoing in the order of the next column's
        // nodes, incoming in the order of the previous column's.
        var startCursor = layout.columns.map { $0.map(\.lower) }, endCursor = startCursor
        let ordered = clean.sorted { ($0.stage, $0.from, $0.to) < ($1.stage, $1.from, $1.to) }
        var starts: [Int: Span] = [:]
        for (index, link) in ordered.enumerated() {
            let thickness = link.rate * scale
            starts[index] = Span(startCursor[link.stage][link.from], startCursor[link.stage][link.from] + thickness)
            startCursor[link.stage][link.from] += thickness
        }
        for index in ordered.indices.sorted(by: { (ordered[$0].stage, ordered[$0].to, ordered[$0].from) < (ordered[$1].stage, ordered[$1].to, ordered[$1].from) }) {
            let link = ordered[index], thickness = link.rate * scale
            let end = Span(endCursor[link.stage + 1][link.to], endCursor[link.stage + 1][link.to] + thickness)
            endCursor[link.stage + 1][link.to] += thickness
            layout.bands.append(Band(stage: link.stage, from: link.from, to: link.to, start: starts[index]!, end: end))
        }
        return layout
    }

    /// Spread over the height: first node at the top, last at the bottom,
    /// at least `gap` apart; one node in the middle.
    static func spread(_ heights: [Double], height: Double, gap: Double) -> [Span] {
        let used = heights.reduce(0, +)
        let between = heights.count > 1 ? max(gap, (height - used) / Double(heights.count - 1)) : 0
        var cursor = heights.count > 1 ? 0 : max(0, (height - used) / 2)
        return heights.map { length in
            defer { cursor += length + between }
            return Span(cursor, cursor + length)
        }
    }
}

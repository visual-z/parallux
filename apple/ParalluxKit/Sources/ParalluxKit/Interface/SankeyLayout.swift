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
        SankeyLayout()
    }
}

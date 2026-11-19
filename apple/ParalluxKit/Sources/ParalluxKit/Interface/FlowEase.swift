import Foundation

/// Eases the flow diagram's rates from one sample to the next (perf-flow-animation).
public struct FlowEase: Equatable, Sendable {
    public static let duration = 0.4

    public init() {}

    public var value: [Double] { [] }
    public var isSettled: Bool { false }

    public mutating func retarget(_ target: [Double]) {}
    public mutating func advance(by seconds: Double) {}
    public mutating func finish() {}
}

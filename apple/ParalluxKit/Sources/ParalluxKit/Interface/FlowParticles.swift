import Foundation

/// The dots that travel along the flow diagram's bands (design v0.2).
public struct FlowParticles: Sendable {
    public struct Particle: Equatable, Sendable {
        public var from: Int
        public var to: Int
        public var progress: Double
        public var lane: Double
        public var speed: Double
    }

    public static let limit = 900
    public private(set) var particles: [Particle] = []

    public init() {}

    public mutating func step(by seconds: Double, bands: [SankeyLayout.Band], using generator: inout some RandomNumberGenerator) {}

    public static func y(of particle: Particle, in band: SankeyLayout.Band) -> Double { 0 }
}

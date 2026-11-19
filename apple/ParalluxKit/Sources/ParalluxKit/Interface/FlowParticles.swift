import Foundation

/// The dots that travel along the flow diagram's bands (design v0.2): what
/// exists and how far each has come. Drawing is the view's job; this stays a
/// pure model so its bound can be tested (INV-8).
public struct FlowParticles: Sendable {
    public struct Particle: Equatable, Sendable {
        /// The band it rides, by link and exit index.
        public var from: Int
        public var to: Int
        /// 0..<1 link to centre bar, 1..<2 centre bar to exit.
        public var progress: Double
        /// 0...1 across the band's thickness.
        public var lane: Double
        /// Stages per second.
        public var speed: Double
    }

    /// Why 900: at full scale the bands are about 260 pt thick in total, which
    /// spawns 260 × density ≈ 220 a second, each living 2 / 0.48 ≈ 4 s, so
    /// about 900 alive. Past the limit the oldest go first. Without it a
    /// stalled clock or a huge step could grow the array without bound.
    /// Derived from the design's numbers, not measured.
    public static let limit = 900
    /// Particles per second per point of band thickness. Why 0.85: design
    /// v0.2 spawns `Mbps / 4.5` a second and draws 0.26 pt per Mbps.
    public static let density = 0.85
    /// Why 0.05 s: the design's clamp. A longer step (the window was hidden,
    /// the Mac slept) would otherwise release a burst of particles at once.
    public static let longestStep = 0.05
    /// Stages per second, as in the design (0.45...0.75 × 0.8).
    static let speeds = 0.36...0.6

    public private(set) var particles: [Particle] = []

    public init() {}

    public mutating func step(by seconds: Double, bands: [SankeyLayout.Band], using generator: inout some RandomNumberGenerator) {
        let dt = min(max(seconds.isFinite ? seconds : 0, 0), Self.longestStep)
        // Advance; drop the ones that arrived or whose band is gone.
        var kept: [Particle] = []
        kept.reserveCapacity(particles.count)
        for var particle in particles {
            particle.progress += particle.speed * dt
            guard particle.progress < 2, bands.contains(where: { $0.from == particle.from && $0.to == particle.to }) else { continue }
            kept.append(particle)
        }
        // Spawn in proportion to thickness: the whole part, then one more
        // with the fraction as its probability.
        for band in bands where band.left.length > 0 {
            var expected = band.left.length * Self.density * dt
            while expected > 0 {
                if expected >= 1 || Double.random(in: 0..<1, using: &generator) < expected {
                    kept.append(Particle(from: band.from, to: band.to, progress: 0,
                                         lane: Double.random(in: 0...1, using: &generator),
                                         speed: Double.random(in: Self.speeds, using: &generator)))
                }
                expected -= 1
            }
        }
        particles = kept.count > Self.limit ? Array(kept.suffix(Self.limit)) : kept
    }

    /// The band's edges are cubic Béziers whose inner control points sit at
    /// mid-x on the end heights. In the curve's own parameter `t` that gives
    /// these two polynomials, so a particle placed with them is on the band,
    /// not near it.
    public static func rise(_ t: Double) -> Double { t * t * (3 - 2 * t) }
    public static func run(_ t: Double) -> Double { t * (1.5 - 1.5 * t + t * t) }

    public static func y(of particle: Particle, in band: SankeyLayout.Band) -> Double {
        let (start, end) = particle.progress < 1 ? (band.left, band.center) : (band.center, band.right)
        let t = particle.progress < 1 ? particle.progress : particle.progress - 1
        let top = start.lower + (end.lower - start.lower) * rise(t)
        return top + particle.lane * band.left.length
    }
}

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

    /// How busy the dots are for a total rate, 0...1: the one thing in the
    /// diagram that still says how much traffic there is, now that widths are
    /// shares. Logarithmic, because rates
    /// span five orders of magnitude and a thousand times the traffic should
    /// look clearly busier, not a thousand times as dense.
    /// Why these ends: under 10 kbit/s is background chatter (a few dots, so
    /// the picture is not dead); 100 Mbit/s fills the bands as the design's
    /// demo does. Assumed; to revisit, watch a download of known speed.
    public static func intensity(bytesPerSecond rate: Double) -> Double {
        guard rate.isFinite, rate > 0 else { return 0 }
        let quiet = 1250.0, full = 12_500_000.0, least = 0.08
        guard rate > quiet else { return least }
        guard rate < full else { return 1 }
        return least + (1 - least) * log10(rate / quiet) / log10(full / quiet)
    }


    public mutating func step(by seconds: Double, bands: [SankeyLayout.Band], intensity: Double = 1, using generator: inout some RandomNumberGenerator) {
        let dt = min(max(seconds.isFinite ? seconds : 0, 0), Self.longestStep)
        // Which (link, exit) pairs still have a band: a table, not a search
        // per particle (hundreds of particles, every frame).
        let exits = (bands.map(\.to).max() ?? -1) + 1
        var alive = [Bool](repeating: false, count: ((bands.map(\.from).max() ?? -1) + 1) * exits)
        for band in bands { alive[band.from * exits + band.to] = true }
        // Advance in place; drop the ones that arrived or whose band is gone.
        var kept = particles
        var count = 0
        for index in kept.indices {
            var particle = kept[index]
            particle.progress += particle.speed * dt
            let slot = particle.from * exits + particle.to
            guard particle.progress < 2, particle.to < exits, slot < alive.count, alive[slot] else { continue }
            kept[count] = particle
            count += 1
        }
        kept.removeSubrange(count...)
        // Spawn in proportion to thickness: the whole part, then one more
        // with the fraction as its probability.
        for band in bands where band.left.length > 0 {
            var expected = band.left.length * Self.density * dt * min(max(intensity.isFinite ? intensity : 0, 0), 1)
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

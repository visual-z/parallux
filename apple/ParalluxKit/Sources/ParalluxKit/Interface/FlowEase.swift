import Foundation

/// Eases the flow diagram's rates from one sample to the next
/// (perf-flow-animation).
///
/// A fixed-length curve, not "move a share of the gap every frame": that one
/// never arrives, so the band layer could never stop redrawing, and how fast
/// it went depended on the frame rate. This is a function of elapsed time
/// alone and lands on the target exactly.
public struct FlowEase: Equatable, Sendable {
    /// Seconds from one sample to the next being fully shown. Why 0.4: rates
    /// arrive once a second, so the bands rest (and cost nothing) for the
    /// other 0.6 s; shorter reads as a jump, longer is still moving when the
    /// next sample lands. Chosen by eye against design v0.2's roughly 0.3 s
    /// time constant; not measured.
    public static let duration = 0.4

    private var from: [Double] = []
    private var to: [Double] = []
    private var elapsed = duration

    public init() {}

    /// The rates to draw now.
    public var value: [Double] {
        guard elapsed < Self.duration else { return to }
        // Ease-out cubic: fast at first, settling into place.
        let remaining = 1 - elapsed / Self.duration
        let progress = 1 - remaining * remaining * remaining
        // from + (to - from) * p, clamped: rounding must not step outside the ends.
        return zip(from, to).map { start, end in
            min(max(start + (end - start) * progress, min(start, end)), max(start, end))
        }
    }

    /// Nothing left to animate.
    public var isSettled: Bool { elapsed >= Self.duration }

    /// A new sample. Carries on from the value on screen; a different number
    /// of nodes (or the very first sample) cannot be eased and is taken as is.
    public mutating func retarget(_ target: [Double]) {
        guard target != to else { return }
        let current = value
        to = target
        if current.count == target.count, current != target {
            from = current
            elapsed = 0
        } else {
            from = target
            elapsed = Self.duration
        }
    }

    /// Zero, negative and NaN steps move nothing.
    public mutating func advance(by seconds: Double) {
        guard seconds > 0 else { return }
        elapsed = min(Self.duration, elapsed + seconds)
    }

    /// Lands at once (reduced motion, a hidden window).
    public mutating func finish() { elapsed = Self.duration }
}

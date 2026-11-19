import Foundation

/// The rate that fills the flow diagram's height. Design v0.2 draws width =
/// rate against a fixed 1000 Mbps (its demo data); a fixed figure would draw
/// everyday traffic thinner than a pixel, so the full-scale value follows the
/// recent peak instead, in steps so it does not twitch with every sample.
public enum FlowScale {
    /// Bytes per second; 1 Mbit/s. Why a floor: below it the "peak" is only
    /// background chatter, and scaling to it would fill the diagram with
    /// traffic nobody would call traffic (the full-height block this replaced).
    /// Why this value: the smallest rate a person notices as "something is
    /// loading". Assumed, not measured; to revisit, watch an idle Mac's total
    /// in the overview for a minute and take the usual peak.
    public static let floor: Int64 = 125_000

    /// The smallest 1-2-5 step (times the floor) that holds `peak`. Never
    /// above 2.5 × peak, so the busiest moment fills at least 40% of the
    /// height. Past the last step that fits an Int64 the peak is its own
    /// capacity.
    public static func capacity(peak: Int64) -> Int64 {
        var decade = floor
        while true {
            for multiple: Int64 in [1, 2, 5] {
                let (step, overflow) = decade.multipliedReportingOverflow(by: multiple)
                if overflow { return max(peak, floor) }
                if step >= peak { return step }
            }
            let (next, overflow) = decade.multipliedReportingOverflow(by: 10)
            if overflow { return max(peak, floor) }
            decade = next
        }
    }
}

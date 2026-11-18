import Foundation

/// Formats byte counters for the interface. Rates are shown in bits per
/// second (network convention, the design's "612 Mbps"); totals in bytes.
public enum RateFormat {
    public static func bitsPerSecond(_ bytesPerSecond: Int64) -> String {
        let bits = Double(max(bytesPerSecond, 0)) * 8
        let units = ["bps", "Kbps", "Mbps", "Gbps"]
        var value = bits
        var unit = 0
        while value >= 1000, unit < units.count - 1 {
            value /= 1000
            unit += 1
        }
        return value < 10 && unit > 0 ? String(format: "%.1f %@", value, units[unit]) : "\(Int(value.rounded())) \(units[unit])"
    }

    public static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(count, 0), countStyle: .binary)
    }
}

import Foundation

/// The rate that fills the flow diagram's height (docs/tasks/fix-overview-design-parity.md).
public enum FlowScale {
    public static let floor: Int64 = 125_000

    public static func capacity(peak: Int64) -> Int64 { max(peak, 0) }
}

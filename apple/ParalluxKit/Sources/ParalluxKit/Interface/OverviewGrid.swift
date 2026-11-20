import Foundation

// stub: fix-overview-responsive

/// How the overview's cards share the width they are given.
public enum OverviewGrid {
    public static let minimumCardWidth: Double = 200
    public static let spacing: Double = 12

    public static func rows(count: Int, width: Double) -> [Range<Int>] {
        count > 0 ? [0..<count] : []
    }
}

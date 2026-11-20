import Foundation

// stub: fix-route-modes

/// Gives a profile the route modes 全局 and 直连.
public enum RouteModes {
    public static let direct = "Direct"
    public static let global = "Global"

    public static func add(to profile: String) -> String { profile }
}

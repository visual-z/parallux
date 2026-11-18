import Foundation

/// Where the running app bundle sits. macOS only activates a system
/// extension whose app is in /Applications (Apple, "Installing System
/// Extensions and Drivers"); a quarantined download runs translocated from
/// a random read-only path, which also blocks activation.
public enum ApplicationsLocation: Equatable, Sendable {
    case ok
    case translocated
    case notInApplications

    public static func classify(bundlePath: String, home: String) -> ApplicationsLocation { .ok }
}

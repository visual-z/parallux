import Foundation

/// Where the running app bundle sits. macOS only activates a system
/// extension whose app is in /Applications (Apple, "Installing System
/// Extensions and Drivers"); a quarantined download runs translocated from
/// a random read-only path, which also blocks activation.
public enum ApplicationsLocation: Equatable, Sendable {
    case ok
    case translocated
    case notInApplications

    public static func classify(bundlePath: String, home: String) -> ApplicationsLocation {
        let components = URL(fileURLWithPath: bundlePath).standardizedFileURL.pathComponents
        guard !bundlePath.isEmpty else { return .notInApplications }
        if components.contains("AppTranslocation") { return .translocated }
        let path = "/" + components.dropFirst().joined(separator: "/")
        let roots = ["/Applications/", URL(fileURLWithPath: home).standardizedFileURL.path + "/Applications/"]
        return roots.contains { path.hasPrefix($0) } ? .ok : .notInApplications
    }
}

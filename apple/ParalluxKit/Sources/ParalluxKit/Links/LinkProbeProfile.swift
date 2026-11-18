import Foundation

/// A throwaway sing-box profile that exercises Decision 13's real path:
/// one `direct` outbound with `bind_interface` per interface, URL-tested
/// together (research-sysext-bind-interface, feat-probe-arms).
public enum LinkProbeProfile {
    public static let groupTag = "probe"
    public static func outboundTag(_ interface: String) -> String { "probe-\(interface)" }
    /// Why this URL: a 204 endpoint with no body, the kind sing-box's docs use for urltest.
    public static let testURL = "http://cp.cloudflare.com/generate_204"

    /// nil when there is nothing to probe.
    public static func make(interfaces: [String]) -> String? { nil }
}

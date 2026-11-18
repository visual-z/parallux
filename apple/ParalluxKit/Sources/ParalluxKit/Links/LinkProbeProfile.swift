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
    public static func make(interfaces: [String]) -> String? {
        guard !interfaces.isEmpty else { return nil }
        let tags = interfaces.map(outboundTag)
        var outbounds: [[String: Any]] = zip(interfaces, tags).map { name, tag in
            ["type": "direct", "tag": tag, "bind_interface": name]
        }
        // Why 10 m: the diagnostics page triggers tests by hand; a short
        // interval would keep testing in the background.
        outbounds.append(["type": "urltest", "tag": groupTag, "outbounds": tags, "url": testURL, "interval": "10m"])
        outbounds.append(["type": "direct", "tag": "direct"])
        let profile: [String: Any] = [
            "log": ["level": "debug"],
            "dns": ["servers": [["type": "local", "tag": "local"]]],
            "inbounds": [[
                "type": "tun", "tag": "tun-in", "address": ["172.19.0.1/30", "fdfe:dcba:9876::1/126"],
                "auto_route": true, "strict_route": true,
            ]],
            "outbounds": outbounds,
            "route": [
                "rules": [["action": "sniff"], ["protocol": "dns", "action": "hijack-dns"]],
                "final": "direct",
                "auto_detect_interface": true,
            ],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: profile, options: [.prettyPrinted, .sortedKeys]) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}

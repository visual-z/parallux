import Foundation

/// The profile for 聚合 on, 代理 off (feat-split-switches): everything goes
/// out `direct`, which ProfileComposer then turns into the aggregate over the
/// enabled links.
///
/// Only the user's tun inbound is kept (its addresses, MTU, stack). Their DNS
/// servers are not: they may detour through a node, which is off here.
public enum DirectProfile {
    public static let directTag = "direct"

    static var defaultTun: [String: Any] { [
        "type": "tun", "tag": "tun-in",
        "address": ["172.19.0.1/30", "fdfe:dcba:9876::1/126"],
        "auto_route": true, "strict_route": true,
    ] }

    public static func make(from profile: String?) -> String {
        let user = profile.flatMap { (try? JSONSerialization.jsonObject(with: Data($0.utf8))) as? [String: Any] }
        let tun = ((user?["inbounds"] as? [[String: Any]]) ?? []).first { $0["type"] as? String == "tun" } ?? defaultTun
        var root: [String: Any] = [
            "dns": ["servers": [["type": "local", "tag": "local"]]],
            "inbounds": [tun],
            "outbounds": [["type": "direct", "tag": directTag]],
            "route": [
                "rules": [["action": "sniff"], ["protocol": "dns", "action": "hijack-dns"]],
                "final": directTag,
                "auto_detect_interface": true,
            ] as [String: Any],
        ]
        if let log = user?["log"] { root["log"] = log }
        // A fixed key order keeps reloads comparable in the log.
        let data = (try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }
}

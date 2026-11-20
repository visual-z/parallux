import Foundation

/// User-facing text for profiles (design: "远程 · 每 12 小时更新 · 3 小时前更新").
public enum ProfileDescription {
    public static let intervalChoices: [TimeInterval] = [15 * 60, 3600, 6 * 3600, 12 * 3600, 86400, 7 * 86400]

    public static func interval(_ seconds: TimeInterval) -> String {
        let clamped = RemoteUpdate.clamp(seconds)
        if clamped < 3600 { return "\(Int(clamped / 60)) 分钟" }
        if clamped < 86400 { return "\(Int(clamped / 3600)) 小时" }
        return "\(Int(clamped / 86400)) 天"
    }

    public static func detail(_ profile: Profile, now: Date) -> String {
        switch profile.kind {
        case .local:
            return "本地"
        case .icloud:
            return "iCloud · \(profile.icloudPath ?? "")"
        case .remote:
            var parts = ["远程"]
            if profile.autoUpdate { parts.append("每 \(interval(profile.autoUpdateInterval))更新") }
            if let last = profile.lastUpdated { parts.append(ago(last, now: now) + "更新") }
            return parts.joined(separator: " · ")
        }
    }

    static func ago(_ date: Date, now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return "刚刚" }
        if seconds < 3600 { return "\(Int(seconds / 60)) 分钟前" }
        if seconds < 86400 { return "\(Int(seconds / 3600)) 小时前" }
        return "\(Int(seconds / 86400)) 天前"
    }

    /// A valid starting point for a new local profile: tun plus direct.
    public static let blankTemplate = """
    {
      "log": { "level": "info" },
      "dns": { "servers": [ { "type": "local", "tag": "local" } ] },
      "inbounds": [
        { "type": "tun", "tag": "tun-in", "address": ["172.19.0.1/30", "fdfe:dcba:9876::1/126"], "auto_route": true, "strict_route": true }
      ],
      "outbounds": [ { "type": "direct", "tag": "direct" } ],
      "route": { "rules": [ { "action": "sniff" }, { "protocol": "dns", "action": "hijack-dns" } ], "auto_detect_interface": true }
    }
    """
}

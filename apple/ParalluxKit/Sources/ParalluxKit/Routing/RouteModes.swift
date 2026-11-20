import Foundation

/// Gives a profile the route modes 全局 and 直连 when it defines none.
///
/// sing-box has no built-in modes. The list it offers (and the app shows) is
/// read from the `clash_mode` rules of the configuration, with the default
/// mode `Rule` in front; a subscription without such rules can only ever be
/// in 规则, and the mode control has nothing to switch to. Two rules, added
/// when connecting, give the core the other two:
///
///     {"clash_mode": "Direct", "outbound": <the profile's direct outbound>}
///     {"type": "logical", "mode": "and",
///      "rules": [{"clash_mode": "Global"}, {"ip_is_private": true, "invert": true}],
///      "outbound": <where the profile sends everything else>}
///
/// The profile file is never edited, as with route overrides (decision 20).
public enum RouteModes {
    public static let direct = "Direct"
    public static let global = "Global"

    /// Actions that prepare a connection without deciding where it goes.
    /// The mode rules come after the leading run of these, so sniffing and
    /// DNS hijacking still happen in every mode.
    static let preparing: Set<String> = ["sniff", "resolve", "hijack-dns", "route-options"]
    /// Outbound types that are not somewhere to proxy through.
    static let notAProxy: Set<String> = ["direct", "block", "dns"]
    static let groups: Set<String> = ["selector", "urltest"]

    /// The profile with the two mode rules, or exactly `profile` when it is
    /// not a JSON object or already defines a mode of its own: someone who
    /// wrote mode rules meant them.
    public static func add(to profile: String) -> String {
        guard var root = (try? JSONSerialization.jsonObject(with: Data(profile.utf8))) as? [String: Any] else { return profile }
        var route = (root["route"] as? [String: Any]) ?? [:]
        var rules = (route["rules"] as? [[String: Any]]) ?? []
        let dnsRules = ((root["dns"] as? [String: Any])?["rules"] as? [[String: Any]]) ?? []
        guard !definesModes(rules), !definesModes(dnsRules) else { return profile }

        var outbounds = (root["outbounds"] as? [[String: Any]]) ?? []
        func type(of tag: String?) -> String? {
            guard let tag else { return nil }
            return outbounds.first { $0["tag"] as? String == tag }?["type"] as? String
        }
        func firstTag(where matches: (String) -> Bool) -> String? {
            outbounds.first { ($0["type"] as? String).map(matches) ?? false }?["tag"] as? String
        }

        // 直连: the profile's own direct outbound. With links on, the
        // composer turns it into the aggregate of the same tag, so direct
        // mode still spreads over the links.
        let directTag: String
        if let existing = firstTag(where: { $0 == "direct" }) {
            directTag = existing
        } else {
            let taken = Set(outbounds.compactMap { $0["tag"] as? String })
            directTag = taken.contains("direct") ? "parallux-direct" : "direct"
            outbounds.append(["type": "direct", "tag": directTag])
            root["outbounds"] = outbounds
        }

        // 全局: where the profile sends "everything else", which is what
        // its author thinks of as the proxy. A whitelist profile ends in
        // direct or block; then the first group, then the first node.
        let final = route["final"] as? String
        let finalType = type(of: final)
        let globalTag: String?
        if let final, let finalType, !notAProxy.contains(finalType) {
            globalTag = final
        } else {
            globalTag = firstTag(where: groups.contains) ?? firstTag(where: ProfileComposer.proxyTypes.contains)
        }

        var added: [[String: Any]] = [["clash_mode": direct, "outbound": directTag]]
        if let globalTag {
            // Private addresses are left to the profile's own rules, as in
            // 规则: switching to 全局 must not send the NAS and the printer
            // to the proxy. A destination that is still a name has no
            // address to be private, so it goes to the proxy.
            added.append([
                "type": "logical", "mode": "and",
                "rules": [["clash_mode": global], ["ip_is_private": true, "invert": true] as [String: Any]],
                "outbound": globalTag,
            ])
        }
        let position = rules.prefix { rule in
            if let action = rule["action"] as? String { return preparing.contains(action) }
            // The older way to hand DNS over: a rule to an outbound of type dns.
            return type(of: rule["outbound"] as? String) == "dns"
        }.count
        rules.insert(contentsOf: added, at: position)
        route["rules"] = rules
        root["route"] = route

        // 直连 is what people switch to when the node is down, and then a
        // DNS server reached through the node resolves nothing. Names go to
        // the profile's local server in that mode, when it has one
        // (GUI.for.SingBox and sing-box-subscribe pair their mode rules
        // with DNS rules the same way). 全局 keeps the profile's DNS rules.
        if var dns = root["dns"] as? [String: Any], let local = localServer(dns) {
            dns["rules"] = dnsRules
            root["dns"] = dns
        }
        guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]) else { return profile }
        return String(decoding: data, as: UTF8.self)
    }

    /// The tag of the profile's DNS server that asks the system resolver:
    /// `type: local`, or `address: local` in the format before sing-box 1.12.
    static func localServer(_ dns: [String: Any]) -> String? {
        let servers = (dns["servers"] as? [[String: Any]]) ?? []
        return servers.first { $0["type"] as? String == "local" || $0["address"] as? String == "local" }?["tag"] as? String
    }

    /// Whether any rule, or a rule inside a logical rule, names a mode.
    static func definesModes(_ rules: [[String: Any]]) -> Bool {
        rules.contains { rule in
            if let mode = rule["clash_mode"] as? String, !mode.isEmpty { return true }
            return definesModes((rule["rules"] as? [[String: Any]]) ?? [])
        }
    }
}

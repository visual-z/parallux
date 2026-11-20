import Foundation

/// A minimal configuration for the first connection before profiles exist
/// (M2): a tun inbound with auto_route and a direct outbound. Proves the
/// extension path end to end without any node. The JSON is checked against
/// libbox by core/pxbridge TestTheBundledSampleProfilePassesLibboxCheckConfig.
enum SampleProfile {
    static var content: String {
        guard let url = Bundle.main.url(forResource: "sample-profile", withExtension: "json"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return "{}" }
        return text
    }
}

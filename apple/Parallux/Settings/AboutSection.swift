import Libbox
import SwiftUI

/// 设置 › 关于: versions, source and licences (SFM parity #110).
struct AboutSection: View {
    /// From PLAN decision 9's bundle id owner; the repository has no git
    /// remote yet (2026-11-19), so this address is unverified.
    static let sourceURL = URL(string: "https://github.com/visual-z/parallux")!

    /// Summary of docs/LICENSES.md for people who do not read the repository.
    static let thirdParty: [(name: String, license: String)] = [
        ("sing-box", "GPLv3"),
        ("sing-box for Apple", "GPLv3"),
        ("singbox-multipath", "GPLv3"),
        ("gomobile", "BSD-3-Clause"),
    ]

    var body: some View {
        Form {
            Section {
                LabeledContent("版本", value: "\(Self.info("CFBundleShortVersionString")) (\(Self.info("CFBundleVersion")))")
                LabeledContent("核心", value: PxbridgeVersion())
                Link("源代码", destination: Self.sourceURL)
            }
            Section("GPLv3") {
                ForEach(Self.thirdParty, id: \.name) { item in
                    LabeledContent(item.name, value: item.license)
                }
            }
        }
        .formStyle(.grouped)
    }

    private static func info(_ key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "?"
    }
}

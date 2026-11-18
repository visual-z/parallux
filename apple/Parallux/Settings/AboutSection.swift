import Libbox
import SwiftUI

/// 设置 › 关于: versions, source and licences (SFM parity #110).
struct AboutSection: View {
    /// From PLAN decision 9's bundle id owner; the repository has no git
    /// remote yet (2026-11-19), so this address is unverified.
    static let sourceURL = URL(string: "https://github.com/visual-z/parallux")!

    /// Summary of docs/LICENSES.md for people who do not read the repository.
    static let thirdParty: [(name: String, license: String)] = [
        ("sing-box（含 libbox）", "GPLv3"),
        ("sing-box for Apple（SFM）的部分做法与代码", "GPLv3"),
        ("singbox-multipath（叠加传输）", "GPLv3"),
        ("gomobile", "BSD-3-Clause"),
    ]

    var body: some View {
        Form {
            Section {
                LabeledContent("版本", value: "\(Self.info("CFBundleShortVersionString")) (\(Self.info("CFBundleVersion")))")
                LabeledContent("内核", value: PxbridgeVersion())
                Link("源代码", destination: Self.sourceURL)
            }
            Section("许可") {
                Text("Parallux 以 GPLv3 发布。本软件不收集任何使用数据。").font(.callout)
                ForEach(Self.thirdParty, id: \.name) { item in
                    LabeledContent(item.name, value: item.license)
                }
                Text("sing-box 与 singbox-multipath 的许可附加条款：衍生作品不得使用其名称或暗示与其关联。Parallux 与它们的作者无关。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private static func info(_ key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "?"
    }
}

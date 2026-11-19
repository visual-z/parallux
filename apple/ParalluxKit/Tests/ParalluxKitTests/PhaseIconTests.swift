import AppKit
import Foundation
import Testing
@testable import ParalluxKit

@MainActor @Suite struct PhaseIconTests {
    @Test func eachPhaseIconAnnouncesItsConnectionProxyAndHealthState() {
        let running = [
            "仅代理", "聚合待命 · 代理关闭", "聚合待命 · 代理开启",
            "分流 · 代理关闭", "分流 · 代理开启", "叠加 · 代理开启",
            "主备 · 代理关闭", "主备 · 代理开启",
        ]
        let expected = Set((["未连接", "正在连接", "正在断开", "连接异常"]
            + running.flatMap { [$0, $0 + " · 异常"] }).map { "Parallux " + $0 })
        let actual = Set(MenuBarIcon.State.allCases.compactMap { MenuBarIcon.image(for: $0).accessibilityDescription })
        #expect(actual == expected)
    }

    @Test func theAppTargetSelectsTheLayeredPhaseIcon() throws {
        let apple = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let project = try String(contentsOf: apple.appendingPathComponent("project.yml"), encoding: .utf8)
        let app = try #require(project.components(separatedBy: "  ParalluxHelper:").first)
        #expect(app.contains("ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon"))
        let package = apple.appendingPathComponent("AppIcon.icon")
        #expect(FileManager.default.fileExists(atPath: package.appendingPathComponent("icon.json").path))
    }
}

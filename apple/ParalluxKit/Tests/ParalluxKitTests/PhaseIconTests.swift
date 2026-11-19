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
        let data = try Data(contentsOf: package.appendingPathComponent("icon.json"))
        let document = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let groups = try #require(document["groups"] as? [[String: Any]])
        #expect(groups.count == 2)
        var vectors = Set<String>()
        for group in groups {
            let layers = try #require(group["layers"] as? [[String: Any]])
            #expect(layers.count == 1)
            let name = try #require(layers.first?["image-name"] as? String)
            #expect(name.hasSuffix(".svg"))
            let svg = try String(contentsOf: package.appendingPathComponent("Assets").appendingPathComponent(name), encoding: .utf8)
            #expect(svg.contains("<path"))
            vectors.insert(svg)
        }
        #expect(vectors.count == 2)
    }

    @Test func theIconFollowsTheEffectiveModeAndDisplayedSwitches() {
        let modes: [AggregationMode?] = [nil, .balance, .bond, .failover]
        let switches: [ConnectionSwitches] = [.none, .init(aggregation: false, proxy: true),
                                               .init(aggregation: true, proxy: false), .both]
        let phases: [StatusLine.Tunnel] = [.disconnected, .connecting, .connected, .disconnecting]
        var reachable = Set<MenuBarIcon.State>()
        for phase in phases {
            for setting in switches {
                for mode in modes {
                    for serviceError in [false, true] {
                        for linkError in [false, true] {
                            let state = MenuBarIcon.State.resolve(tunnel: phase, switches: setting, effectiveMode: mode,
                                                                  serviceError: serviceError, linkError: linkError)
                            reachable.insert(state)
                            let expected: String
                            switch phase {
                            case .disconnected: expected = serviceError ? "连接异常" : "未连接"
                            case .connecting: expected = "正在连接"
                            case .disconnecting: expected = "正在断开"
                            case .connected where setting == .none: expected = "正在断开"
                            case .connected where !setting.aggregation: expected = serviceError ? "仅代理 · 异常" : "仅代理"
                            case .connected:
                                let actualMode = mode == .bond && !setting.proxy ? .failover : mode
                                expected = (actualMode?.title ?? "聚合待命")
                                    + (setting.proxy ? " · 代理开启" : " · 代理关闭")
                                    + (serviceError || linkError ? " · 异常" : "")
                            }
                            #expect(state.title == expected, "\(phase) \(setting) \(String(describing: mode)) \(serviceError) \(linkError)")
                        }
                    }
                }
            }
        }
        #expect(reachable == Set(MenuBarIcon.State.allCases))
    }

    @Test func thePhaseIconsRetainDistinctInkAtBothMenuBarScales() throws {
        for scale in [1, 2] {
            var seen = Set<Data>()
            for state in MenuBarIcon.State.allCases {
                let image = MenuBarIcon.image(for: state)
                #expect(image.isTemplate && image.size == NSSize(width: 18, height: 18))
                let side = 18 * scale
                let bitmap = try #require(CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                                                   bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                bitmap.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: bitmap, flipped: false)
                image.draw(in: NSRect(origin: .zero, size: image.size))
                NSGraphicsContext.restoreGraphicsState()
                let pixels = try #require(bitmap.data?.assumingMemoryBound(to: UInt8.self))
                let ink = Data((0..<(side * side)).map { pixels[4 * $0 + 3] >= 128 ? 1 : 0 })
                #expect(ink.contains(1), "\(state.title) @\(scale)x has no visible ink")
                #expect(seen.insert(ink).inserted, "\(state.title) @\(scale)x duplicates another mask")
            }
        }
    }
}

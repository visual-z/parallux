import AppKit
import ParalluxKit

/// Carries out a parallux:// or sing-box:// link (URLRoute).
@MainActor
enum URLRouter {
    static func open(_ url: URL, app: AppModel) {
        guard let route = URLRoute.parse(url) else { return }
        Task {
            do {
                switch route {
                case let .addAggregationServer(link):
                    let server = try app.servers.add(link: link)
                    if app.linkSettings.value.bondServerID == nil {
                        app.linkSettings.value.bondServerID = server.id
                        await app.applyLinkChanges()
                    }
                    inform("已添加聚合服务器", "「\(server.name)」可用于叠加。")
                case let .importRemoteProfile(link):
                    try await app.profiles.importLink(link)
                    inform("已导入订阅", "可在「配置」页选用。")
                case .connect:
                    await app.setOn(true)
                case .disconnect:
                    await app.setOn(false)
                case .toggle:
                    await app.setOn(!app.isOn)
                }
            } catch {
                inform("无法打开链接", error.localizedDescription)
            }
        }
    }

    private static func inform(_ title: String, _ text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        NSApp.activate()
        alert.runModal()
    }
}

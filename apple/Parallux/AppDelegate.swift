import AppKit
import Observation
import ParalluxKit
import SwiftUI

/// Owns the menu bar status item.
///
/// SwiftUI's MenuBarExtra cannot tell a left click from a right click, and the
/// design wants both (left: panel, right: native menu; PLAN decision 7), so the
/// status item is plain AppKit and hosts SwiftUI only inside the popover.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    /// SwiftUI's scene actions, handed over by MainWindow when it appears.
    /// They stay valid after that window closes, so AppKit code (the status
    /// item and its menu) can reopen the main and settings windows.
    var sceneActions: SceneActions?
    let app = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        popover.behavior = .transient
        app.start()
        SystemServices.start(app)
        UpdaterModel.shared.start()
        popover.contentViewController = NSHostingController(rootView: PanelView(
            app: app,
            openMainWindow: { [weak self] in self?.showMainWindow() },
            openSettings: { [weak self] in self?.showSettings() }
        ))

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
            button.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        }
        statusItem = item
        renderStatusItem()
    }

    /// parallux:// and sing-box:// links (URLRoute).
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { URLRouter.open(url, app: app) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !app.settings.value.keepInMenuBarAfterClose
    }

    /// Redraws the icon (and the optional rate) whenever what it shows changes.
    /// The status stream updates at most once per second, which bounds the
    /// rate text's refresh as the design asks.
    private func renderStatusItem() {
        withObservationTracking {
            guard let button = statusItem?.button else { return }
            let state = app.menuBarState
            button.image = MenuBarIcon.image(for: state)
            if app.settings.value.showRateInMenuBar, let status = app.session.status {
                button.title = " " + RateFormat.bitsPerSecond(status.downlink + status.uplink)
            } else {
                button.title = ""
            }
            button.toolTip = app.statusLine
        } onChange: { [weak self] in
            Task { @MainActor in self?.renderStatusItem() }
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let wantsMenu = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if wantsMenu {
            showMenu()
        } else if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: right-click menu (design v0.2: everything the panel does, by keyboard)

    private func showMenu() {
        let menu = NSMenu()
        let session = app.session
        menu.addItem(ActionItem(app.isOn ? "关闭 Parallux" : "开启 Parallux") { [app] in
            Task { await app.setOn(!app.isOn) }
        })
        menu.addItem(.separator())

        let aggregation = NSMenu()
        let canAggregate = app.enabledLinks.count >= 2
        for mode in AggregationMode.allCases {
            let item = ActionItem(mode.title) { [app] in Task { await app.setMode(mode) } }
            item.state = mode == app.linkSettings.value.mode ? .on : .off
            item.isEnabled = canAggregate
            aggregation.addItem(item)
        }
        if !canAggregate {
            aggregation.addItem(.separator())
            aggregation.addItem(disabled("启用两条以上线路后可选"))
        }
        aggregation.addItem(.separator())
        aggregation.addItem(disabled("聚合服务器：\(app.bondServerSummary ?? "未设置")"))
        menu.addItem(submenu("聚合方式", aggregation))

        let links = NSMenu()
        for link in app.links.links {
            let enabled = !app.linkSettings.value.preferences.disabled.contains(link.name)
            let item = ActionItem("\(link.kind.title) · \(link.name)") { [app] in
                if enabled { app.linkSettings.value.preferences.disabled.insert(link.name) } else { app.linkSettings.value.preferences.disabled.remove(link.name) }
                Task { await app.applyLinkChanges() }
            }
            item.state = enabled ? .on : .off
            links.addItem(item)
        }
        if app.links.links.isEmpty { links.addItem(disabled("没有可用的网络")) }
        menu.addItem(submenu("线路", links))

        let modes = NSMenu()
        for mode in session.routeModes {
            let item = ActionItem(RouteMode.title(mode)) { session.setRouteMode(mode) }
            item.state = mode == session.routeMode ? .on : .off
            modes.addItem(item)
        }
        if session.routeModes.isEmpty { modes.addItem(disabled("连接后可选")) }
        menu.addItem(submenu("路由模式", modes))

        let nodes = NSMenu()
        for group in session.groups where group.selectable {
            let items = NSMenu()
            for node in group.items {
                let title = node.delay > 0 ? "\(node.tag)  \(node.delay) ms" : node.tag
                let item = ActionItem(title) { session.select(group: group.tag, outbound: node.tag) }
                item.state = node.tag == group.selected ? .on : .off
                items.addItem(item)
            }
            items.addItem(.separator())
            items.addItem(ActionItem("测速") { session.urlTest(group: group.tag) })
            nodes.addItem(submenu("\(group.tag)：\(group.selected)", items))
        }
        if nodes.items.isEmpty { nodes.addItem(disabled("连接后可选")) }
        menu.addItem(submenu("节点", nodes))

        let profiles = NSMenu()
        for profile in app.profiles.store.profiles {
            let item = ActionItem(profile.name) { [app] in Task { await app.select(profile: profile.id) } }
            item.state = profile.id == app.profiles.store.selectedID ? .on : .off
            profiles.addItem(item)
        }
        if profiles.items.isEmpty { profiles.addItem(disabled("还没有配置")) }
        menu.addItem(submenu("配置", profiles))

        menu.addItem(.separator())
        if UpdaterModel.shared.isConfigured { menu.addItem(ActionItem("检查更新…") { UpdaterModel.shared.checkForUpdates() }) }
        menu.addItem(ActionItem("打开主窗口", key: "o") { [weak self] in self?.showMainWindow() })
        menu.addItem(ActionItem("设置…", key: ",") { [weak self] in self?.showSettings() })
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 Parallux", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil // so the next left click opens the panel again
    }

    private func submenu(_ title: String, _ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    func showMainWindow() {
        popover.performClose(nil)
        NSApp.activate()
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == MainWindow.id }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            sceneActions?.openWindow(id: MainWindow.id)
        }
    }

    /// A settings window opened from a menu bar item stays behind other apps
    /// unless the app is activated first (steipete.me/posts/2025/showing-
    /// settings-from-macos-menu-bar-items); SettingsLink inside a popover
    /// does not do that, so both entry points come through here.
    func showSettings() {
        popover.performClose(nil)
        NSApp.activate()
        sceneActions?.openSettings()
    }
}

/// An NSMenuItem that runs a closure.
@MainActor
private final class ActionItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(_ title: String, key: String = "", handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: key)
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func run() { handler() }
}

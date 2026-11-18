import AppKit
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: PanelView(
            openMainWindow: { [weak self] in self?.showMainWindow() },
            openSettings: { [weak self] in self?.showSettings() }
        ))

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            // Template image: the system tints it for light, dark and tinted
            // menu bars. Placeholder until the custom 18 pt glyph exists.
            let image = NSImage(systemSymbolName: "point.3.connected.trianglepath.dotted", accessibilityDescription: "Parallux")
            image?.isTemplate = true
            button.image = image
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false // Parallux keeps running in the menu bar.
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let wantsMenu = event?.type == .rightMouseUp || event?.modifierFlags.contains(.option) == true
        if wantsMenu {
            showMenu()
        } else if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "打开主窗口", action: #selector(menuOpenMainWindow), keyEquivalent: "o").target = self
        menu.addItem(withTitle: "设置…", action: #selector(menuOpenSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 Parallux", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil // so the next left click opens the panel again
    }

    @objc private func menuOpenMainWindow() { showMainWindow() }
    @objc private func menuOpenSettings() { showSettings() }

    private func showMainWindow() {
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
    private func showSettings() {
        popover.performClose(nil)
        NSApp.activate()
        sceneActions?.openSettings()
    }
}

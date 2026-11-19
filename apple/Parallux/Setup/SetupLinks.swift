import AppKit
import ParalluxKit
import ServiceManagement
import UserNotifications

/// Where each setup step is approved in System Settings.
///
/// The network-extension pane link is community-documented, not an Apple API
/// (feat-setup-approval, 环境假设); it worked on macOS 27.2.1. If it does not
/// open, fall back to Apple's SMAppService.openSystemSettingsLoginItems(),
/// which lands one level up in Login Items & Extensions.
enum SetupLinks {
    static let networkExtensions = URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences?extensionPointIdentifier=com.apple.system_extension.network_extension.extension-point")!
    static let notifications = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!

    @MainActor
    static func open(_ step: SetupStep) {
        switch step {
        case .systemExtension:
            if !NSWorkspace.shared.open(networkExtensions) { SMAppService.openSystemSettingsLoginItems() }
        case .helper:
            SMAppService.openSystemSettingsLoginItems()
        case .notifications:
            NSWorkspace.shared.open(notifications)
        case .vpnConfiguration:
            break // a system prompt, not a Settings pane
        }
    }
}

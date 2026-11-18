import ParalluxKit
import SwiftUI

@main
struct ParalluxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Parallux", id: MainWindow.id) {
            MainWindow { appDelegate.sceneActions = $0 }
                .environment(appDelegate.profiles)
                .environment(appDelegate.tunnel)
                .environment(appDelegate.tunnel.session)
        }
        .defaultSize(width: 1040, height: 680)

        Settings {
            SettingsView()
        }
    }
}

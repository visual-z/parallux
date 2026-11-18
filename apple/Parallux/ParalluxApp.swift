import ParalluxKit
import SwiftUI

@main
struct ParalluxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Parallux", id: MainWindow.id) {
            MainWindow { appDelegate.sceneActions = $0 }
                .environment(appDelegate.app)
                .environment(appDelegate.app.profiles)
                .environment(appDelegate.app.tunnel)
                .environment(appDelegate.app.session)
        }
        .defaultSize(width: 1040, height: 680)
        .commands {
            CommandGroup(after: .appSettings) {
                Button("打开主窗口") { appDelegate.showMainWindow() }.keyboardShortcut("o")
            }
        }

        Settings {
            SettingsView()
                .environment(appDelegate.app)
        }
    }
}

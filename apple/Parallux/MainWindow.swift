import ParalluxKit
import SwiftUI

/// The main window: a NavigationSplitView with the standard (Liquid Glass)
/// sidebar. Glass is left to the system components; content stays opaque.
struct MainWindow: View {
    static let id = "main"
    /// Receives SwiftUI's scene actions; environment values are only reachable
    /// from a view, and the status item (AppKit) needs them.
    var onSceneActionsAvailable: (SceneActions) -> Void = { _ in }

    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @State private var selection: SidebarItem? = .overview

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(SidebarSection.allCases) { section in
                    if let title = section.title {
                        Section(title) { rows(section) }
                    } else {
                        Section { rows(section) }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            let item = selection ?? .overview
            ContentUnavailableView(item.title, systemImage: item.symbol, description: Text("尚未实现"))
                .navigationTitle(item.title)
        }
        .onAppear { onSceneActionsAvailable(SceneActions(openWindow: openWindow, openSettings: openSettings)) }
    }

    private func rows(_ section: SidebarSection) -> some View {
        ForEach(section.items) { item in
            Label(item.title, systemImage: item.symbol).tag(item)
        }
    }
}

/// SwiftUI scene actions captured for AppKit callers.
struct SceneActions {
    let openWindow: OpenWindowAction
    let openSettings: OpenSettingsAction
}

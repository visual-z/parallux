import ParalluxKit
import SwiftUI

/// The main window: a NavigationSplitView with the standard (Liquid Glass)
/// sidebar. Glass is left to the system components; content stays opaque.
struct MainWindow: View {
    static let id = "main"
    /// Receives SwiftUI's window opener; the environment value is only
    /// reachable from a view, and the status item (AppKit) needs it.
    var onOpenWindowAvailable: (OpenWindowAction) -> Void = { _ in }

    @Environment(\.openWindow) private var openWindow
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
        .onAppear { onOpenWindowAvailable(openWindow) }
    }

    private func rows(_ section: SidebarSection) -> some View {
        ForEach(section.items) { item in
            Label(item.title, systemImage: item.symbol).tag(item)
        }
    }
}

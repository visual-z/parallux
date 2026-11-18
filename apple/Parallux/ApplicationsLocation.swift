import AppKit
import ParalluxKit

/// Offers to move the app into /Applications at launch: macOS will not
/// activate the system extension from anywhere else (ApplicationsLocation).
@MainActor
enum ApplicationsMover {
    static func checkAtLaunch() {
        let bundle = Bundle.main.bundleURL
        let location = ApplicationsLocation.classify(bundlePath: bundle.path,
                                                     home: FileManager.default.homeDirectoryForCurrentUser.path)
        guard location != .ok else { return }
        let alert = NSAlert()
        alert.messageText = "把 Parallux 移到「应用程序」文件夹？"
        alert.informativeText = location == .translocated
            ? "Parallux 正从下载后的隔离位置运行。macOS 只会从「应用程序」文件夹启用网络扩展。"
            : "macOS 只会从「应用程序」文件夹启用 Parallux 的网络扩展。"
        alert.addButton(withTitle: "移到「应用程序」")
        alert.addButton(withTitle: "暂不")
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        move(bundle)
    }

    private static func move(_ bundle: URL) {
        let target = URL(fileURLWithPath: "/Applications").appendingPathComponent(bundle.lastPathComponent)
        do {
            if FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.trashItem(at: target, resultingItemURL: nil)
            }
            try FileManager.default.copyItem(at: bundle, to: target)
        } catch {
            let failure = NSAlert(error: error)
            failure.informativeText = "请手动把 Parallux 拖到「应用程序」文件夹。（\(error.localizedDescription)）"
            failure.runModal()
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: target, configuration: configuration) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }
}

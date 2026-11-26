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
        // Copy from LetsMove (potionfactory/LetsMove zh_CN.lproj), the library
        // most Mac apps use for this prompt.
        alert.messageText = "是否要把程序移动到“应用程序”文件夹中？"
        alert.informativeText = "这样做能让你的“下载”文件夹保持整洁。"
        alert.addButton(withTitle: "移动到“应用程序”文件夹中")
        alert.addButton(withTitle: "不移动")
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
            failure.messageText = "无法移动到“应用程序”文件夹中"
            failure.informativeText = error.localizedDescription
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

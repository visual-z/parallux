import Foundation

/// Everything feat-system-integration starts at launch, behind one call so
/// AppDelegate stays a thin entry point: the shared model for intents and
/// links, the widget snapshot writer, the core notification forwarder, and
/// the /Applications check.
@MainActor
enum SystemServices {
    private static var writer: WidgetSnapshotWriter?
    private static var forwarder: CoreNotificationForwarder?

    static func start(_ app: AppModel) {
        AppModel.shared = app
        writer = WidgetSnapshotWriter(app: app)
        writer?.start()
        forwarder = CoreNotificationForwarder(app: app)
        forwarder?.start()
        ApplicationsMover.checkAtLaunch()
    }
}

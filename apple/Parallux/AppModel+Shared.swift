import Foundation

/// App Intents, URL links and the widget snapshot writer reach the one
/// running AppModel through this. AppDelegate sets it at launch, before
/// any of them can run.
extension AppModel {
    @MainActor static var shared: AppModel?
}

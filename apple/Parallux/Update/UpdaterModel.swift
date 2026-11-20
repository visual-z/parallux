import Foundation
import Observation
import ParalluxKit
import Sparkle

/// Sparkle auto-update (PLAN decision 19). Starts only when this build has an
/// https feed and an EdDSA public key (UpdateFeed.resolve); development builds
/// leave both empty and the settings say so instead of offering dead controls.
///
/// Sparkle replaces only the .app; the system extension is replaced on the
/// next activation request, which SystemExtensionInstaller makes when the
/// version changed.
@MainActor @Observable
final class UpdaterModel: NSObject {
    static let shared = UpdaterModel()

    var channel: UpdateChannel {
        didSet {
            UserDefaults.standard.set(channel.rawValue, forKey: UpdateChannel.defaultsKey)
            // A new feed applies to the next check; reset the schedule so it comes soon.
            controller?.updater.resetUpdateCycle()
        }
    }

    var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    private(set) var canCheckForUpdates = false
    var isConfigured: Bool { controller != nil }
    var lastCheck: Date? { controller?.updater.lastUpdateCheckDate }

    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var observation: NSKeyValueObservation?

    override private init() {
        channel = UserDefaults.standard.string(forKey: UpdateChannel.defaultsKey).flatMap(UpdateChannel.init) ?? .stable
        super.init()
    }

    /// Call once at launch. No-op when the build has no feed.
    func start() {
        guard controller == nil, case .feed = resolve() else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
        self.controller = controller
        canCheckForUpdates = controller.updater.canCheckForUpdates
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] updater, _ in
            let value = updater.canCheckForUpdates
            Task { @MainActor in self?.canCheckForUpdates = value }
        }
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    func resolve() -> UpdateFeed.Resolution {
        let info = Bundle.main
        return UpdateFeed.resolve(
            channel: channel,
            stable: info.object(forInfoDictionaryKey: UpdateFeed.stableKey) as? String,
            beta: info.object(forInfoDictionaryKey: UpdateFeed.betaKey) as? String,
            publicKey: info.object(forInfoDictionaryKey: UpdateFeed.publicKeyKey) as? String
        )
    }
}

extension UpdaterModel: SPUUpdaterDelegate {
    nonisolated func feedURLString(for _: SPUUpdater) -> String? {
        MainActor.assumeIsolated {
            if case let .feed(url) = resolve() { return url.absoluteString }
            return nil
        }
    }
}

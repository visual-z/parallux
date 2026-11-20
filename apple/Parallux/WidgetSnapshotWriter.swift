import Foundation
import Observation
import ParalluxKit
import WidgetKit

/// Publishes the app's state to the widget and the Control Center toggle
/// through the App Group. Writes are
/// throttled by WidgetSnapshotThrottle; reloads only follow state changes,
/// because WidgetKit budgets timeline reloads.
@MainActor
final class WidgetSnapshotWriter {
    private let app: AppModel
    private let defaults: UserDefaults?
    private var throttle = WidgetSnapshotThrottle()
    private var lastWritten: WidgetSnapshot?
    private var heartbeat: Timer?

    init(app: AppModel) {
        self.app = app
        defaults = AppGroup.identifier().flatMap(UserDefaults.init(suiteName:))
    }

    func start() {
        guard defaults != nil else { return } // unsigned build: no App Group
        observe()
        // Keeps the snapshot fresh (WidgetSnapshot.staleAfter) while nothing changes.
        heartbeat = Timer.scheduledTimer(withTimeInterval: WidgetSnapshotThrottle.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.publish() }
        }
        publish()
    }

    private func observe() {
        withObservationTracking {
            _ = snapshot()
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.publish()
                self?.observe()
            }
        }
    }

    private func snapshot() -> WidgetSnapshot {
        let status = app.session.status
        return WidgetSnapshot(
            connected: app.tunnel.isConnected,
            mode: app.effectiveMode?.rawValue,
            linkCount: max(app.activeLinks.count, app.links.links.isEmpty ? 0 : 1),
            rate: (status?.uplink ?? 0) + (status?.downlink ?? 0),
            profileName: app.profiles.store.selected?.name,
            updatedAt: Date()
        )
    }

    private func publish() {
        guard let defaults else { return }
        let current = snapshot()
        guard throttle.shouldWrite(current) else { return }
        let reload = WidgetSnapshotThrottle.isStateChange(from: lastWritten, to: current)
        defaults.set(current.encoded(), forKey: WidgetSnapshot.defaultsKey)
        lastWritten = current
        if reload {
            WidgetCenter.shared.reloadAllTimelines()
            ControlCenter.shared.reloadAllControls()
        }
    }
}

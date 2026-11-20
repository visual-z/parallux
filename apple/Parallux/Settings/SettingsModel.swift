import Foundation
import Network
import Observation
import ParalluxKit
import ServiceManagement

/// The app's settings, persisted on every change (AppSettings in UserDefaults).
@MainActor @Observable
final class SettingsModel {
    var value: AppSettings {
        didSet { if value != oldValue { value.save(to: .standard) } }
    }

    init() {
        value = AppSettings.load(from: .standard)
    }

    /// Login item state lives in ServiceManagement, not in our settings.
    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                loginItemError = error.localizedDescription
            }
        }
    }

    var loginItemError: String?
}

/// The interface macOS currently routes through, until M3 discovers every link.
@MainActor @Observable
final class DefaultLinkMonitor {
    struct Link: Equatable {
        var name: String
        var kind: String
        var symbol: String
    }

    private(set) var link: Link?
    @ObservationIgnored private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            // Skip the tunnel's own utun: the physical link is what we show.
            let physical = path.availableInterfaces.first { $0.type != .other }
            let link = physical.map { Self.describe($0) }
            Task { @MainActor in self?.link = link }
        }
        monitor.start(queue: DispatchQueue(label: "parallux.default-link"))
    }

    nonisolated static func describe(_ interface: NWInterface) -> Link {
        switch interface.type {
        case .wifi: Link(name: interface.name, kind: "Wi‑Fi", symbol: "wifi")
        case .wiredEthernet: Link(name: interface.name, kind: "有线", symbol: "cable.connector")
        case .cellular: Link(name: interface.name, kind: "蜂窝", symbol: "iphone")
        default: Link(name: interface.name, kind: interface.name, symbol: "network")
        }
    }
}

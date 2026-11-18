import Foundation
import Libbox
import Observation

/// Live status of the running core, read over libbox's command client.
struct CoreStatus: Equatable, Sendable {
    var uplink: Int64 = 0
    var downlink: Int64 = 0
    var uplinkTotal: Int64 = 0
    var downlinkTotal: Int64 = 0
    var memory: Int64 = 0
    var connections: Int32 = 0
}

/// Subscribes to StartedService status messages and publishes them on the main actor.
@MainActor @Observable
final class StatusClient {
    private(set) var status: CoreStatus?
    private(set) var lastError: String?
    @ObservationIgnored private var client: LibboxCommandClient?
    @ObservationIgnored private var handler: Handler?

    func connect() {
        disconnect()
        let handler = Handler(owner: self)
        let options = LibboxCommandClientOptions()
        options.addCommand(LibboxCommandStatus)
        // Why 1 s: matches the panel's refresh cadence; the design caps the
        // menu bar rate at one update per second.
        options.statusInterval = Int64(NSEC_PER_SEC)
        guard let client = LibboxNewCommandClient(handler, options) else { return }
        self.handler = handler
        self.client = client
        let box = ClientBox(client: client)
        Task.detached { [weak self] in
            do { try box.client.connect() } catch {
                let message = error.localizedDescription
                await MainActor.run { self?.lastError = message }
            }
        }
    }

    func disconnect() {
        guard let client else { return }
        self.client = nil
        handler = nil
        status = nil
        let box = ClientBox(client: client)
        Task.detached { try? box.client.disconnect() }
    }

    fileprivate func update(_ status: CoreStatus?, error: String? = nil) {
        self.status = status
        lastError = error
    }

    /// gomobile objects are thread-safe Go handles but not marked Sendable.
    private struct ClientBox: @unchecked Sendable { let client: LibboxCommandClient }

    private final class Handler: NSObject, LibboxCommandClientHandlerProtocol, @unchecked Sendable {
        weak var owner: StatusClient?
        init(owner: StatusClient) { self.owner = owner }

        func connected() {}
        func disconnected(_ message: String?) {
            Task { @MainActor [owner] in owner?.update(nil, error: message) }
        }
        func writeStatus(_ message: LibboxStatusMessage?) {
            guard let message else { return }
            let status = CoreStatus(
                uplink: message.uplink, downlink: message.downlink,
                uplinkTotal: message.uplinkTotal, downlinkTotal: message.downlinkTotal,
                memory: message.memory, connections: message.connectionsOut
            )
            Task { @MainActor [owner] in owner?.update(status) }
        }
        func clearLogs() {}
        func initializeClashMode(_: (any LibboxStringIteratorProtocol)?, currentMode _: String?) {}
        func setDefaultLogLevel(_: Int32) {}
        func updateClashMode(_: String?) {}
        func write(_: LibboxConnectionEvents?) {}
        func writeGroups(_: (any LibboxOutboundGroupIteratorProtocol)?) {}
        func writeLogs(_: (any LibboxLogIteratorProtocol)?) {}
        func writeOutbounds(_: (any LibboxOutboundGroupItemIteratorProtocol)?) {}
    }
}

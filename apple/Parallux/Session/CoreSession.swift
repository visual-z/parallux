import Foundation
import Libbox
import Observation
import ParalluxKit

/// Live status of the running core.
struct CoreStatus: Equatable, Sendable {
    var uplink: Int64 = 0
    var downlink: Int64 = 0
    var uplinkTotal: Int64 = 0
    var downlinkTotal: Int64 = 0
    var memory: Int64 = 0
    var connections: Int32 = 0
}

/// Everything the interface reads from the running core, over libbox's
/// command client (StartedService gRPC through the XPC-dialed socket).
///
/// The base stream (status, groups, route mode) runs while the tunnel is
/// connected; connections and logs have their own streams that pages open
/// while visible, so their high event rates cost nothing in the background.
@MainActor @Observable
final class CoreSession {
    /// Why 120: one point per second, a two-minute sparkline.
    static let rateHistoryCapacity = 120
    /// Why 3000: SFM's logMaxLines; a few hundred KB of text at most.
    static let logCapacity = 3000
    /// Why 500: closed connections are kept for the 「已关闭」 filter; past a
    /// few hundred the table is unreadable and memory grows with every request.
    static let closedConnectionCapacity = 500

    private(set) var status: CoreStatus?
    private(set) var rateHistory = RingBuffer<RatePoint>(capacity: rateHistoryCapacity)
    private(set) var groups: [OutboundGroupModel] = []
    private(set) var routeModes: [String] = []
    private(set) var routeMode: String?
    private(set) var connections: [ConnectionRow] = []
    private(set) var logs = RingBuffer<LogEntry>(capacity: logCapacity)
    private(set) var lastError: String?
    private(set) var testing: Set<String> = []
    private(set) var startedAt: Date?
    var logsPaused = false

    @ObservationIgnored private var base: Stream?
    @ObservationIgnored private var connectionStream: Stream?
    @ObservationIgnored private var connectionStore: LibboxConnections?
    @ObservationIgnored private var logStream: Stream?
    @ObservationIgnored private var nextLogID = 0
    @ObservationIgnored private var connectionConsumers = 0
    @ObservationIgnored private var logConsumers = 0

    var isRunning: Bool { base != nil || previewing }

    /// DEBUG only: fills the session with fixture data so the routing page can
    /// be looked at without a running tunnel (`-ParalluxPreview YES`). Never
    /// compiled into release builds.
    @ObservationIgnored private var previewing = false

    #if DEBUG
    func loadPreview() {
        previewing = true
        func g(_ tag: String, _ type: String, _ selected: String, _ items: [(String, String, Int32)]) -> OutboundGroupModel {
            OutboundGroupModel(tag: tag, type: type, selectable: type == "selector", selected: selected,
                               items: items.map { .init(tag: $0.0, type: $0.1, delay: $0.2) })
        }
        groups = [
            g("proxy", "selector", "DE Auto", [("DE Auto", "URLTest", 368), ("US Auto", "URLTest", 439), ("🇨🇳 CN-1", "URLTest", 167),
                ("🇩🇪 DE-1 AnyTLS", "AnyTLS", 368), ("🇩🇪 DE-1 HY2", "Hysteria2", 369), ("🇺🇸 US-1 Reality", "VLESS", 439),
                ("🇺🇸 US-2 AnyTLS", "AnyTLS", 537), ("IPLC · 香港 04 0.5倍率", "AnyTLS", 373), ("IPLC · 狮城 0.5倍率", "AnyTLS", 659),
                ("Ghelper", "Selector", 3908), ("direct", "Direct", 0)]),
            g("DE Auto", "urltest", "🇩🇪 DE-1 AnyTLS", [("🇩🇪 DE-1 AnyTLS", "AnyTLS", 368), ("🇩🇪 DE-1 HY2", "Hysteria2", 369), ("🇩🇪 DE-1 Reality", "VLESS", 473)]),
            g("US Auto", "urltest", "🇺🇸 US-1 Reality", [("🇺🇸 US-1 Reality", "VLESS", 439), ("🇺🇸 US-2 AnyTLS", "AnyTLS", 537), ("🇺🇸 US-1 AnyTLS", "AnyTLS", 688)]),
            g("流媒体", "selector", "IPLC · 香港 02", [("IPLC · 香港 02", "AnyTLS", 565), ("IPLC · 台湾 0.5倍率", "AnyTLS", 407), ("IPLC · 日本 0.5倍率", "AnyTLS", 482), ("IPLC · 美国 0.5倍率", "AnyTLS", 1051)]),
        ]
        routeModes = ["Rule", "Global", "Direct"]
        routeMode = "Rule"
        status = CoreStatus(uplink: 6_000_000, downlink: 70_000_000, uplinkTotal: 3 << 30, downlinkTotal: 38 << 30, memory: 38 << 20, connections: 142)
        func row(_ id: String, _ dest: String, _ rule: String, _ out: String, _ rate: Int64) -> ConnectionRow {
            ConnectionRow(id: id, process: "", destination: dest, rule: rule, outbound: out, downlinkTotal: rate * 30, downlink: rate)
        }
        connections = [
            row("1", "rr1.googlevideo.com:443", "rule_set=geosite-youtube", "流媒体", 22_000_000),
            row("2", "github.com:443", "domain_suffix=[github.com githubusercontent.com]", "proxy", 8_000_000),
            row("3", "steamcdn-a.akamaihd.net:443", "rule_set=geosite-steam@cn", "direct", 30_000_000),
            row("4", "www.baidu.com:443", "rule_set=[geosite-cn geoip-cn]", "direct", 12_000_000),
            row("5", "api.openai.com:443", "rule_set=[geosite-openai geosite-anthropic]", "US Auto", 1_500_000),
            row("6", "example.org:443", "", "proxy", 5_000_000),
            row("7", "192.168.1.20:445", "ip_is_private=true", "direct", 300_000),
        ]
    }

    static let previewProfile = """
    {"outbounds":[{"type":"selector","tag":"proxy","outbounds":["DE Auto","US Auto"]},{"type":"urltest","tag":"DE Auto","outbounds":["DE-1"]},
     {"type":"urltest","tag":"US Auto","outbounds":["US-1"]},{"type":"selector","tag":"流媒体","outbounds":["HK-02"]},{"type":"direct","tag":"direct"}],
     "route":{"rules":[{"action":"sniff"},{"protocol":"dns","action":"hijack-dns"},{"ip_is_private":true,"outbound":"direct"},
      {"rule_set":"geosite-youtube","outbound":"流媒体"},{"rule_set":"geosite-netflix","outbound":"流媒体"},
      {"domain_suffix":["github.com","githubusercontent.com"],"outbound":"proxy"},
      {"rule_set":["geosite-openai","geosite-anthropic"],"outbound":"US Auto"},{"rule_set":"geosite-steam@cn","outbound":"direct"},
      {"rule_set":["geosite-cn","geoip-cn"],"outbound":"direct"}],"final":"proxy"}}
    """
    #endif

    func start() {
        guard base == nil else { return }
        startedAt = Date()
        base = Stream(session: self, commands: [LibboxCommandStatus, LibboxCommandGroup, LibboxCommandClashMode])
        loadDeprecatedNotes()
        if connectionConsumers > 0 { openConnections() }
        if logConsumers > 0 { openLogs() }
    }

    func stop() {
        base?.close()
        base = nil
        connectionStream?.close()
        connectionStream = nil
        logStream?.close()
        logStream = nil
        status = nil
        startedAt = nil
        lastError = nil
        deprecatedNotes = []
        groups = []
        routeModes = []
        routeMode = nil
        connections = []
        connectionStore = nil
        rateHistory.removeAll()
    }

    // MARK: on-demand streams (reference counted by the pages showing them)

    func retainConnections() {
        connectionConsumers += 1
        if connectionConsumers == 1, isRunning { openConnections() }
    }

    func releaseConnections() {
        connectionConsumers = max(0, connectionConsumers - 1)
        if connectionConsumers == 0 {
            connectionStream?.close()
            connectionStream = nil
        }
    }

    func retainLogs() {
        logConsumers += 1
        if logConsumers == 1, isRunning { openLogs() }
    }

    func releaseLogs() {
        logConsumers = max(0, logConsumers - 1)
        if logConsumers == 0 {
            logStream?.close()
            logStream = nil
        }
    }

    private func openConnections() {
        connectionStore = LibboxNewConnections()
        connectionStream = Stream(session: self, commands: [LibboxCommandConnections])
    }

    private func openLogs() {
        logStream = Stream(session: self, commands: [LibboxCommandLog])
    }

    // MARK: actions (one-shot standalone clients, dialed over XPC)

    func select(group: String, outbound: String) {
        perform { try $0.selectOutbound(group, outboundTag: outbound) }
        if let index = groups.firstIndex(where: { $0.tag == group }) { groups[index].selected = outbound }
    }

    func urlTest(group: String) {
        testing.insert(group)
        perform({ try $0.urlTest(group) }, then: { [weak self] in self?.testing.remove(group) })
    }

    func setRouteMode(_ mode: String) {
        routeMode = mode
        perform { try $0.setClashMode(mode) }
    }

    func closeConnection(_ id: String) { perform { try $0.closeConnection(id) } }
    func closeAllConnections() { perform { try $0.closeConnections() } }

    func clearLogs() {
        logs.removeAll()
        perform { try $0.clearLogs() }
    }

    func dismissError() { lastError = nil }

    /// Deprecation notes for the running configuration (SFM #76).
    private(set) var deprecatedNotes: [String] = []

    func loadDeprecatedNotes() {
        Task.detached { [weak self] in
            var notes: [String] = []
            if let client = try? CommandTarget.standalone(), let iterator = try? client.getDeprecatedNotes() {
                while iterator.hasNext(), let note = iterator.next() { notes.append(note.message()) }
            }
            await MainActor.run { self?.deprecatedNotes = notes }
        }
    }

    private func perform(_ action: @escaping @Sendable (LibboxCommandClient) throws -> Void, then done: (@MainActor () -> Void)? = nil) {
        Task.detached { [weak self] in
            var message: String?
            do {
                let client = try CommandTarget.standalone()
                try action(client)
            } catch {
                message = error.localizedDescription
            }
            await MainActor.run {
                if let message { self?.lastError = message }
                done?()
            }
        }
    }

    // MARK: stream callbacks

    fileprivate func receive(status message: CoreStatus) {
        status = message
        rateHistory.append(RatePoint(uplink: message.uplink, downlink: message.downlink))
    }

    fileprivate func receive(groups: [OutboundGroupModel]) { self.groups = groups }

    fileprivate func receive(routeModes: [String], current: String) {
        self.routeModes = routeModes
        routeMode = current
    }

    fileprivate func receive(routeMode: String) { self.routeMode = routeMode }

    fileprivate func receive(connectionEvents: StreamValue<LibboxConnectionEvents>) {
        guard let store = connectionStore else { return }
        store.apply(connectionEvents.value)
        store.filterState(Int32(LibboxConnectionStateAll))
        store.sortByDate()
        var rows: [ConnectionRow] = []
        var closed = 0
        let iterator = store.iterator()
        while let iterator, iterator.hasNext(), let connection = iterator.next() {
            let row = Self.row(connection)
            if row.isClosed {
                closed += 1
                if closed > Self.closedConnectionCapacity { continue }
            }
            rows.append(row)
        }
        connections = rows
    }

    fileprivate func receive(logs entries: [(Int32, String)]) {
        guard !logsPaused else { return }
        for (level, message) in entries {
            nextLogID += 1
            logs.append(LogEntry(id: nextLogID, level: LogLevel(sing: level), message: message))
        }
    }

    fileprivate func receiveClearLogs() { logs.removeAll() }

    fileprivate func receive(connected _: Void) { lastError = nil }

    fileprivate func receive(disconnected message: String?) {
        if let message, !message.isEmpty { lastError = message }
    }

    static func row(_ connection: LibboxConnection) -> ConnectionRow {
        var chain: [String] = []
        let iterator = connection.chain()
        while let iterator, iterator.hasNext() { chain.append(iterator.next()) }
        let path = connection.processInfo?.processPath ?? ""
        return ConnectionRow(
            id: connection.id_,
            process: path.isEmpty ? "" : URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent,
            destination: connection.displayDestination(),
            rule: connection.rule,
            outbound: connection.outbound,
            chain: chain,
            network: connection.network,
            uplinkTotal: connection.uplinkTotal,
            downlinkTotal: connection.downlinkTotal,
            createdAt: Date(timeIntervalSince1970: TimeInterval(connection.createdAt) / 1000),
            isClosed: connection.closedAt > 0,
            uplink: connection.uplink,
            downlink: connection.downlink,
            outboundType: connection.outboundType
        )
    }

    // MARK: one command-client connection

    /// gomobile objects are thread-safe Go handles but not marked Sendable.
    struct StreamValue<T>: @unchecked Sendable { let value: T }

    private final class Stream {
        private let client: LibboxCommandClient?
        private let handler: Handler

        init(session: CoreSession, commands: [Int32]) {
            handler = Handler(session: session)
            let options = LibboxCommandClientOptions()
            for command in commands { options.addCommand(command) }
            // Why 1 s: the design refreshes rates at most once per second.
            options.statusInterval = Int64(NSEC_PER_SEC)
            client = CommandTarget.client(handler, options)
            let box = StreamValue(value: client)
            let handler = self.handler
            Task.detached {
                do {
                    try box.value?.connect()
                } catch {
                    // A rejected XPC dial or a dead extension must be visible,
                    // not an empty page under "connected".
                    handler.disconnected(error.localizedDescription)
                }
            }
        }

        func close() {
            let box = StreamValue(value: client)
            Task.detached { try? box.value?.disconnect() }
        }
    }

    private final class Handler: NSObject, LibboxCommandClientHandlerProtocol, @unchecked Sendable {
        weak var session: CoreSession?
        init(session: CoreSession) { self.session = session }

        private func main(_ body: @escaping @MainActor (CoreSession) -> Void) {
            Task { @MainActor [weak session] in
                if let session { body(session) }
            }
        }

        func connected() { main { $0.receive(connected: ()) } }
        func disconnected(_ message: String?) { main { $0.receive(disconnected: message) } }

        func writeStatus(_ message: LibboxStatusMessage?) {
            guard let message else { return }
            let status = CoreStatus(uplink: message.uplink, downlink: message.downlink, uplinkTotal: message.uplinkTotal,
                                    downlinkTotal: message.downlinkTotal, memory: message.memory, connections: message.connectionsOut)
            main { $0.receive(status: status) }
        }

        func writeGroups(_ message: (any LibboxOutboundGroupIteratorProtocol)?) {
            var groups: [OutboundGroupModel] = []
            while let message, message.hasNext(), let group = message.next() {
                var items: [OutboundGroupModel.Item] = []
                let iterator = group.getItems()
                while let iterator, iterator.hasNext(), let item = iterator.next() {
                    items.append(.init(tag: item.tag, type: item.type, delay: item.urlTestDelay))
                }
                groups.append(.init(tag: group.tag, type: group.type, selectable: group.selectable, selected: group.selected, items: items))
            }
            main { $0.receive(groups: groups) }
        }

        func initializeClashMode(_ modeList: (any LibboxStringIteratorProtocol)?, currentMode: String?) {
            var modes: [String] = []
            while let modeList, modeList.hasNext() { modes.append(modeList.next()) }
            let current = currentMode ?? ""
            main { $0.receive(routeModes: modes, current: current) }
        }

        func updateClashMode(_ newMode: String?) {
            let mode = newMode ?? ""
            main { $0.receive(routeMode: mode) }
        }

        func write(_ events: LibboxConnectionEvents?) {
            guard let events else { return }
            let box = StreamValue(value: events)
            main { $0.receive(connectionEvents: box) }
        }

        func writeLogs(_ messageList: (any LibboxLogIteratorProtocol)?) {
            var entries: [(Int32, String)] = []
            while let messageList, messageList.hasNext(), let entry = messageList.next() {
                entries.append((entry.level, entry.message))
            }
            main { $0.receive(logs: entries) }
        }

        func clearLogs() { main { $0.receiveClearLogs() } }
        func setDefaultLogLevel(_: Int32) {}
        func writeOutbounds(_: (any LibboxOutboundGroupItemIteratorProtocol)?) {}
    }
}

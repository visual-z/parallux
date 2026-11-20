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
    /// The last one-shot action that failed (CoreAction.failure), for a moment.
    private(set) var actionError: String?
    @ObservationIgnored private var actionSerial = 0
    /// Why 6 s: time to read a short sentence in the subtitle; longer and it
    /// reads as a state the app is in. Assumed.
    static let actionErrorSeconds = 6.0
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

    private static let baseCommands: [Int32] = [LibboxCommandStatus, LibboxCommandGroup, LibboxCommandClashMode]
    /// Reconnect attempts per stream since it last connected.
    private var retries: [StreamKind: Int] = [:]

    func start() {
        guard base == nil else { return }
        retries = [:]
        startedAt = Date()
        base = Stream(session: self, commands: Self.baseCommands, kind: .base)
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
        retries = [:]
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
        // A fresh store: after a reload the core numbers connections anew.
        connectionStream = Stream(session: self, commands: [LibboxCommandConnections], kind: .connections)
    }

    private func openLogs() {
        logStream = Stream(session: self, commands: [LibboxCommandLog], kind: .logs)
    }

    // MARK: actions (one-shot standalone clients, dialed over XPC)

    func select(group: String, outbound: String) {
        perform(.selectOutbound) { try $0.selectOutbound(group, outboundTag: outbound) }
        if let index = groups.firstIndex(where: { $0.tag == group }) { groups[index].selected = outbound }
    }

    func urlTest(group: String) { urlTest(groups: [group]) }

    /// Tests several groups over one client, one after another. One client
    /// per group, all at once, was what a "test everything" button did: with
    /// 19 groups, 19 concurrent probes of the command server, some of which
    /// timed out.
    func urlTest(groups tags: [String]) {
        let pending = tags.filter { !testing.contains($0) }
        guard !pending.isEmpty else { return }
        testing.formUnion(pending)
        perform(.urlTest, { client in
            // A group that fails does not stop the others; the first failure is reported.
            var failure: Error?
            for tag in pending {
                do { try client.urlTest(tag) } catch { failure = failure ?? error }
            }
            if let failure { throw failure }
        }, then: { [weak self] in self?.testing.subtract(pending) })
    }

    func setRouteMode(_ mode: String) {
        routeMode = mode
        perform(.setRouteMode) { try $0.setClashMode(mode) }
    }

    func closeConnection(_ id: String) { perform(.closeConnection) { try $0.closeConnection(id) } }
    func closeAllConnections() { perform(.closeConnection) { try $0.closeConnections() } }

    func clearLogs() {
        logs.removeAll()
        perform(.clearLogs) { try $0.clearLogs() }
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

    private func perform(_ kind: CoreAction, _ action: @escaping @Sendable (LibboxCommandClient) throws -> Void, then done: (@MainActor () -> Void)? = nil) {
        Task.detached { [weak self] in
            var failed = false
            do {
                let client = try CommandTarget.standalone()
                try action(client)
            } catch {
                failed = true
            }
            await MainActor.run {
                self?.finished(kind, failed: failed)
                done?()
            }
        }
    }

    /// A failed action is its own thing, not a core that cannot be read
    /// (`lastError` is for the streams): it says what failed, and goes away
    /// by itself or with the next action that works.
    private func finished(_ kind: CoreAction, failed: Bool) {
        actionSerial += 1
        guard failed else { return actionError = nil }
        actionError = kind.failure
        let serial = actionSerial
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.actionErrorSeconds))
            if self?.actionSerial == serial { self?.actionError = nil }
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

    fileprivate func receive(connected kind: StreamKind) {
        retries[kind] = 0
        if retries.values.allSatisfy({ $0 == 0 }) { lastError = nil }
    }

    /// Reconnects a stream the core closed, a bounded number of times
    /// (StreamRetry); only then is the error shown.
    fileprivate func receive(lost kind: StreamKind, message: String?) {
        guard isRunning else { return }
        let attempt = retries[kind] ?? 0
        guard let delay = StreamRetry.delay(after: attempt) else {
            if let message, !message.isEmpty { lastError = message }
            return
        }
        retries[kind] = attempt + 1
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, self.isRunning else { return }
            self.reopen(kind)
        }
    }

    private func reopen(_ kind: StreamKind) {
        switch kind {
        case .base:
            base?.close()
            base = Stream(session: self, commands: Self.baseCommands, kind: .base)
        case .connections:
            guard connectionConsumers > 0 else { return }
            connectionStream?.close()
            openConnections()
        case .logs:
            guard logConsumers > 0 else { return }
            logStream?.close()
            openLogs()
        }
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

    /// One command-client subscription. A core reload closes it from the
    /// other side; `onLost` lets the session reconnect.
    private final class Stream {
        private let client: LibboxCommandClient?
        private let handler: Handler

        init(session: CoreSession, commands: [Int32], kind: StreamKind) {
            handler = Handler(session: session, kind: kind)
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
            handler.closed = true
            let box = StreamValue(value: client)
            Task.detached { try? box.value?.disconnect() }
        }
    }

    enum StreamKind { case base, connections, logs }

    private final class Handler: NSObject, LibboxCommandClientHandlerProtocol, @unchecked Sendable {
        weak var session: CoreSession?
        let kind: StreamKind
        /// Set when the app closed the stream itself; its disconnect is not a loss.
        nonisolated(unsafe) var closed = false
        init(session: CoreSession, kind: StreamKind) {
            self.session = session
            self.kind = kind
        }

        private func main(_ body: @escaping @MainActor (CoreSession) -> Void) {
            Task { @MainActor [weak session] in
                if let session { body(session) }
            }
        }

        func connected() {
            let kind = kind
            main { $0.receive(connected: kind) }
        }

        func disconnected(_ message: String?) {
            guard !closed else { return }
            let kind = kind
            main { $0.receive(lost: kind, message: message) }
        }

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

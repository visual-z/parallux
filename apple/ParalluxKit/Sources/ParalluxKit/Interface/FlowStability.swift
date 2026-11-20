import Foundation

/// Keeps a diagram's nodes in place while traffic comes and goes
/// (docs/tasks/fix-flow-stability.md, INV-10).
///
/// The overview and the route map used to rebuild their nodes from the
/// instantaneous rates every second: whoever had traffic right now, sorted by
/// rate. Recorded on a real connection the set of exits changed on 85 of 119
/// steps. Here a node takes the next free place when it first carries
/// traffic, keeps that place while it does, and gives it up only after it has
/// been idle for `retention`. Rates are smoothed, so widths drift instead of
/// jumping. It does not know what a node is: exits, links and traffic classes
/// all use it.
public struct FlowSlots: Equatable, Sendable {
    public struct Slot: Equatable, Sendable, Identifiable {
        public var id: String
        /// Smoothed bytes per second: what the widths are drawn from. Zero
        /// once the node has been silent for `fade`.
        public var rate: Double
        /// The latest sample as it came in: what the labels print.
        public var current: Double
        /// The merged remainder (其他); always last.
        public var isOther: Bool
    }

    /// Seconds a silent node keeps its place. Why 15: page loads pause a few
    /// seconds between bursts (feat-link-view saw 1–3 s); a node that is back
    /// within that should not have left. Assumed, then measured against the
    /// recording in FlowRecording (119 steps, 85 membership changes as the
    /// app drew it), with 4 seats: 0 s leaves 83 changes, 5 s 31, and 10, 15
    /// and 30 s all 21 (what remains is newcomers taking idle seats). With
    /// 15 s and 5 seats: 9; 6 seats: 12; 7 seats: 13.
    public static let retention: TimeInterval = 15
    /// Time constant of the smoothing, seconds. Why 2: samples arrive once a
    /// second and a single one is mostly noise (one connection opening);
    /// two seconds follows a download starting within a few samples without
    /// redrawing the picture for a one-second spike. Assumed.
    public static let smoothing: TimeInterval = 2
    /// Seconds of silence after which a node's band is gone (three time
    /// constants: under 5% of what it was).
    public static let fade: TimeInterval = 3 * smoothing
    /// How many times a seated node's rate a newcomer needs to take its place
    /// when every seat is in use. Why 2: without a margin two similar flows
    /// would trade the last seat every second.
    public static let displacement = 2.0
    public static let otherID = "\u{0}other"

    /// Named nodes shown at once; the rest is merged into 其他.
    public var limit: Int
    private var retention: TimeInterval
    private var seated: [Seat] = []
    private var other: Seat?
    private var updatedAt: TimeInterval?

    private struct Seat: Equatable, Sendable {
        var id: String
        var rate: Double
        var current: Double
        var lastSeen: TimeInterval
    }

    public init(limit: Int, retention: TimeInterval = FlowSlots.retention) {
        self.limit = max(limit, 0)
        self.retention = retention
    }

    /// The nodes to draw, in their places.
    public var slots: [Slot] {
        seated.map { Slot(id: $0.id, rate: $0.rate, current: $0.current, isOther: false) }
            + (other.map { [Slot(id: Self.otherID, rate: $0.rate, current: $0.current, isOther: true)] } ?? [])
    }

    /// One sample: every node that carries traffic now, with its rate.
    /// `time` in seconds on any clock; a clock that steps back expires
    /// nothing early and smooths nothing.
    public mutating func update(_ rates: [(id: String, rate: Double)], at time: TimeInterval) {
        // Sum duplicates; anything that is not a positive finite rate is silence.
        var order: [String] = []
        var input: [String: Double] = [:]
        for item in rates where item.rate.isFinite && item.rate > 0 {
            if input[item.id] == nil { order.append(item.id) }
            input[item.id, default: 0] += item.rate
        }
        let dt = max(0, time - (updatedAt ?? time))
        updatedAt = time
        let alpha = 1 - exp(-dt / Self.smoothing)
        func advance(_ seat: inout Seat, to sample: Double) {
            seat.current = sample
            seat.rate += (sample - seat.rate) * alpha
            if sample > 0 { seat.lastSeen = time }
            if time - seat.lastSeen > Self.fade { seat.rate = 0 }
        }
        for index in seated.indices { advance(&seated[index], to: input[seated[index].id] ?? 0) }
        seated.removeAll { time - $0.lastSeen > retention }

        // Newcomers, the busiest first, take free seats, then the seats of
        // idle nodes (longest idle first), then a seat from a much smaller
        // flow; whoever is left over goes to 其他.
        var winners: Set<String> = []
        var overflow = 0.0
        let known = Set(seated.map(\.id))
        for id in order.filter({ !known.contains($0) }).sorted(by: { input[$0]! != input[$1]! ? input[$0]! > input[$1]! : $0 < $1 }) {
            let rate = input[id]!
            if seated.count + winners.count < limit {
                winners.insert(id)
            } else if let idle = seated.indices.filter({ input[seated[$0].id] == nil })
                .min(by: { (seated[$0].lastSeen, seated[$0].rate) < (seated[$1].lastSeen, seated[$1].rate) }) {
                seated.remove(at: idle)
                winners.insert(id)
            } else if let smallest = seated.indices.min(by: { seated[$0].rate < seated[$1].rate }), rate > Self.displacement * seated[smallest].rate {
                overflow += seated[smallest].current
                seated.remove(at: smallest)
                winners.insert(id)
            } else {
                overflow += rate
            }
        }
        // In the order they came in: a new node goes behind the ones already there.
        for id in order where winners.contains(id) {
            seated.append(Seat(id: id, rate: input[id]!, current: input[id]!, lastSeen: time))
        }

        if var seat = other {
            advance(&seat, to: overflow)
            other = time - seat.lastSeen > retention ? nil : seat
        } else if overflow > 0 {
            other = Seat(id: Self.otherID, rate: overflow, current: overflow, lastSeen: time)
        }
    }
}

/// The route map's rows in a steady order (docs/tasks/fix-flow-stability.md):
/// the profile's own order, the rules that carry traffic above the ones that
/// do not, and a rule changes section only after `FlowSlots.retention`.
public struct RouteRows: Equatable, Sendable {
    /// Rules that carried traffic within the retention, in profile order.
    public private(set) var active: [String] = []
    /// The rest, in profile order.
    public private(set) var idle: [String] = []
    private var lastActive: [String: TimeInterval] = [:]

    public init() {}

    /// - Parameters:
    ///   - order: every row's id in the profile's order (route.final last).
    ///   - rates: bytes per second per id; missing or zero means silent.
    public mutating func update(order: [String], rates: [String: Double], at time: TimeInterval) {
        let known = Set(order)
        lastActive = lastActive.filter { known.contains($0.key) }
        for id in order where (rates[id] ?? 0) > 0 { lastActive[id] = time }
        active = order.filter { id in lastActive[id].map { time - $0 <= FlowSlots.retention } ?? false }
        let shown = Set(active)
        idle = order.filter { !shown.contains($0) }
    }
}

/// The overview's three columns from the live connections: rules and nodes,
/// and the flow between them (docs/tasks/fix-overview-layout-and-flow.md).
public enum FlowColumns {
    public struct Flow: Equatable, Sendable {
        public var rule: String
        public var node: String
        public var rate: Double
    }

    public struct Result: Equatable, Sendable {
        /// Busiest first; 其他 last when anything was merged.
        public var rules: [(name: String, rate: Double)]
        public var nodes: [(name: String, rate: Double)]
        public var flows: [Flow]
        public static func == (a: Result, b: Result) -> Bool {
            a.rules.map(\.name) == b.rules.map(\.name) && a.rules.map(\.rate) == b.rules.map(\.rate)
                && a.nodes.map(\.name) == b.nodes.map(\.name) && a.nodes.map(\.rate) == b.nodes.map(\.rate) && a.flows == b.flows
        }
    }

    /// - Parameters:
    ///   - ruleName: the name for a connection's `rule` field ("" is route.final).
    ///   - maxRules, maxNodes: named entries per column; the rest is merged into 其他.
    public static func make(_ connections: [ConnectionRow], ruleName: (String) -> String, maxRules: Int, maxNodes: Int) -> Result {
        // One pass: rate per (rule, node). The node is where the connection
        // left (Connection.outbound, the end of its chain); every kind of
        // direct outbound is 直连, as in FlowSummary.
        var pairs: [String: [String: Double]] = [:]
        var ruleOrder: [String] = [], nodeOrder: [String] = []
        for connection in connections {
            let rate = Double(max(0, connection.uplink) &+ max(0, connection.downlink))
            guard rate > 0 else { continue }
            let rule = ruleName(connection.rule)
            let node = FlowSummary.directTypes.contains(connection.outboundType) ? FlowSummary.directName : connection.outbound
            if pairs[rule] == nil { ruleOrder.append(rule) }
            if !nodeOrder.contains(node) { nodeOrder.append(node) }
            pairs[rule, default: [:]][node, default: 0] += rate
        }
        func totals(_ names: [String], _ rate: (String) -> Double) -> [(name: String, rate: Double)] {
            names.map { (name: $0, rate: rate($0)) }.sorted { $0.rate != $1.rate ? $0.rate > $1.rate : $0.name < $1.name }
        }
        let ruleTotals = totals(ruleOrder) { pairs[$0]!.values.reduce(0, +) }
        let nodeTotals = totals(nodeOrder) { node in pairs.values.map { $0[node] ?? 0 }.reduce(0, +) }
        func cut(_ list: [(name: String, rate: Double)], _ limit: Int) -> (kept: [(name: String, rate: Double)], names: Set<String>) {
            guard list.count > limit else { return (list, Set(list.map(\.name))) }
            let kept = Array(list.prefix(max(limit, 0)))
            let rest = list.dropFirst(max(limit, 0)).map(\.rate).reduce(0, +)
            return (kept + [(name: FlowSummary.otherName, rate: rest)], Set(kept.map(\.name)))
        }
        let (rules, keptRules) = cut(ruleTotals, maxRules)
        let (nodes, keptNodes) = cut(nodeTotals, maxNodes)
        // Merged flows add up per (rule, node) after renaming.
        var merged: [String: [String: Double]] = [:]
        for (rule, byNode) in pairs {
            let r = keptRules.contains(rule) ? rule : FlowSummary.otherName
            for (node, rate) in byNode {
                merged[r, default: [:]][keptNodes.contains(node) ? node : FlowSummary.otherName, default: 0] += rate
            }
        }
        var flows: [Flow] = []
        for rule in rules.map(\.name) {
            for node in nodes.map(\.name) {
                if let rate = merged[rule]?[node], rate > 0 { flows.append(Flow(rule: rule, node: node, rate: rate)) }
            }
        }
        return Result(rules: rules, nodes: nodes, flows: flows)
    }
}

/// Which palette colour each shown node gets (fix-overview-layout-and-flow,
/// D8): a node keeps its colour while it is shown, shown nodes never share
/// one (until there are more of them than colours), and a colour a node
/// gives up goes to the next newcomer. By seat, not by hashing the name: a
/// hash would give two rules on screen the same colour.
public struct ColorSeats: Equatable, Sendable {
    private let palette: Int
    private var seats: [String: Int] = [:]

    public init(palette: Int) { self.palette = max(palette, 0) }

    /// `ids`: the nodes shown now, in order; `neutral`: ones that take no colour (其他).
    public mutating func update(_ ids: [String], neutral: Set<String>) {
        guard palette > 0 else { return seats = [:] }
        let shown = ids.filter { !neutral.contains($0) }
        seats = seats.filter { shown.contains($0.key) }
        for id in shown where seats[id] == nil {
            let used = Set(seats.values)
            // The lowest free colour; once all are used, the least used one.
            let free = (0..<palette).first { !used.contains($0) }
            seats[id] = free ?? (0..<palette).min { a, b in seats.values.filter { $0 == a }.count < seats.values.filter { $0 == b }.count }!
        }
    }

    public func color(_ id: String) -> Int? { seats[id] }
}

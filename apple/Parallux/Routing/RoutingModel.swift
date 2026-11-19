import Foundation
import Observation
import ParalluxKit

/// Route overrides (「改走」, decision 20), one set per profile, in UserDefaults.
@MainActor @Observable
final class RouteOverrideStore {
    private(set) var byProfile: [UUID: RouteOverrides] = [:]
    @ObservationIgnored private let key = "parallux.route-overrides"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let stored = try? JSONDecoder().decode([UUID: RouteOverrides].self, from: data) {
            byProfile = stored
        }
    }

    func overrides(for profile: UUID?) -> RouteOverrides {
        profile.flatMap { byProfile[$0] } ?? RouteOverrides()
    }

    func set(_ overrides: RouteOverrides, for profile: UUID) {
        byProfile[profile] = overrides.items.isEmpty ? nil : overrides
        if let data = try? JSONEncoder().encode(byProfile) { UserDefaults.standard.set(data, forKey: key) }
    }
}

/// Everything the routing page shows, derived from the selected profile, the
/// core's groups and the live connections.
@MainActor @Observable
final class RoutingModel {
    enum View: String, CaseIterable, Identifiable {
        case map, groups, explain
        var id: String { rawValue }
        var title: String {
            switch self {
            case .map: "路线图"
            case .groups: "分组"
            case .explain: "试一下"
            }
        }
    }

    private(set) var profile = RouteProfile(rules: [], final: nil)
    private(set) var profileError: String?
    @ObservationIgnored private(set) var profileContent: String?

    func load(_ app: AppModel) async {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "ParalluxPreview") {
            profileContent = CoreSession.previewProfile
            profile = RouteProfile.parse(CoreSession.previewProfile)
            return
        }
        #endif
        guard let selected = app.profiles.store.selected else {
            profile = RouteProfile.parse(SampleProfile.content)
            profileContent = SampleProfile.content
            return
        }
        do {
            let content = try await app.profiles.content(of: selected)
            profileContent = content
            profile = RouteProfile.parse(content)
            profileError = nil
        } catch {
            profileError = error.localizedDescription
        }
    }

    /// All outbound tags of the profile, for 「改走」 targets and chain resolution.
    var outboundTags: [String] {
        guard let content = profileContent,
              let root = (try? JSONSerialization.jsonObject(with: Data(content.utf8))) as? [String: Any] else { return [] }
        return ((root["outbounds"] as? [[String: Any]]) ?? []).compactMap { $0["tag"] as? String }
    }

    /// Outbounds a rule may be rerouted to: groups first, then direct and block.
    func rerouteTargets(groups: [OutboundGroupModel]) -> [String] {
        let groupTags = groups.map(\.tag)
        let others = outboundTags.filter { !groupTags.contains($0) && ($0 == "direct" || $0 == "block" || $0.hasPrefix("direct")) }
        return groupTags + others
    }

    /// The route map as it is drawn: every traffic class in the profile's
    /// order, the ones with traffic first, steadied so rows do not jump with
    /// the rates (docs/tasks/fix-flow-stability.md).
    struct SteadyMap: Equatable {
        /// Classes that carried traffic within FlowSlots.retention, then the rest.
        var active: [TrafficClass] = []
        var idle: [TrafficClass] = []
        /// Each class's share of the smoothed traffic, 0...1, by class id.
        var shares: [String: Double] = [:]
        var isEmpty: Bool { active.isEmpty && idle.isEmpty }
    }

    @ObservationIgnored private var rows = RouteRows()
    @ObservationIgnored private var rates = FlowSlots(limit: 1)

    /// `time`: seconds on a clock that does not jump (system uptime).
    func steadyMap(app: AppModel, at time: TimeInterval) -> SteadyMap {
        let overrides = app.routeOverrides.overrides(for: app.profiles.store.selectedID)
        let classes = RouteMap.classes(profile: effectiveProfile(app: app), connections: app.session.connections,
                                       labels: overrides.names(for: profile), overridden: overrides.reroutedIndices(for: profile))
        let byID = Dictionary(uniqueKeysWithValues: classes.map { ($0.id, $0) })
        rows.update(order: classes.map(\.id), rates: Dictionary(uniqueKeysWithValues: classes.map { ($0.id, Double($0.rate)) }), at: time)
        // Every class has a seat: this FlowSlots only smooths.
        rates.limit = max(classes.count, 1)
        rates.update(classes.map { (id: $0.id, rate: Double($0.rate)) }, at: time)
        let total = rates.slots.map(\.rate).reduce(0, +)
        let shares = total > 0 ? Dictionary(uniqueKeysWithValues: rates.slots.map { ($0.id, $0.rate / total) }) : [:]
        return SteadyMap(active: rows.active.compactMap { byID[$0] }, idle: rows.idle.compactMap { byID[$0] }, shares: shares)
    }

    func map(app: AppModel) -> RouteMap {
        let overrides = app.routeOverrides.overrides(for: app.profiles.store.selectedID)
        return RouteMap.build(profile: effectiveProfile(app: app), connections: app.session.connections,
                              labels: overrides.names(for: profile), overridden: overrides.reroutedIndices(for: profile))
    }

    /// The profile with overrides applied, as the core runs it.
    func effectiveProfile(app: AppModel) -> RouteProfile {
        guard let content = profileContent else { return profile }
        let overrides = app.routeOverrides.overrides(for: app.profiles.store.selectedID)
        let result = RouteOverrides.apply(overrides, to: content)
        return result.applied.isEmpty ? profile : RouteProfile.parse(result.config)
    }

    func chain(_ exit: String, app: AppModel) -> ExitChain {
        var tags = Set(outboundTags)
        tags.formUnion(app.session.groups.map(\.tag))
        for group in app.session.groups { tags.formUnion(group.items.map(\.tag)) }
        return ExitChain.flatten(exit, groups: app.session.groups, outbounds: tags)
    }
}

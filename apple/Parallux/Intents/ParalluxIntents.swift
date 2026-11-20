import AppIntents
import Foundation
import ParalluxKit

/// Shortcuts actions (SFM parity #108). They run in the app process and act
/// on the running AppModel; the system launches the app in the background
/// when needed (App Intents in the app target, Apple "App Intents" docs).
@MainActor
private func runningApp() throws -> AppModel {
    guard let app = AppModel.shared else { throw IntentFailure(message: "Parallux 尚未启动完成") }
    return app
}

struct IntentFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct ConnectIntent: AppIntent {
    static let title: LocalizedStringResource = "连接 Parallux"
    static let description = IntentDescription("用当前选中的配置连接。")

    @MainActor
    func perform() async throws -> some IntentResult {
        try await runningApp().setOn(true)
        return .result()
    }
}

struct DisconnectIntent: AppIntent {
    static let title: LocalizedStringResource = "断开 Parallux"

    @MainActor
    func perform() async throws -> some IntentResult {
        try await runningApp().setOn(false)
        return .result()
    }
}

struct ToggleIntent: AppIntent {
    static let title: LocalizedStringResource = "切换 Parallux"

    @MainActor
    func perform() async throws -> some IntentResult {
        let app = try runningApp()
        await app.setOn(!app.isOn)
        return .result()
    }
}

enum AggregationModeIntentValue: String, AppEnum {
    case balance, bond, failover

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "聚合方式"
    static let caseDisplayRepresentations: [AggregationModeIntentValue: DisplayRepresentation] = [
        .balance: "分流", .bond: "叠加", .failover: "主备",
    ]

    var mode: AggregationMode { AggregationMode(rawValue: rawValue) ?? .balance }
}

struct SetAggregationModeIntent: AppIntent {
    static let title: LocalizedStringResource = "设置聚合方式"

    @Parameter(title: "聚合方式")
    var mode: AggregationModeIntentValue

    @MainActor
    func perform() async throws -> some IntentResult {
        try await runningApp().setMode(mode.mode)
        return .result()
    }
}

/// A profile as Shortcuts sees it.
struct ProfileEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "配置"
    static let defaultQuery = ProfileQuery()

    let id: UUID
    let name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct ProfileQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [ProfileEntity] {
        try runningApp().profiles.store.profiles.filter { identifiers.contains($0.id) }.map { ProfileEntity(id: $0.id, name: $0.name) }
    }

    @MainActor
    func suggestedEntities() async throws -> [ProfileEntity] {
        try runningApp().profiles.store.profiles.map { ProfileEntity(id: $0.id, name: $0.name) }
    }
}

struct SelectProfileIntent: AppIntent {
    static let title: LocalizedStringResource = "使用配置"

    @Parameter(title: "配置")
    var profile: ProfileEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        try await runningApp().select(profile: profile.id)
        return .result()
    }
}

struct UpdateProfilesIntent: AppIntent {
    static let title: LocalizedStringResource = "更新订阅"
    static let description = IntentDescription("立即更新全部远程订阅。")

    @MainActor
    func perform() async throws -> some IntentResult {
        let profiles = try runningApp().profiles
        for profile in profiles.store.profiles where profile.kind == .remote {
            try await profiles.update(profile)
        }
        return .result()
    }
}

struct ParalluxShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ConnectIntent(), phrases: ["连接 \(.applicationName)", "打开 \(.applicationName)"],
                    shortTitle: "连接", systemImageName: "power")
        AppShortcut(intent: DisconnectIntent(), phrases: ["断开 \(.applicationName)", "关闭 \(.applicationName)"],
                    shortTitle: "断开", systemImageName: "power.circle")
        AppShortcut(intent: ToggleIntent(), phrases: ["切换 \(.applicationName)"],
                    shortTitle: "切换", systemImageName: "arrow.triangle.2.circlepath")
        AppShortcut(intent: SetAggregationModeIntent(), phrases: ["设置 \(.applicationName) 的聚合方式"],
                    shortTitle: "聚合方式", systemImageName: "point.3.connected.trianglepath.dotted")
        AppShortcut(intent: SelectProfileIntent(), phrases: ["\(.applicationName) 使用配置"],
                    shortTitle: "使用配置", systemImageName: "doc.text")
        AppShortcut(intent: UpdateProfilesIntent(), phrases: ["更新 \(.applicationName) 订阅"],
                    shortTitle: "更新订阅", systemImageName: "arrow.clockwise")
    }
}

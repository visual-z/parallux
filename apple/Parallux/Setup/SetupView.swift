import ParalluxKit
import SwiftUI
import UserNotifications

/// What Parallux needs before it can run, each with its next action
/// (feat-setup-approval). Shown on the overview before the first connection
/// and in Settings › Core.
struct SetupSection: View {
    @Environment(AppModel.self) private var app
    @State private var helper = HelperServiceManager()
    @State private var notificationsAllowed: Bool?
    /// What macOS reports for the installed extension; a leftover VPN
    /// configuration says nothing about whether the extension is enabled.
    @State private var installedExtension: String?

    private var inputs: SetupStep.Inputs {
        let helperState: SetupStep.Inputs.HelperState = switch helper.state {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        default: .notRegistered
        }
        let extensionState: ActivationMachine.State = installedExtension != nil ? .activated : app.tunnel.extensionState
        return SetupStep.Inputs(extensionState: extensionState, vpnConfigured: app.tunnel.hasConfiguration, helper: helperState,
                                notificationsAllowed: notificationsAllowed, signed: AppGroup.identifier() != nil)
    }

    var body: some View {
        Section {
            ForEach(SetupStep.allCases) { step in
                SetupRow(step: step, status: SetupStep.status(step, inputs), action: { await act(step) })
            }
        }
        .task { await refresh() }
        .onChange(of: app.tunnel.extensionState) { Task { await refresh() } }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await refresh() }
        }
    }

    private func refresh() async {
        installedExtension = await app.tunnel.installedExtensionVersion()
        await helper.refresh()
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationsAllowed = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }

    private func act(_ step: SetupStep) async {
        switch step {
        case .systemExtension, .vpnConfiguration:
            // install() asks macOS; approval then completes on its own.
            await app.tunnel.install()
            if app.tunnel.phase == .awaitingApproval {
                SetupLinks.open(.systemExtension)
                _ = await app.tunnel.completeApproval()
            }
        case .helper:
            if helper.state == .requiresApproval { SetupLinks.open(.helper) } else { await helper.install() }
        case .notifications:
            let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])) ?? false
            if !granted { SetupLinks.open(.notifications) }
        }
        await refresh()
    }
}

private struct SetupRow: View {
    let step: SetupStep
    let status: SetupStep.Status
    let action: () async -> Void
    @State private var running = false

    var body: some View {
        LabeledContent {
            switch status {
            case .done:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityLabel("已完成")
            case .blocked:
                Text("等待中").foregroundStyle(.secondary)
            case .unavailable:
                Text("不可用").foregroundStyle(.secondary)
            case .needsAction:
                Button(buttonTitle) {
                    running = true
                    Task { await action(); running = false }
                }
                .disabled(running)
            }
        } label: {
            Label(step.title, systemImage: symbol)
        }
    }

    /// SFM: 安装系统扩展 / 安装辅助服务 / 授权.
    private var buttonTitle: String {
        switch step {
        case .systemExtension: "安装系统扩展"
        case .vpnConfiguration: "安装"
        case .helper: "安装辅助服务"
        case .notifications: "授权"
        }
    }

    private var symbol: String {
        switch step {
        case .systemExtension: "puzzlepiece.extension"
        case .vpnConfiguration: "network.badge.shield.half.filled"
        case .helper: "gearshape.2"
        case .notifications: "bell"
        }
    }
}

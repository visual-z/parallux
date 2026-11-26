import Foundation

/// System-extension activation as a pure state machine.
///
/// macOS calls `requestNeedsUserApproval` first and, once the user switches
/// the extension on in System Settings, `didFinishWithResult` on the same
/// request. Treating needs-approval as the end left the app stuck waiting.
public enum ActivationMachine {
    public enum State: Equatable, Sendable {
        case idle
        case requesting
        case awaitingApproval
        case activated
        case needsReboot
        case failed(Int)

        public var isTerminal: Bool {
            switch self {
            case .activated, .needsReboot, .failed: true
            default: false
            }
        }
    }

    public enum Event: Equatable, Sendable {
        case submitted
        case needsApproval
        case finished(needsReboot: Bool)
        case failed(code: Int)
        /// Replacing an identical build was cancelled: it is already installed.
        case cancelledSameVersion
    }

    public static func reduce(_ state: State, _ event: Event) -> State {
        if case .submitted = event { return .requesting }
        // One request ends once; late callbacks of the same request are ignored.
        guard !state.isTerminal else { return state }
        switch event {
        case .submitted: return .requesting
        case .needsApproval: return .awaitingApproval
        case let .finished(needsReboot): return needsReboot ? .needsReboot : .activated
        case let .failed(code): return .failed(code)
        case .cancelledSameVersion: return .activated
        }
    }
}

/// The setup checklist: what Parallux needs before it can run.
public enum SetupStep: String, CaseIterable, Identifiable, Sendable {
    case systemExtension, vpnConfiguration, helper, notifications
    public var id: String { rawValue }

    public enum Status: Equatable, Sendable {
        case done
        case needsAction
        /// Waiting for an earlier step.
        case blocked
        case unavailable
    }

    public struct Inputs: Equatable, Sendable {
        public var extensionState: ActivationMachine.State
        public var vpnConfigured: Bool
        public var helper: HelperState
        public var notificationsAllowed: Bool?
        public var signed: Bool

        public enum HelperState: Equatable, Sendable { case notRegistered, requiresApproval, enabled }

        public init(extensionState: ActivationMachine.State, vpnConfigured: Bool, helper: HelperState, notificationsAllowed: Bool?, signed: Bool) {
            self.extensionState = extensionState
            self.vpnConfigured = vpnConfigured
            self.helper = helper
            self.notificationsAllowed = notificationsAllowed
            self.signed = signed
        }
    }

    public static func status(_ step: SetupStep, _ inputs: Inputs) -> Status {
        switch step {
        case .systemExtension:
            guard inputs.signed else { return .unavailable }
            return inputs.extensionState == .activated ? .done : .needsAction
        case .vpnConfiguration:
            guard inputs.signed else { return .unavailable }
            guard inputs.extensionState == .activated else { return .blocked }
            return inputs.vpnConfigured ? .done : .needsAction
        case .helper:
            guard inputs.signed else { return .unavailable }
            return inputs.helper == .enabled ? .done : .needsAction
        case .notifications:
            return inputs.notificationsAllowed == true ? .done : .needsAction
        }
    }

    /// SFM wording where it has one.
    public var title: String {
        switch self {
        case .systemExtension: "系统扩展"
        case .vpnConfiguration: "VPN 配置"
        case .helper: "辅助服务"
        case .notifications: "通知"
        }
    }
}

/// OSSystemExtensionError codes in the words of SFM and macOS.
public enum SystemExtensionErrorText {
    /// `OSSystemExtensionErrorCode` from SystemExtensions.framework/SystemExtensions.h,
    /// one case per value: the numbers are not contiguous in meaning (3 is the
    /// bundle location, 8 is the signature), so the table must be read from the
    /// header rather than guessed. Wording from SFM's strings where they exist.
    public static func text(code: Int, fallback: String) -> String {
        switch code {
        case 1: "未知错误"
        case 2: "缺少授权"
        case 3: "请将 Parallux 移到「应用程序」文件夹"
        case 4: "未找到系统扩展"
        case 5: "系统扩展缺少标识符"
        case 6: "系统扩展标识符重复"
        case 7: "未知的系统扩展类别"
        case 8: "系统扩展的代码签名无效"
        case 9: "系统扩展没有通过系统校验"
        case 10: "被系统策略禁止"
        case 11: "请求已取消"
        case 12: "请求被更新的请求取代"
        case 13: "需要在系统设置中授权"
        default: fallback
        }
    }
}

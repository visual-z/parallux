import Foundation

/// System-extension activation as a pure state machine (feat-setup-approval).
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

    public static func reduce(_ state: State, _ event: Event) -> State { state }
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

    public static func status(_ step: SetupStep, _ inputs: Inputs) -> Status { .needsAction }
}

/// OSSystemExtensionError codes in the words of SFM and macOS.
public enum SystemExtensionErrorText {
    public static func text(code: Int, fallback: String) -> String { fallback }
}

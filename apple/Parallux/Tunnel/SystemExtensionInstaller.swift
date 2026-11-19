import Foundation
import Observation
import os
import ParalluxKit
import SystemExtensions

/// Activates the packet tunnel system extension (adapted from SFM
/// SystemExtension.swift, GPLv3).
///
/// The request's callbacks drive ActivationMachine. A request keeps listening
/// after `requestNeedsUserApproval`: when the user switches the extension on
/// in System Settings, macOS finishes the same request, and `state` becomes
/// `.activated` without the user having to click anything again
/// (feat-setup-approval).
@MainActor @Observable
final class SystemExtensionInstaller: NSObject, OSSystemExtensionRequestDelegate {
    private(set) var state: ActivationMachine.State = .idle
    /// The last failure's text, for the status line.
    private(set) var lastError: String?
    @ObservationIgnored private let log = Logger(subsystem: "io.github.visual-z.parallux", category: "sysext")

    /// Each callback is matched to the request that produced it by identity,
    /// so a properties request finishing cannot be read as an activation.
    private enum Kind { case activation, deactivation, properties }
    @ObservationIgnored private var requests: [ObjectIdentifier: Kind] = [:]
    @ObservationIgnored private var waiters: [UUID: CheckedContinuation<ActivationMachine.State, Never>] = [:]
    @ObservationIgnored private var deactivation: CheckedContinuation<Void, Error>?
    @ObservationIgnored private var propertiesWaiter: CheckedContinuation<String?, Never>?
    /// Which properties request the pending timeout belongs to.
    @ObservationIgnored private var propertiesToken = UUID()

    /// Why: the user may take a while to find the switch in System Settings;
    /// after this the caller gives up waiting (the request itself stays alive
    /// and still completes `state`), and pressing 启动 again resumes.
    /// Assumed value, not measured.
    static let approvalLimit: Duration = .seconds(15 * 60)
    /// Why: sysextd answers activation and properties requests locally; a
    /// minute without a callback means it is stuck, and callers must not hang.
    /// Assumed value; measure with `log stream --predicate 'subsystem == "com.apple.sx"'`.
    static let requestLimit: Duration = .seconds(60)

    static var extensionBundleID: String { (Bundle.main.bundleIdentifier ?? "") + ".tunnel" }

    /// Submits an activation request and returns at the first state the
    /// caller can act on: activated, needs-reboot, failed, or awaiting
    /// approval. The request stays alive after awaiting approval; observe
    /// `state` (or call `waitForCompletion`) for the rest.
    func activate() async -> ActivationMachine.State {
        apply(.submitted)
        lastError = nil
        submit(.activationRequest(forExtensionWithIdentifier: Self.extensionBundleID, queue: .main), as: .activation)
        return await wait(limit: Self.requestLimit)
    }

    /// Waits until the current request ends (after the user approves).
    func waitForCompletion() async -> ActivationMachine.State {
        if state.isTerminal || state == .idle { return state }
        return await wait(limit: Self.approvalLimit)
    }

    func deactivate() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            deactivation = continuation
            submit(.deactivationRequest(forExtensionWithIdentifier: Self.extensionBundleID, queue: .main), as: .deactivation)
        }
        state = .idle
    }

    /// Installed version as macOS reports it, for the Core settings tab.
    func installedVersion() async -> String? {
        guard propertiesWaiter == nil else { return nil }
        let token = UUID()
        propertiesToken = token
        let result = await withCheckedContinuation { continuation in
            propertiesWaiter = continuation
            submit(.propertiesRequest(forExtensionWithIdentifier: Self.extensionBundleID, queue: .main), as: .properties)
            Task { [weak self] in
                try? await Task.sleep(for: Self.requestLimit)
                guard let self, self.propertiesToken == token else { return }
                self.finishProperties(nil)
            }
        }
        return result
    }

    private func submit(_ request: OSSystemExtensionRequest, as kind: Kind) {
        requests[ObjectIdentifier(request)] = kind
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    /// Suspends until `apply` reaches a state the caller can act on, or the
    /// limit passes (then returns the state as it is).
    private func wait(limit: Duration) async -> ActivationMachine.State {
        let id = UUID()
        return await withCheckedContinuation { continuation in
            waiters[id] = continuation
            Task { [weak self] in
                try? await Task.sleep(for: limit)
                guard let self, let waiter = self.waiters.removeValue(forKey: id) else { return }
                waiter.resume(returning: self.state)
            }
        }
    }

    /// Feeds the machine and wakes callers at states they can act on.
    private func apply(_ event: ActivationMachine.Event) {
        state = ActivationMachine.reduce(state, event)
        guard state.isTerminal || state == .awaitingApproval else { return }
        let ready = waiters.values
        waiters.removeAll()
        for waiter in ready { waiter.resume(returning: state) }
    }

    private func finishProperties(_ version: String?) {
        propertiesWaiter?.resume(returning: version)
        propertiesWaiter = nil
        propertiesToken = UUID()
    }

    /// Ends bookkeeping for a request; returns what kind it was.
    private func take(_ id: ObjectIdentifier, keep: Bool = false) -> Kind? {
        keep ? requests[id] : requests.removeValue(forKey: id)
    }

    // MARK: delegate

    nonisolated func request(_: OSSystemExtensionRequest, actionForReplacingExtension existing: OSSystemExtensionProperties, withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        // Replace unless it is the very same build; a stale extension keeps
        // the old Mach service (Base.xcconfig PARALLUX_TUNNEL_MACH_SERVICE).
        if existing.bundleVersion == ext.bundleVersion, existing.bundleShortVersion == ext.bundleShortVersion, !existing.isAwaitingUserApproval {
            return .cancel
        }
        return .replace
    }

    nonisolated func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        let id = ObjectIdentifier(request)
        Task { @MainActor in
            guard self.take(id, keep: true) == .activation else { return }
            self.apply(.needsApproval)
        }
    }

    nonisolated func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        let id = ObjectIdentifier(request)
        let reboot = result == .willCompleteAfterReboot
        Task { @MainActor in
            switch self.take(id) {
            case .activation: self.apply(.finished(needsReboot: reboot))
            case .deactivation:
                self.deactivation?.resume()
                self.deactivation = nil
            case .properties, nil: break
            }
        }
    }

    nonisolated func request(_ request: OSSystemExtensionRequest, foundProperties properties: [OSSystemExtensionProperties]) {
        let id = ObjectIdentifier(request)
        let enabled = properties.first { $0.isEnabled && !$0.isUninstalling }
        let version = enabled.map { "\($0.bundleShortVersion) (\($0.bundleVersion))" }
        Task { @MainActor in
            guard self.take(id) == .properties else { return }
            self.finishProperties(version)
        }
    }

    nonisolated func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        let id = ObjectIdentifier(request)
        let nsError = error as NSError
        Task { @MainActor in
            switch self.take(id) {
            case .properties: self.finishProperties(nil)
            case .deactivation:
                self.deactivation?.resume(throwing: error)
                self.deactivation = nil
            case .activation:
                // Cancelling the replacement of an identical build is reported as
                // an error but means it is already installed.
                if nsError.code == OSSystemExtensionError.requestCanceled.rawValue {
                    self.apply(.cancelledSameVersion)
                    return
                }
                self.log.error("activation failed: \(nsError.localizedDescription, privacy: .public)")
                self.lastError = SystemExtensionErrorText.text(code: nsError.code, fallback: nsError.localizedDescription)
                self.apply(.failed(code: nsError.code))
            case nil: break
            }
        }
    }
}

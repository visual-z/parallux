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
    @ObservationIgnored private let log = Logger(subsystem: "io.github.visual-z.parallux", category: "sysext")
    @ObservationIgnored private var waiters: [CheckedContinuation<ActivationMachine.State, Never>] = []
    @ObservationIgnored private var deactivation: CheckedContinuation<Void, Error>?
    @ObservationIgnored private var propertiesWaiter: CheckedContinuation<String?, Never>?
    /// The last failure's text, for the status line.
    private(set) var lastError: String?

    static var extensionBundleID: String { (Bundle.main.bundleIdentifier ?? "") + ".tunnel" }

    /// Submits an activation request and returns at the first state the
    /// caller can act on: activated, needs-reboot, failed, or awaiting
    /// approval. The request stays alive after awaiting approval; observe
    /// `state` (or call `waitForCompletion`) for the rest.
    func activate() async -> ActivationMachine.State {
        apply(.submitted)
        lastError = nil
        let request = OSSystemExtensionRequest.activationRequest(forExtensionWithIdentifier: Self.extensionBundleID, queue: .main)
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
        return await withCheckedContinuation { waiters.append($0) }
    }

    /// Waits until the current request ends (after the user approves).
    func waitForCompletion() async -> ActivationMachine.State {
        if state.isTerminal || state == .idle { return state }
        return await withCheckedContinuation { waiters.append($0) }
    }

    func deactivate() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            deactivation = continuation
            let request = OSSystemExtensionRequest.deactivationRequest(forExtensionWithIdentifier: Self.extensionBundleID, queue: .main)
            request.delegate = self
            OSSystemExtensionManager.shared.submitRequest(request)
        }
        state = .idle
    }

    /// Installed version as macOS reports it, for the Core settings tab.
    func installedVersion() async -> String? {
        guard propertiesWaiter == nil else { return nil }
        return await withCheckedContinuation { continuation in
            propertiesWaiter = continuation
            let request = OSSystemExtensionRequest.propertiesRequest(forExtensionWithIdentifier: Self.extensionBundleID, queue: .main)
            request.delegate = self
            OSSystemExtensionManager.shared.submitRequest(request)
        }
    }

    /// Feeds the machine and wakes callers at states they can act on.
    private func apply(_ event: ActivationMachine.Event) {
        state = ActivationMachine.reduce(state, event)
        guard state.isTerminal || state == .awaitingApproval else { return }
        let ready = waiters
        waiters.removeAll()
        for waiter in ready { waiter.resume(returning: state) }
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

    nonisolated func requestNeedsUserApproval(_: OSSystemExtensionRequest) {
        Task { @MainActor in self.apply(.needsApproval) }
    }

    nonisolated func request(_: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        Task { @MainActor in
            if let deactivation = self.deactivation {
                self.deactivation = nil
                deactivation.resume()
                return
            }
            self.apply(.finished(needsReboot: result == .willCompleteAfterReboot))
        }
    }

    nonisolated func request(_: OSSystemExtensionRequest, foundProperties properties: [OSSystemExtensionProperties]) {
        let enabled = properties.first { $0.isEnabled && !$0.isUninstalling }
        let version = enabled.map { "\($0.bundleShortVersion) (\($0.bundleVersion))" }
        Task { @MainActor in
            self.propertiesWaiter?.resume(returning: version)
            self.propertiesWaiter = nil
        }
    }

    nonisolated func request(_: OSSystemExtensionRequest, didFailWithError error: Error) {
        let nsError = error as NSError
        Task { @MainActor in
            if let waiter = self.propertiesWaiter {
                waiter.resume(returning: nil)
                self.propertiesWaiter = nil
                return
            }
            if let deactivation = self.deactivation {
                self.deactivation = nil
                deactivation.resume(throwing: error)
                return
            }
            // Cancelling the replacement of an identical build is reported as
            // an error but means it is already installed.
            if nsError.code == OSSystemExtensionError.requestCanceled.rawValue {
                self.apply(.cancelledSameVersion)
                return
            }
            self.log.error("activation failed: \(nsError.localizedDescription, privacy: .public)")
            self.lastError = SystemExtensionErrorText.text(code: nsError.code, fallback: nsError.localizedDescription)
            self.apply(.failed(code: nsError.code))
        }
    }
}

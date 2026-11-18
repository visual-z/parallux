import Foundation
import os
import SystemExtensions

/// Activates the packet tunnel system extension (adapted from SFM
/// SystemExtension.swift, GPLv3). The delegate callbacks are turned into one
/// async result instead of SFM's blocking semaphore.
@MainActor
final class SystemExtensionInstaller: NSObject, OSSystemExtensionRequestDelegate {
    enum Outcome: Equatable {
        case activated
        /// The user still has to approve it in System Settings.
        case needsApproval
        case willCompleteAfterReboot
    }

    private let log = Logger(subsystem: "io.github.visual-z.parallux", category: "sysext")
    private var continuation: CheckedContinuation<Outcome, Error>?

    static var extensionBundleID: String { (Bundle.main.bundleIdentifier ?? "") + ".tunnel" }

    func activate() async throws -> Outcome {
        precondition(continuation == nil, "one request at a time")
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let request = OSSystemExtensionRequest.activationRequest(forExtensionWithIdentifier: Self.extensionBundleID, queue: .main)
            request.delegate = self
            OSSystemExtensionManager.shared.submitRequest(request)
        }
    }

    private func resume(_ result: Result<Outcome, Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }

    nonisolated func request(_: OSSystemExtensionRequest, actionForReplacingExtension existing: OSSystemExtensionProperties, withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        // Replace unless it is the very same build; a stale extension keeps
        // the old Mach service (Base.xcconfig PARALLUX_TUNNEL_MACH_SERVICE).
        if existing.bundleVersion == ext.bundleVersion, existing.bundleShortVersion == ext.bundleShortVersion, !existing.isAwaitingUserApproval {
            return .cancel
        }
        return .replace
    }

    nonisolated func requestNeedsUserApproval(_: OSSystemExtensionRequest) {
        Task { @MainActor in self.resume(.success(.needsApproval)) }
    }

    nonisolated func request(_: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        Task { @MainActor in
            self.resume(.success(result == .willCompleteAfterReboot ? .willCompleteAfterReboot : .activated))
        }
    }

    nonisolated func request(_: OSSystemExtensionRequest, didFailWithError error: Error) {
        // Cancelling the replacement of an identical build is reported as an
        // error but means it is already installed.
        let code = (error as NSError).code
        Task { @MainActor in
            if code == OSSystemExtensionError.requestCanceled.rawValue {
                self.resume(.success(.activated))
            } else {
                self.log.error("activation failed: \(error.localizedDescription, privacy: .public)")
                self.resume(.failure(error))
            }
        }
    }
}

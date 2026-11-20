import Foundation
import Testing
@testable import ParalluxKit

@Suite struct ActivationMachineTests {
    typealias M = ActivationMachine

    func run(_ events: [M.Event]) -> M.State {
        events.reduce(M.State.idle, M.reduce)
    }

    @Test func activationMachineFinishesAfterApproval() {
        #expect(run([.submitted, .needsApproval]) == .awaitingApproval)
        #expect(run([.submitted, .needsApproval, .finished(needsReboot: false)]) == .activated, "approval in Settings completes on its own")
        #expect(run([.submitted, .finished(needsReboot: false)]) == .activated)
        #expect(run([.submitted, .needsApproval, .failed(code: 4)]) == .failed(4))
        #expect(run([.submitted, .finished(needsReboot: true)]) == .needsReboot)
        #expect(run([.submitted, .cancelledSameVersion]) == .activated)
        // Terminal states ignore late or repeated events from the same request.
        var rng = SplitMix64(seed: 0x5E7)
        let all: [M.Event] = [.needsApproval, .finished(needsReboot: false), .finished(needsReboot: true), .failed(code: 1), .cancelledSameVersion]
        for _ in 0..<300 {
            var state = run([.submitted])
            var terminal: M.State?
            for _ in 0..<6 {
                state = M.reduce(state, all[rng.int(all.count)])
                if let terminal { #expect(state == terminal) }
                if state.isTerminal, terminal == nil { terminal = state }
            }
        }
        // A new submission after a terminal state starts over.
        #expect(M.reduce(.failed(4), .submitted) == .requesting)
        #expect(M.reduce(.activated, .submitted) == .requesting)
    }
}

@Suite struct SetupStepTests {
    typealias I = SetupStep.Inputs

    @Test func setupStepsFollowTheirPrerequisites() {
        let fresh = I(extensionState: .idle, vpnConfigured: false, helper: .notRegistered, notificationsAllowed: nil, signed: true)
        #expect(SetupStep.status(.systemExtension, fresh) == .needsAction)
        #expect(SetupStep.status(.vpnConfiguration, fresh) == .blocked, "needs the extension first")
        #expect(SetupStep.status(.helper, fresh) == .needsAction, "independent of the extension")
        #expect(SetupStep.status(.notifications, fresh) == .needsAction)

        var waiting = fresh
        waiting.extensionState = .awaitingApproval
        #expect(SetupStep.status(.systemExtension, waiting) == .needsAction)

        var ready = fresh
        ready.extensionState = .activated
        #expect(SetupStep.status(.systemExtension, ready) == .done)
        #expect(SetupStep.status(.vpnConfiguration, ready) == .needsAction)
        ready.vpnConfigured = true
        ready.helper = .requiresApproval
        ready.notificationsAllowed = true
        #expect(SetupStep.status(.vpnConfiguration, ready) == .done)
        #expect(SetupStep.status(.helper, ready) == .needsAction)
        #expect(SetupStep.status(.notifications, ready) == .done)
        ready.helper = .enabled
        #expect(SetupStep.allCases.allSatisfy { SetupStep.status($0, ready) == .done })

        let unsigned = I(extensionState: .idle, vpnConfigured: false, helper: .notRegistered, notificationsAllowed: nil, signed: false)
        #expect(SetupStep.status(.systemExtension, unsigned) == .unavailable)
        #expect(SetupStep.status(.helper, unsigned) == .unavailable)
    }

    @Test func systemExtensionErrorsAreReadable() {
        // OSSystemExtensionError codes (SystemExtensions.framework).
        #expect(SystemExtensionErrorText.text(code: 8, fallback: "x") != "x", "unsupported parent bundle location")
        #expect(SystemExtensionErrorText.text(code: 8, fallback: "x").contains("应用程序"))
        #expect(SystemExtensionErrorText.text(code: 9, fallback: "x") != "x", "extension missing identifier / invalid")
        #expect(SystemExtensionErrorText.text(code: 4, fallback: "x") != "x", "extension not found")
        #expect(SystemExtensionErrorText.text(code: 13, fallback: "x") != "x", "authorization required")
        #expect(SystemExtensionErrorText.text(code: 999, fallback: "原文") == "原文")
        for code in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14] {
            let text = SystemExtensionErrorText.text(code: code, fallback: "x")
            #expect(!text.contains("com.apple"), "code \(code) leaks a system identifier")
        }
    }
}

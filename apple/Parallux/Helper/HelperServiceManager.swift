import AppKit
import Foundation
import Observation
import os
import ParalluxKit
import ServiceManagement

/// Installs, removes and talks to the root helper (PLAN decision 12;
/// adapted from SFM Library/Network/HelperServiceManager.swift, GPLv3).
@MainActor @Observable
final class HelperServiceManager {
    enum State: Equatable {
        case notInstalled
        /// Registered, waiting for System Settings › General › Login Items.
        case requiresApproval
        case enabled
        case unsigned
        case failed(String)
    }

    private(set) var state: State = .notInstalled
    private(set) var version: String?
    private(set) var workingDirectory: HelperWorkingDirectory.Info?
    private(set) var crashReports: [CrashReportCatalog.Entry] = []
    private(set) var lastError: String?
    private(set) var busy = false

    @ObservationIgnored private let log = Logger(subsystem: "io.github.visual-z.parallux", category: "helper")

    private var plistName: String? {
        (Bundle.main.object(forInfoDictionaryKey: "ParalluxHelperLabel") as? String).map { $0 + ".plist" }
    }

    private var service: SMAppService? { plistName.map { SMAppService.daemon(plistName: $0) } }
    private var client: HelperXPCClient? { HelperMachService.client() }

    func refresh() async {
        guard let service, client != nil else {
            state = .unsigned
            return
        }
        switch service.status {
        case .enabled: state = .enabled
        case .requiresApproval: state = .requiresApproval
        case .notRegistered, .notFound: state = .notInstalled
        @unknown default: state = .notInstalled
        }
        guard state == .enabled, let client else {
            version = nil
            workingDirectory = nil
            crashReports = []
            return
        }
        let results = await Task.detached {
            (Result { try client.version() }, Result { try client.workingDirectoryInfo() }, Result { try client.listCrashReports() })
        }.value
        version = try? results.0.get()
        workingDirectory = try? results.1.get()
        crashReports = (try? results.2.get()) ?? []
        if case let .failure(error) = results.0 { lastError = "辅助服务没有应答：\(error)" } else { lastError = nil }
    }

    func install() async {
        guard let service else { return }
        await run {
            // Re-registering replaces an older build's job (SFM does the same).
            if service.status == .enabled { try await service.unregister() }
            try service.register()
        }
        if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
    }

    func uninstall() async {
        guard let service else { return }
        await run { try await service.unregister() }
    }

    func openApproval() { SMAppService.openSystemSettingsLoginItems() }

    func destroyWorkingDirectory() async {
        guard let client else { return }
        await run {
            try await Task.detached { try client.destroyWorkingDirectory(token: HelperWorkingDirectory.destroyToken) }.value
        }
    }

    func readCrashReport(_ name: String) async -> CrashReportCatalog.Report? {
        guard let client else { return nil }
        do {
            return try await Task.detached { try client.readCrashReport(name: name) }.value
        } catch {
            lastError = "\(error)"
            return nil
        }
    }

    private func run(_ body: () async throws -> Void) async {
        busy = true
        defer { busy = false }
        do {
            try await body()
            lastError = nil
        } catch {
            log.error("helper: \(error.localizedDescription, privacy: .public)")
            lastError = error.localizedDescription
        }
        await refresh()
    }
}

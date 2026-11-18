import Foundation
import Libbox
import NetworkExtension
import os
import ParalluxKit

/// Runs sing-box (libbox's command server) inside the system extension.
///
/// Order follows SFM's ExtensionProvider: set up libbox, start the command
/// server (so command.sock exists), start listening on the Mach service, then
/// start the service from the configuration in the start options.
final class PacketTunnelProvider: NEPacketTunnelProvider, @unchecked Sendable {
    let log = Logger(subsystem: "io.github.visual-z.parallux.tunnel", category: "tunnel")
    private(set) var commandServer: LibboxCommandServer?
    private(set) var startOptions: TunnelStartOptions?
    private lazy var platform = ExtensionPlatform(tunnel: self)
    private var xpcListener: NSXPCListener?

    /// A system extension runs as root; its home is root's container, which the
    /// app cannot read. Everything libbox writes lives there.
    private var baseURL: URL { FileManager.default.homeDirectoryForCurrentUser }
    private var optionsURL: URL { baseURL.appendingPathComponent("start-options.json") }

    /// libbox's start calls back into openTun, which waits for
    /// setTunnelNetworkSettings' completion; doing that on the provider's
    /// callback thread risks waiting on ourselves, so start runs here.
    private let startQueue = DispatchQueue(label: "parallux.tunnel.start")

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        nonisolated(unsafe) let options = options
        startQueue.async { [self] in
            do {
                try start(options)
                log.info("core \(PxbridgeVersion(), privacy: .public) started")
                completionHandler(nil)
            } catch {
                log.error("start failed: \(String(describing: error), privacy: .public)")
                stopEverything()
                completionHandler(error)
            }
        }
    }

    private func start(_ options: [String: NSObject]?) throws {
        let resolved = try resolveStartOptions(options)
        startOptions = resolved
        try? FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        try resolved.json().write(to: optionsURL, options: .atomic)

        let setup = LibboxSetupOptions()
        setup.basePath = baseURL.path
        setup.workingPath = baseURL.appendingPathComponent("Working").path
        setup.tempPath = baseURL.appendingPathComponent("Temp").path
        // Why 3000: SFM's value; the log ring buffer is bounded by line count.
        setup.logMaxLines = 3000
        setup.crashReportSource = "NetworkExtension"
        setup.appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        setup.appMarketingVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        var error: NSError?
        LibboxSetup(setup, &error)
        if let error { throw ExtensionError("setup libbox: \(error.localizedDescription)") }

        guard let server = LibboxNewCommandServer(platform, platform, &error) else {
            throw ExtensionError("create command server: \(error?.localizedDescription ?? "nil")")
        }
        try server.start()
        commandServer = server

        if let service = MachService.name(in: .main) {
            let delegate = CommandXPCService(
                socketPath: baseURL.appendingPathComponent("command.sock").path,
                appBundleID: Self.appBundleID,
                teamID: AppGroup.identifier(in: .main).map { String($0.prefix(10)) }
            )
            let listener = NSXPCListener(machServiceName: service)
            listener.delegate = delegate
            listener.resume()
            xpcListener = listener
            xpcDelegate = delegate
        } else {
            log.error("no usable Mach service in Info.plist; the app cannot reach the core")
        }

        try server.startOrReloadService(resolved.configContent, options: LibboxOverrideOptions())
    }

    private var xpcDelegate: CommandXPCService?

    /// The app's bundle id is the extension's minus ".tunnel" (project.yml).
    static var appBundleID: String {
        let own = Bundle.main.bundleIdentifier ?? ""
        return own.hasSuffix(".tunnel") ? String(own.dropLast(".tunnel".count)) : own
    }

    /// The system starts an on-demand tunnel without options; reuse the last ones.
    private func resolveStartOptions(_ options: [String: NSObject]?) throws -> TunnelStartOptions {
        if let fresh = try TunnelStartOptions.decode(options) { return fresh }
        guard let data = try? Data(contentsOf: optionsURL) else {
            throw ExtensionError("missing start options and no persisted copy")
        }
        return try TunnelStartOptions.fromJSON(data)
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        log.info("stop requested, reason \(reason.rawValue)")
        stopEverything()
        completionHandler()
    }

    private func stopEverything() {
        try? commandServer?.closeService()
        commandServer?.close()
        commandServer = nil
        xpcListener?.invalidate()
        xpcListener = nil
        xpcDelegate = nil
        platform.reset()
    }

    /// The app sends new start options to reload without dropping the tunnel.
    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        do {
            let options = try TunnelStartOptions.fromJSON(messageData)
            startOptions = options
            try options.json().write(to: optionsURL, options: .atomic)
            try commandServer?.startOrReloadService(options.configContent, options: LibboxOverrideOptions())
            completionHandler?(nil)
        } catch {
            completionHandler?(Data(String(describing: error).utf8))
        }
    }

    override func sleep(completionHandler: @escaping () -> Void) {
        commandServer?.pause()
        completionHandler()
    }

    override func wake() {
        commandServer?.wake()
    }

    func writeMessage(_ message: String) {
        commandServer?.writeMessage(4, message: message)
    }
}

struct ExtensionError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

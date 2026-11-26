import Foundation
import os
import ParalluxKit

/// The root helper's XPC service (PLAN decision 12; adapted from SFM
/// HelperService/RootHelperService.swift and WorkingDirectoryManager.swift,
/// GPLv3). It does only what needs root: process lookup, the extension's
/// working directory and its crash reports. The core stays in the extension.
final class HelperService: NSObject, NSXPCListenerDelegate, HelperXPCProtocol, @unchecked Sendable {
    private let log = Logger(subsystem: "io.github.visual-z.parallux.helper", category: "service")
    private var listener: NSXPCListener?

    /// Info.plist of this tool (embedded with -sectcreate) names the team-
    /// prefixed App Group and the bundle ids of its two clients.
    private let info = Bundle.main.infoDictionary ?? [:]

    private var appBundleID: String { info["ParalluxAppBundleID"] as? String ?? "io.github.visual-z.parallux" }
    private var extensionBundleID: String { appBundleID + ".tunnel" }
    private var teamID: String? {
        guard let group = AppGroup.identifier(in: .main) else { return nil }
        return String(group.prefix(10))
    }

    var workingDirectory: URL {
        HelperWorkingDirectory.extensionHome(extensionBundleID: extensionBundleID).appendingPathComponent("Working", isDirectory: true)
    }

    var crashReports: URL { workingDirectory.appendingPathComponent("crash_reports", isDirectory: true) }

    func start() {
        guard let service = info["ParalluxHelperMachService"] as? String, !service.isEmpty, !service.hasPrefix("$(") else {
            log.fault("no Mach service name in Info.plist; exiting")
            exit(1)
        }
        let listener = NSXPCListener(machServiceName: service)
        listener.delegate = self
        listener.resume()
        self.listener = listener
        log.info("listening on \(service, privacy: .public)")
    }

    func listener(_: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        // Only the app and the system extension of our team may talk to root.
        // Unsigned development builds have no team and accept nobody.
        guard let teamID else {
            log.error("rejecting connection: unsigned helper has no team")
            return false
        }
        let requirement = "(identifier \"\(appBundleID)\" or identifier \"\(extensionBundleID)\") and anchor apple generic and certificate leaf[subject.OU] = \"\(teamID)\""
        connection.setCodeSigningRequirement(requirement)
        connection.exportedInterface = HelperXPC.makeInterface()
        connection.exportedObject = self
        connection.resume()
        return true
    }

    // MARK: HelperXPCProtocol

    func version(reply: @escaping (String) -> Void) {
        let short = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        reply("\(short) (\(build))")
    }

    func findConnectionOwner(proto: Int32, sourceAddress: String, sourcePort: Int32, destinationAddress: String, destinationPort: Int32,
                             reply: @escaping (Data?, NSError?) -> Void) {
        guard let kind = SocketOwnerMatcher.Proto(rawValue: proto),
              let source = SocketOwnerMatcher.Address(sourceAddress), (0...65535).contains(sourcePort) else {
            reply(nil, Self.error(1, "bad query"))
            return
        }
        let destination = SocketOwnerMatcher.Address(destinationAddress).flatMap { address in
            (1...65535).contains(destinationPort) ? SocketOwnerMatcher.Endpoint(address, UInt16(destinationPort)) : nil
        }
        guard let entry = ProcessSockets.findOwner(proto: kind, source: .init(source, UInt16(sourcePort)), destination: destination) else {
            reply(nil, Self.error(2, "connection owner not found"))
            return
        }
        let owner = HelperConnectionOwner(pid: entry.pid, userID: entry.uid,
                                          userName: ProcessSockets.userName(of: entry.uid),
                                          processPath: ProcessSockets.path(of: entry.pid))
        reply(try? JSONEncoder().encode(owner), nil)
    }

    func workingDirectoryInfo(reply: @escaping (Data?, NSError?) -> Void) {
        let path = workingDirectory.path
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
        let info = HelperWorkingDirectory.Info(path: path, exists: exists, sizeBytes: exists ? Self.size(of: workingDirectory) : 0)
        reply(try? JSONEncoder().encode(info), nil)
    }

    func destroyWorkingDirectory(token: String, reply: @escaping (NSError?) -> Void) {
        guard token == HelperWorkingDirectory.destroyToken else {
            reply(Self.error(3, "refused: wrong confirmation token"))
            return
        }
        do {
            let items = (try? FileManager.default.contentsOfDirectory(at: workingDirectory, includingPropertiesForKeys: nil)) ?? []
            for item in items { try FileManager.default.removeItem(at: item) }
            log.info("emptied the working directory (\(items.count) items)")
            reply(nil)
        } catch {
            reply(error as NSError)
        }
    }

    func listCrashReports(reply: @escaping (Data?, NSError?) -> Void) {
        reply(try? JSONEncoder().encode(CrashReportCatalog.list(in: crashReports)), nil)
    }

    func readCrashReport(name: String, reply: @escaping (Data?, NSError?) -> Void) {
        do {
            reply(try JSONEncoder().encode(CrashReportCatalog.read(name, in: crashReports)), nil)
        } catch {
            reply(nil, Self.error(4, "\(error)"))
        }
    }

    // MARK: helpers

    /// Why 100 000: rule sets and caches are a few hundred files; the cap
    /// bounds a walk over a directory someone filled by mistake.
    static let maxFilesSized = 100_000

    static func size(of directory: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) else { return 0 }
        var total: Int64 = 0
        var count = 0
        for case let url as URL in enumerator {
            count += 1
            if count > maxFilesSized { break }
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if values?.isRegularFile == true { total += Int64(values?.fileSize ?? 0) }
        }
        return total
    }

    static func error(_ code: Int, _ message: String) -> NSError {
        NSError(domain: "Parallux.Helper", code: code, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

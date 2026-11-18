import Foundation
import os
import ParalluxKit

/// Serves TunnelXPCProtocol on the extension's Mach service: every request
/// opens a fresh connection to libbox's command.sock and hands the descriptor
/// to the app (PLAN decision 11; adapted from SFM CommandXPC.swift, GPLv3).
final class CommandXPCService: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
    private let log = Logger(subsystem: "io.github.visual-z.parallux.tunnel", category: "xpc")
    private let socketPath: String
    private let requirement: String?

    /// - Parameter teamID: only apps signed by this team may connect; nil
    ///   (unsigned development builds) accepts any client.
    init(socketPath: String, appBundleID: String, teamID: String?) {
        self.socketPath = socketPath
        requirement = teamID.map {
            "identifier \"\(appBundleID)\" and anchor apple generic and certificate leaf[subject.OU] = \"\($0)\""
        }
    }

    func listener(_: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        if let requirement {
            connection.setCodeSigningRequirement(requirement)
        }
        connection.exportedInterface = TunnelXPC.makeInterface()
        connection.exportedObject = Handler(socketPath: socketPath, log: log)
        connection.resume()
        return true
    }

    private final class Handler: NSObject, TunnelXPCProtocol {
        let socketPath: String
        let log: Logger
        init(socketPath: String, log: Logger) {
            self.socketPath = socketPath
            self.log = log
        }

        func connectToCommandServer(reply: @escaping (FileHandle?, NSError?) -> Void) {
            do {
                reply(try UnixSocket.connect(path: socketPath), nil)
            } catch {
                log.error("command socket: \(String(describing: error), privacy: .public)")
                reply(nil, NSError(domain: "Parallux.CommandXPC", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: String(describing: error),
                ]))
            }
        }
    }
}

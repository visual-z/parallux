import Foundation
import Libbox
import ParalluxKit

/// Which core the interface talks to: this Mac's extension (over XPC) or a
/// remote device's command server. Every command client is created here, so
/// local and remote are one code path (adapted from SFM CommandTarget.swift, GPLv3).
enum CommandTarget {
    struct Remote: Sendable, Equatable {
        var server: RemoteServer
        var secret: String
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var current: Remote?

    static var remote: Remote? { lock.withLock { current } }
    static func set(_ remote: Remote?) { lock.withLock { current = remote } }

    private static func options(_ remote: Remote) -> LibboxRemoteConnectionOptions {
        let options = LibboxRemoteConnectionOptions()
        options.url = RemoteServerAddress.connectURL(remote.server.address)
        options.secret = remote.secret
        return options
    }

    /// A streaming client for `handler`.
    static func client(_ handler: any LibboxCommandClientHandlerProtocol, _ options: LibboxCommandClientOptions) -> LibboxCommandClient? {
        guard let remote else { return LibboxNewCommandClient(handler, options) }
        var error: NSError?
        return LibboxNewRemoteCommandClient(handler, options, Self.options(remote), &error)
    }

    /// A client for one-shot calls; the caller disconnects it.
    static func standalone() throws -> LibboxCommandClient {
        guard let remote else {
            guard let client = LibboxNewStandaloneCommandClient() else { throw CocoaError(.featureUnsupported) }
            return client
        }
        var error: NSError?
        guard let client = LibboxNewStandaloneRemoteCommandClient(Self.options(remote), &error), error == nil else {
            throw error ?? CocoaError(.featureUnsupported)
        }
        return client
    }

    /// Reachability: GetStartedAt answers.
    static func probe(_ remote: Remote) -> Bool {
        var error: NSError?
        guard let client = LibboxNewStandaloneRemoteCommandClient(options(remote), &error), error == nil else { return false }
        defer { try? client.disconnect() }
        var startedAt: Int64 = 0
        return (try? client.getStartedAt(&startedAt)) != nil
    }
}

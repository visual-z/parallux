import Foundation

/// What the system extension exports on its Mach service (PLAN decision 11).
///
/// The extension runs as root, so its command.sock sits in root's home and the
/// app cannot open it; instead the extension opens the socket and hands the
/// connected descriptor over XPC (SFM's CommandXPC.swift does the same).
@objc public protocol TunnelXPCProtocol {
    /// Replies with a FileHandle connected to libbox's command server.
    func connectToCommandServer(reply: @escaping (FileHandle?, NSError?) -> Void)
}

public enum TunnelXPC {
    /// How long the app waits for the extension to answer a dial.
    /// Why: libbox calls the dialer synchronously from Go and a missing reply
    /// (extension crashed, listener not resumed) would hang that goroutine
    /// forever. 5 s is assumed: SFM's local probe timeout is a few seconds and
    /// an XPC round trip to a running extension takes milliseconds; measure
    /// with `log stream` on the dial if this ever fires spuriously.
    public static let dialTimeout: TimeInterval = 5

    public enum DialError: Error, Equatable {
        case timedOut
        case noHandle
        case remote(String)
    }

    /// Whitelists FileHandle in the reply; NSXPC refuses classes it was not told about.
    public static func makeInterface() -> NSXPCInterface {
        NSXPCInterface(with: TunnelXPCProtocol.self)
    }

    /// Asks the extension behind `connection` for a command-server socket and
    /// returns a descriptor the caller owns. Never waits longer than `timeout`.
    public static func dialCommandSocket(over connection: NSXPCConnection, timeout: TimeInterval = dialTimeout) throws -> Int32 {
        throw DialError.noHandle
    }
}

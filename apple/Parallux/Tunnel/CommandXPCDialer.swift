import Foundation
import Libbox
import ParalluxKit

/// libbox calls this when its command client connects: ask the extension
/// over XPC for a socket to its command server (PLAN decision 11).
final class CommandXPCDialer: NSObject, LibboxXPCDialerProtocol, @unchecked Sendable {
    static let shared = CommandXPCDialer()

    func dialXPC(_ ret0_: UnsafeMutablePointer<Int32>?) throws {
        guard let service = MachService.name(in: .main) else {
            throw NSError(domain: "Parallux.XPC", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "未签名的构建没有 App Group，无法连接网络扩展",
            ])
        }
        let connection = NSXPCConnection(machServiceName: service)
        defer { connection.invalidate() }
        ret0_?.pointee = try TunnelXPC.dialCommandSocket(over: connection)
    }
}

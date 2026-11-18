import Darwin
import Foundation
import ParalluxKit

/// Reads every process's TCP and UDP sockets through libproc, as root.
///
/// Feeds SocketOwnerMatcher, which holds the matching rules; this file only
/// turns kernel structures into SocketEntry values. libproc instead of
/// libbox's FindConnectionOwner keeps Libbox.xcframework (128 MB) out of the
/// helper (docs/tasks/feat-helper-service.md, 设计).
enum ProcessSockets {
    /// Why 4096: a busy Mac runs ~800 processes; the cap bounds one scan if
    /// the process table explodes. Assumed value.
    static let maxProcesses = 4096
    /// Why 2048: browsers hold a few hundred descriptors; the cap bounds the
    /// per-process buffer. Assumed value.
    static let maxDescriptorsPerProcess = 2048
    /// Why 1 s: matches HelperXPC.ownerLookupTimeout; a scan past it is useless
    /// because the extension already gave up.
    static let scanBudget: TimeInterval = 1

    /// Scans until it finds a match (exact match stops early) or runs out of
    /// processes or time.
    static func findOwner(proto: SocketOwnerMatcher.Proto, source: SocketOwnerMatcher.Endpoint,
                          destination: SocketOwnerMatcher.Endpoint?) -> SocketOwnerMatcher.SocketEntry? {
        let deadline = Date().addingTimeInterval(scanBudget)
        var seen: [SocketOwnerMatcher.SocketEntry] = []
        for pid in allPIDs() {
            if Date() > deadline { break }
            let entries = sockets(of: pid, proto: proto)
            if let hit = SocketOwnerMatcher.match(entries, proto: proto, source: source, destination: destination), hit.kind == .exact {
                return hit.entry
            }
            seen.append(contentsOf: entries.filter { $0.local.port == source.port })
        }
        return SocketOwnerMatcher.match(seen, proto: proto, source: source, destination: destination)?.entry
    }

    static func allPIDs() -> [pid_t] {
        var pids = [pid_t](repeating: 0, count: maxProcesses)
        let bytes = pids.withUnsafeMutableBytes { proc_listpids(UInt32(PROC_ALL_PIDS), 0, $0.baseAddress, Int32($0.count)) }
        guard bytes > 0 else { return [] }
        return Array(pids.prefix(Int(bytes) / MemoryLayout<pid_t>.size)).filter { $0 > 0 }
    }

    static func sockets(of pid: pid_t, proto: SocketOwnerMatcher.Proto) -> [SocketOwnerMatcher.SocketEntry] {
        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: maxDescriptorsPerProcess)
        let bytes = fds.withUnsafeMutableBytes { proc_pidinfo(pid, PROC_PIDLISTFDS, 0, $0.baseAddress, Int32($0.count)) }
        guard bytes > 0 else { return [] }
        let count = Int(bytes) / MemoryLayout<proc_fdinfo>.size
        var uid: UInt32 = 0
        var bsd = proc_bsdshortinfo()
        if proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0, &bsd, Int32(MemoryLayout<proc_bsdshortinfo>.size)) > 0 {
            uid = bsd.pbsi_uid
        }
        var out: [SocketOwnerMatcher.SocketEntry] = []
        for fd in fds.prefix(count) where fd.proc_fdtype == UInt32(PROX_FDTYPE_SOCKET) {
            var info = socket_fdinfo()
            let size = proc_pidfdinfo(pid, fd.proc_fd, PROC_PIDFDSOCKETINFO, &info, Int32(MemoryLayout<socket_fdinfo>.size))
            guard size == Int32(MemoryLayout<socket_fdinfo>.size) else { continue }
            if let entry = entry(info.psi, pid: pid, uid: uid, proto: proto) { out.append(entry) }
        }
        return out
    }

    private static func entry(_ socket: socket_info, pid: pid_t, uid: UInt32, proto: SocketOwnerMatcher.Proto) -> SocketOwnerMatcher.SocketEntry? {
        guard socket.soi_family == AF_INET || socket.soi_family == AF_INET6, socket.soi_protocol == proto.rawValue else { return nil }
        let inp: in_sockinfo
        switch Int(socket.soi_kind) {
        case SOCKINFO_TCP: inp = socket.soi_proto.pri_tcp.tcpsi_ini
        case SOCKINFO_IN: inp = socket.soi_proto.pri_in
        default: return nil
        }
        let isV4 = inp.insi_vflag & UInt8(INI_IPV4) != 0
        var laddr = inp.insi_laddr
        var faddr = inp.insi_faddr
        // The union has no Swift name; read its 16 bytes. struct in4in6_addr
        // is 12 pad bytes then the IPv4 address (sys/proc_info.h), so either
        // view is the same 16 bytes.
        let local = address(withUnsafeBytes(of: &laddr) { Array($0.prefix(16)) }, isV4: isV4)
        let remote = address(withUnsafeBytes(of: &faddr) { Array($0.prefix(16)) }, isV4: isV4)
        let localPort = UInt16(bigEndian: UInt16(truncatingIfNeeded: inp.insi_lport))
        let remotePort = UInt16(bigEndian: UInt16(truncatingIfNeeded: inp.insi_fport))
        let connected = remotePort != 0 || !remote.isUnspecified
        return SocketOwnerMatcher.SocketEntry(
            pid: pid, uid: uid, proto: proto,
            local: .init(local, localPort),
            remote: connected ? .init(remote, remotePort) : nil
        )
    }

    private static func address(_ bytes: [UInt8], isV4: Bool) -> SocketOwnerMatcher.Address {
        isV4 ? SocketOwnerMatcher.Address(ipv4: Array(bytes[12..<16])) : SocketOwnerMatcher.Address(ipv6: bytes)
    }

    static func path(of pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return "" }
        return String(cString: buffer)
    }

    static func userName(of uid: UInt32) -> String {
        guard let entry = getpwuid(uid), let name = entry.pointee.pw_name else { return "" }
        return String(cString: name)
    }
}

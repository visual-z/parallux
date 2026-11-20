import Darwin
import ParalluxKit

/// Byte counters of every interface, 64-bit.
/// `NET_RT_IFLIST2` returns `if_msghdr2` with `if_data64`; getifaddrs' 32-bit
/// counters wrap every 4 GiB.
enum InterfaceCounters {
    /// Why 1 MiB: a Mac has tens of interfaces at ~200 bytes each; the cap
    /// only guards a kernel answer that keeps growing between the two calls.
    static let bufferLimit = 1 << 20

    static func read() -> [String: InterfaceRates.Counter] {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &length, nil, 0) == 0, length > 0, length <= bufferLimit else { return [:] }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, UInt32(mib.count), &buffer, &length, nil, 0) == 0 else { return [:] }
        var result: [String: InterfaceRates.Counter] = [:]
        buffer.withUnsafeBytes { raw in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = raw.load(fromByteOffset: offset, as: if_msghdr.self)
                let size = Int(header.ifm_msglen)
                guard size > 0 else { break }
                if Int32(header.ifm_type) == RTM_IFINFO2, offset + MemoryLayout<if_msghdr2>.size <= length {
                    let message = raw.load(fromByteOffset: offset, as: if_msghdr2.self)
                    var name = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
                    if if_indextoname(UInt32(message.ifm_index), &name) != nil {
                        result[String(cString: name)] = .init(received: message.ifm_data.ifi_ibytes, sent: message.ifm_data.ifi_obytes)
                    }
                }
                offset += size
            }
        }
        return result
    }
}

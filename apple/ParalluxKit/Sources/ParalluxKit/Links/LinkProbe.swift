import Foundation

/// One probe of one network interface: can a socket bound to it (IP_BOUND_IF,
/// the option sing-box's `bind_interface` uses) reach the target, and which
/// public address does the far end see?
public struct LinkProbeResult: Codable, Equatable, Sendable {
    public var interface: String
    public var index: UInt32
    public var connected: Bool
    /// errno of the failing call; nil on success.
    public var errno: Int32?
    public var failedCall: String?
    public var millis: Int
    public var egressIP: String?
}

public enum LinkProbe {
    /// Why: a dead link must not stall the diagnostics page; 3 s is above any
    /// sane RTT to 1.1.1.1 and below the 5 s XPC dial bound. Assumed value.
    public static let timeout: TimeInterval = 3
    /// Cloudflare's trace endpoint echoes the client address as `ip=`.
    public static let traceHost = "1.1.1.1"
    public static let tracePort: UInt16 = 80

    public static func probe(interface: String, host: String = traceHost, port: UInt16 = tracePort,
                             timeout: TimeInterval = timeout, readTrace: Bool = true) -> LinkProbeResult {
        let started = Date()
        var result = LinkProbeResult(interface: interface, index: 0, connected: false, errno: nil, failedCall: nil, millis: 0, egressIP: nil)
        func fail(_ call: String, _ code: Int32) -> LinkProbeResult {
            result.failedCall = call
            result.errno = code
            result.millis = Int(Date().timeIntervalSince(started) * 1000)
            return result
        }

        let index = if_nametoindex(interface)
        guard index != 0 else { return fail("if_nametoindex", ENXIO) }
        result.index = index

        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return fail("socket", Darwin.errno) }
        defer { close(fd) }
        var boundIndex = index
        guard setsockopt(fd, IPPROTO_IP, IP_BOUND_IF, &boundIndex, socklen_t(MemoryLayout<UInt32>.size)) == 0 else {
            return fail("setsockopt(IP_BOUND_IF)", Darwin.errno)
        }
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        guard inet_pton(AF_INET, host, &address.sin_addr) == 1 else { return fail("inet_pton", EINVAL) }
        let connectResult = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if connectResult != 0 {
            guard Darwin.errno == EINPROGRESS else { return fail("connect", Darwin.errno) }
            guard wait(fd, events: Int16(POLLOUT), until: started.addingTimeInterval(timeout)) else {
                return fail("connect", ETIMEDOUT)
            }
            var soError: Int32 = 0
            var length = socklen_t(MemoryLayout<Int32>.size)
            getsockopt(fd, SOL_SOCKET, SO_ERROR, &soError, &length)
            guard soError == 0 else { return fail("connect", soError) }
        }
        result.connected = true
        result.millis = Int(Date().timeIntervalSince(started) * 1000)
        guard readTrace else { return result }

        let request = Array("GET /cdn-cgi/trace HTTP/1.1\r\nHost: \(host)\r\nConnection: close\r\n\r\n".utf8)
        guard write(fd, request, request.count) == request.count else { return result }
        // Why 4 KiB: the trace body is ~300 bytes; the cap bounds a misbehaving peer.
        var response = [UInt8]()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while response.count < 4096, wait(fd, events: Int16(POLLIN), until: started.addingTimeInterval(timeout)) {
            let count = read(fd, &buffer, buffer.count)
            if count <= 0 { break }
            response.append(contentsOf: buffer[0..<count])
        }
        let text = String(decoding: response, as: UTF8.self)
        if let body = text.range(of: "\r\n\r\n") {
            result.egressIP = parseTrace(String(text[body.upperBound...]))
        }
        return result
    }

    private static func wait(_ fd: Int32, events: Int16, until deadline: Date) -> Bool {
        let remaining = deadline.timeIntervalSinceNow
        guard remaining > 0 else { return false }
        var descriptor = pollfd(fd: fd, events: events, revents: 0)
        return poll(&descriptor, 1, Int32(remaining * 1000)) > 0
    }

    /// Extracts the `ip=` line of a /cdn-cgi/trace body.
    public static func parseTrace(_ text: String) -> String? {
        for line in text.split(whereSeparator: \.isNewline) where line.hasPrefix("ip=") {
            let value = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
            return value.isEmpty ? nil : value
        }
        return nil
    }

    /// Physical interfaces worth probing (see D2 of the research card),
    /// listed with getifaddrs rather than NWPathMonitor, which reports late
    /// and only the preferred path inside an extension (mqvpn notes).
    public static func candidateInterfaces() -> [String] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }
        var flags: [String: UInt32] = [:]
        var withIPv4: Set<String> = []
        var order: [String] = []
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let name = String(cString: entry.pointee.ifa_name)
            if flags[name] == nil { order.append(name) }
            flags[name] = entry.pointee.ifa_flags
            if entry.pointee.ifa_addr?.pointee.sa_family == sa_family_t(AF_INET) { withIPv4.insert(name) }
        }
        return order.filter { isCandidate(name: $0, flags: flags[$0] ?? 0, hasIPv4: withIPv4.contains($0)) }
    }

    /// Prefixes of virtual interfaces: tunnels (utun, ipsec), Apple peer links
    /// (awdl, llw), bridges, the hypervisor NIC (anpi) and the access point (ap).
    static let virtualPrefixes = ["lo", "utun", "ipsec", "awdl", "llw", "bridge", "anpi", "ap", "gif", "stf"]

    static func isCandidate(name: String, flags: UInt32, hasIPv4: Bool) -> Bool {
        let needed = UInt32(IFF_UP | IFF_RUNNING)
        guard flags & needed == needed, flags & UInt32(IFF_LOOPBACK) == 0, hasIPv4 else { return false }
        return !virtualPrefixes.contains { name.hasPrefix($0) }
    }
}

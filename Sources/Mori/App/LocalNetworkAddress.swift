import Foundation

#if os(macOS)
import Darwin
#endif

/// Resolves a routable IPv4 address for Remote Connect “this Mac” shortcuts.
enum LocalNetworkAddress {
    /// IPv4 addresses currently assigned to interfaces, excluding loopback and IPv4 link-local (169.254/16).
    static func routableIPv4Candidates() -> [String] {
        #if os(macOS)
        var result: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let p = ptr {
            defer { ptr = p.pointee.ifa_next }

            guard let addr = p.pointee.ifa_addr else { continue }
            if addr.pointee.sa_family != sa_family_t(AF_INET) { continue }

            var buf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let nameInfo = getnameinfo(
                addr,
                socklen_t(addr.pointee.sa_len),
                &buf,
                socklen_t(buf.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            guard nameInfo == 0 else { continue }

            let ip = String(decoding: buf.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            if ip == "127.0.0.1" { continue }
            if ip.hasPrefix("169.254.") { continue }
            result.append(ip)
        }
        return result
        #else
        return []
        #endif
    }

    /// Prefers common private LAN ranges, then any other routable candidate.
    static func preferredIPv4() -> String? {
        let candidates = routableIPv4Candidates()
        if let ip = candidates.first(where: { $0.hasPrefix("192.168.") }) { return ip }
        if let ip = candidates.first(where: { $0.hasPrefix("10.") }) { return ip }
        for ip in candidates where ip.hasPrefix("172.") {
            let parts = ip.split(separator: ".")
            if parts.count >= 2, let second = Int(parts[1]), (16...31).contains(second) {
                return ip
            }
        }
        return candidates.first
    }
}

import Foundation

/// Builds and matches the tiny DNS queries used as a UDP loss probe. Pure bytes, no sockets.
public enum DNSProbe {
    /// A recursive A query for `Endpoints.dnsQueryName` with the given 16-bit id.
    public static func query(id: UInt16, name: String = Endpoints.dnsQueryName) -> Data {
        var d = Data()
        d.append(UInt8(id >> 8)); d.append(UInt8(id & 0xff))
        d.append(contentsOf: [0x01, 0x00,   // flags: recursion desired
                              0x00, 0x01,   // QDCOUNT 1
                              0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        for label in name.split(separator: ".") {
            let bytes = Array(label.utf8.prefix(63))
            d.append(UInt8(bytes.count)); d.append(contentsOf: bytes)
        }
        d.append(contentsOf: [0x00, 0x00, 0x01, 0x00, 0x01])   // root, QTYPE A, QCLASS IN
        return d
    }

    /// True when `response` is a DNS response (QR bit set) to the query with this id.
    public static func isResponse(_ response: Data, to id: UInt16) -> Bool {
        guard response.count >= 12 else { return false }
        let bytes = [UInt8](response.prefix(3))
        let rid = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
        return rid == id && bytes[2] & 0x80 != 0
    }
}

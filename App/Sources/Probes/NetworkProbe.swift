import Foundation
import SystemConfiguration
import CoreWLAN
import GameReadyCore

/// Which interface carries the default route, its router, and whether it has global IPv6.
struct NetworkSnapshot: Sendable {
    var kind: ConnectionKind
    var interface: String?
    var router: String?
    var hasGlobalIPv6: Bool
    var wifi: WiFiLink?
}

enum NetworkProbe {
    static func snapshot() -> NetworkSnapshot {
        let store = SCDynamicStoreCreate(nil, "GameReady" as CFString, nil, nil)
        let global = store.flatMap { SCDynamicStoreCopyValue($0, "State:/Network/Global/IPv4" as CFString) as? [String: Any] }
        let interface = global?["PrimaryInterface"] as? String
        let router = global?["Router"] as? String
        let wifiNames = Set(CWWiFiClient.shared().interfaceNames() ?? [])
        let kind: ConnectionKind
        if let interface {
            if wifiNames.contains(interface) { kind = .wifi }
            else if isEthernet(interface) { kind = .ethernet }
            else { kind = .other }
        } else {
            kind = .none
        }
        let wifi = kind == .wifi ? WiFiProbe.link(interface: interface) : nil
        return NetworkSnapshot(kind: kind, interface: interface, router: router,
                               hasGlobalIPv6: interface.map(hasGlobalIPv6) ?? false, wifi: wifi)
    }

    /// Thunderbolt/USB adapters and built-in ports all report as Ethernet to SystemConfiguration.
    private static func isEthernet(_ bsdName: String) -> Bool {
        guard let all = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else { return bsdName.hasPrefix("en") }
        for i in all where (SCNetworkInterfaceGetBSDName(i) as String?) == bsdName {
            return (SCNetworkInterfaceGetInterfaceType(i) as String?) == (kSCNetworkInterfaceTypeEthernet as String)
        }
        return false
    }

    /// A global unicast IPv6 address (2000::/3) on the interface. Link-local and ULA don't count.
    static func hasGlobalIPv6(_ interface: String) -> Bool {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return false }
        defer { freeifaddrs(head) }
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = ptr.pointee
            guard String(cString: ifa.ifa_name) == interface,
                  let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET6) else { continue }
            let firstByte = addr.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee.sin6_addr.__u6_addr.__u6_addr8.0 }
            if firstByte & 0xE0 == 0x20 { return true }
        }
        return false
    }

    /// Whether an interface is up and running (used for the AirDrop radio, `awdl0`).
    static func isUp(_ interface: String) -> Bool? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }
        var found = false
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) where String(cString: ptr.pointee.ifa_name) == interface {
            found = true
            let flags = Int32(ptr.pointee.ifa_flags)
            if flags & IFF_UP != 0 && flags & IFF_RUNNING != 0 { return true }
        }
        return found ? false : nil
    }
}

enum WiFiProbe {
    /// Signal and link facts that macOS gives without Location access (the network name needs it; we don't ask).
    static func link(interface name: String?) -> WiFiLink? {
        let client = CWWiFiClient.shared()
        guard let iface = name.flatMap({ client.interface(withName: $0) }) ?? client.interface() else { return nil }
        let channel = iface.wlanChannel()
        let band: WiFiBand
        switch channel?.channelBand {
        case .band2GHz: band = .ghz24
        case .band5GHz: band = .ghz5
        case .band6GHz: band = .ghz6
        default: band = .unknown
        }
        let width: Int?
        switch channel?.channelWidth {
        case .width20MHz: width = 20
        case .width40MHz: width = 40
        case .width80MHz: width = 80
        case .width160MHz: width = 160
        default: width = nil
        }
        let rssi = iface.rssiValue()
        let noise = iface.noiseMeasurement()
        let rate = iface.transmitRate()
        return WiFiLink(band: band, channel: channel.map { $0.channelNumber }, widthMHz: width,
                        rssi: rssi == 0 ? nil : rssi, noise: noise == 0 ? nil : noise,
                        txRateMbps: rate > 0 ? rate : nil)
    }
}

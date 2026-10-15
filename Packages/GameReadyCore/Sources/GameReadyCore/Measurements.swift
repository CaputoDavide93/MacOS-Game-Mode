/// Plain values the probes produce. No I/O lives here.

public enum ConnectionKind: String, Sendable, Codable {
    case ethernet, wifi, other, none
}

public enum WiFiBand: String, Sendable, Codable {
    case ghz24, ghz5, ghz6, unknown
}

public struct WiFiLink: Sendable, Codable, Equatable {
    public var band: WiFiBand
    public var channel: Int?
    public var widthMHz: Int?
    public var rssi: Int?
    public var noise: Int?
    public var txRateMbps: Double?

    public init(band: WiFiBand, channel: Int? = nil, widthMHz: Int? = nil,
                rssi: Int? = nil, noise: Int? = nil, txRateMbps: Double? = nil) {
        self.band = band; self.channel = channel; self.widthMHz = widthMHz
        self.rssi = rssi; self.noise = noise; self.txRateMbps = txRateMbps
    }
}

/// An Ethernet port's negotiated link, from `ifconfig`'s media line.
public struct EthernetLink: Sendable, Codable, Equatable {
    public var mbps: Int
    public var fullDuplex: Bool

    public init(mbps: Int, fullDuplex: Bool) { self.mbps = mbps; self.fullDuplex = fullDuplex }

    /// "media: autoselect (1000baseT <full-duplex>)" → 1000 Mbps, full duplex. The active media
    /// is in parentheses when it differs from the configured one ("autoselect"); a port set to a
    /// fixed speed prints it bare ("media: 100baseTX <full-duplex>"). Nil with no link.
    public static func parse(_ ifconfig: String) -> EthernetLink? {
        guard let line = ifconfig.split(separator: "\n").first(where: { $0.contains("media:") }),
              let colon = line.range(of: "media:") else { return nil }
        var active = line[colon.upperBound...]
        if let open = active.firstIndex(of: "("), let close = active.lastIndex(of: ")"), open < close {
            active = active[active.index(after: open)..<close]
        }
        let inside = active.lowercased()
        // The speed is the number before "base": 10, 100, 1000, 2500, 5000, or 10g.
        guard let base = inside.range(of: "base") else { return nil }
        let token = inside[..<base.lowerBound].trimmingCharacters(in: .whitespaces)
        let mbps: Int
        if token.hasSuffix("g"), let g = Int(token.dropLast()) { mbps = g * 1000 }
        else if let m = Int(token) { mbps = m }
        else { return nil }
        return EthernetLink(mbps: mbps, fullDuplex: !inside.contains("half-duplex"))
    }
}

public enum ThermalLevel: String, Sendable, Codable {
    case nominal, fair, serious, critical
}

public struct MacState: Sendable, Codable, Equatable {
    public var awdlUp: Bool?
    public var lowPowerMode: Bool
    public var onBattery: Bool
    public var batteryPercent: Int?
    public var thermal: ThermalLevel
    public var cpuPercent: Double?

    public init(awdlUp: Bool?, lowPowerMode: Bool, onBattery: Bool, batteryPercent: Int?,
                thermal: ThermalLevel, cpuPercent: Double?) {
        self.awdlUp = awdlUp; self.lowPowerMode = lowPowerMode; self.onBattery = onBattery
        self.batteryPercent = batteryPercent; self.thermal = thermal; self.cpuPercent = cpuPercent
    }
}

/// One speed-test direction after validation (see `SpeedRun`).
public struct SpeedMeasurement: Sendable, Codable, Equatable {
    public var downMbps: Double?
    public var upMbps: Double?
    public var idleMedianMs: Double?
    public var loadedDownMedianMs: Double?
    public var loadedUpMedianMs: Double?
    /// Every provider refused or short-changed us (e.g. HTTP 429).
    public var rateLimited: Bool

    public init(downMbps: Double?, upMbps: Double?, idleMedianMs: Double?,
                loadedDownMedianMs: Double?, loadedUpMedianMs: Double?, rateLimited: Bool = false) {
        self.downMbps = downMbps; self.upMbps = upMbps; self.idleMedianMs = idleMedianMs
        self.loadedDownMedianMs = loadedDownMedianMs; self.loadedUpMedianMs = loadedUpMedianMs
        self.rateLimited = rateLimited
    }

    /// The worst rise in latency the load caused, in ms. Nil without a baseline.
    public var loadRiseMs: Double? {
        guard let idle = idleMedianMs else { return nil }
        let rises = [loadedDownMedianMs, loadedUpMedianMs].compactMap { $0.map { $0 - idle } }
        return rises.max()
    }
}

/// The kernel's whole-machine CPU tick counters (`host_cpu_load_info`). They are 32-bit
/// and wrap after weeks of uptime, so deltas use wrapping subtraction per counter.
public struct CPUTicks: Sendable, Equatable {
    public var user: UInt32, system: UInt32, idle: UInt32, nice: UInt32

    public init(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32) {
        self.user = user; self.system = system; self.idle = idle; self.nice = nice
    }

    /// Busy share of the time between two readings, in percent. Nil when no time passed.
    public static func busyPercent(from a: CPUTicks, to b: CPUTicks) -> Double? {
        let busy = Double(b.user &- a.user) + Double(b.system &- a.system) + Double(b.nice &- a.nice)
        let total = busy + Double(b.idle &- a.idle)
        return total > 0 ? busy * 100 / total : nil
    }
}

public struct ChecklistItemState: Sendable, Codable, Equatable {
    public var key: String
    public var done: Bool
    public init(key: String, done: Bool) { self.key = key; self.done = done }
}

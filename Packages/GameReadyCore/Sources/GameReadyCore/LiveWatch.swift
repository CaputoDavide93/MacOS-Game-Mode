import Foundation

/// Which part of the chain a hiccup came from.
public enum Layer: String, Sendable, Codable {
    /// The Mac's own Wi-Fi hop to the router (AirDrop/AWDL, Wi-Fi scans, signal).
    case macWiFi
    /// Beyond the router: the household line, the provider, the game server.
    case internet
    /// The Mac itself: CPU, heat.
    case mac
}

public enum LiveEventKind: String, Sendable, Codable {
    case spike, loss, linkChanged, awdlBack, cpuBusy, thermalHigh, noisyAppStarted
}

public struct LiveEvent: Sendable, Codable, Equatable, Identifiable {
    public var id: Date { at }
    public var at: Date
    public var kind: LiveEventKind
    public var layer: Layer
    /// The number that triggered it, already formatted ("73 ms").
    public var value: String?

    public init(at: Date, kind: LiveEventKind, layer: Layer, value: String? = nil) {
        self.at = at; self.kind = kind; self.layer = layer; self.value = value
    }
}

/// One tick of the live watch: the latest router and game-server pings (nil = lost,
/// absent = not measured this tick).
public struct LiveTick: Sendable, Equatable {
    public var at: Date
    public var routerMs: Double??
    public var serverMs: Double??

    public init(at: Date, routerMs: Double?? = .none, serverMs: Double?? = .none) {
        self.at = at; self.routerMs = routerMs; self.serverMs = serverMs
    }
}

/// Turns ticks into events. The rule that separates the layers:
/// if the router hop is bad, it's the Mac's Wi-Fi; if only the server is bad, it's the internet.
public struct LiveClassifier: Sendable {
    public var spikeMs: Double
    /// Don't report the same layer twice within this window.
    public var quietSeconds: TimeInterval = 10
    private var lastByLayer: [Layer: Date] = [:]

    public init(spikeMs: Double = Thresholds.standard.liveSpikeMs) { self.spikeMs = spikeMs }

    public mutating func classify(_ tick: LiveTick) -> LiveEvent? {
        let routerBad: (LiveEventKind, String?)? = badness(tick.routerMs)
        let serverBad: (LiveEventKind, String?)? = badness(tick.serverMs)
        let event: LiveEvent?
        if let (kind, value) = routerBad {
            event = LiveEvent(at: tick.at, kind: kind, layer: .macWiFi, value: value)
        } else if let (kind, value) = serverBad, routerIsFine(tick.routerMs) {
            event = LiveEvent(at: tick.at, kind: kind, layer: .internet, value: value)
        } else {
            event = nil
        }
        guard let event else { return nil }
        if let last = lastByLayer[event.layer], event.at.timeIntervalSince(last) < quietSeconds { return nil }
        lastByLayer[event.layer] = event.at
        return event
    }

    /// Mac-side events (CPU, heat, AWDL, apps) go through the same de-duplication.
    public mutating func report(_ event: LiveEvent) -> LiveEvent? {
        if let last = lastByLayer[event.layer], event.at.timeIntervalSince(last) < quietSeconds { return nil }
        lastByLayer[event.layer] = event.at
        return event
    }

    private func badness(_ sample: Double??) -> (LiveEventKind, String?)? {
        switch sample {
        case .none: return nil                                   // not measured this tick
        case .some(.none): return (.loss, nil)                   // lost
        case .some(.some(let ms)) where ms > spikeMs: return (.spike, String(format: "%.0f ms", ms))
        default: return nil
        }
    }

    /// Only blame the internet when the router hop was measured and fine.
    private func routerIsFine(_ sample: Double??) -> Bool {
        if case .some(.some(let ms)) = sample { return ms <= spikeMs }
        return false
    }
}

/// End-of-session summary for the "2 hiccups: 21:03 internet, 21:17 Wi-Fi" line.
public struct SessionSummary: Sendable, Codable, Equatable {
    public var start: Date
    public var end: Date
    public var events: [LiveEvent]
    public var countByLayer: [Layer: Int] {
        Dictionary(grouping: events, by: \.layer).mapValues(\.count)
    }

    public init(start: Date, end: Date, events: [LiveEvent]) {
        self.start = start; self.end = end; self.events = events
    }
}

import Foundation
import Observation
import GameReadyCore

/// While Game Mode is on: two pings side by side (router and game server) plus a Mac check
/// every 10 s. Each hiccup is labelled with the layer it came from (D5).
@MainActor @Observable
final class LiveMonitor {
    private(set) var running = false
    private(set) var lastRouterMs: Double?
    private(set) var lastServerMs: Double?
    private(set) var events: [LiveEvent] = []
    private(set) var startedAt: Date?

    private var classifier = LiveClassifier()
    private var routerPing: StreamingPing?
    private var serverPing: StreamingPing?
    private var macTask: Task<Void, Never>?
    /// Latest router sample (nil = lost) and when it arrived.
    private var recentRouter: (ms: Double?, at: Date)?
    private var lastLink: (WiFiBand, Int?)?

    /// Current health for the menu-bar dot.
    var grade: Grade {
        guard running else { return .unknown }
        if let last = events.last, Date().timeIntervalSince(last.at) < 20 { return .red }
        if let r = lastRouterMs, let s = lastServerMs, r <= 10, s <= 40 { return .green }
        return .amber
    }

    func start(router: String?, server: String) {
        guard !running else { return }
        running = true
        startedAt = Date()
        events = []
        classifier = LiveClassifier()
        if let router {
            routerPing = StreamingPing(host: router, interval: 1) { [weak self] ms in
                Task { @MainActor in self?.receive(router: ms) }
            }
            routerPing?.start()
        }
        serverPing = StreamingPing(host: server, interval: 2) { [weak self] ms in
            Task { @MainActor in self?.receive(server: ms) }
        }
        serverPing?.start()
        macTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                await self?.checkMac()
            }
        }
    }

    /// Stops and returns the session summary.
    @discardableResult
    func stop() -> SessionSummary? {
        guard running, let start = startedAt else { return nil }
        routerPing?.stop(); serverPing?.stop(); macTask?.cancel()
        routerPing = nil; serverPing = nil; macTask = nil
        running = false
        return SessionSummary(start: start, end: Date(), events: events)
    }

    /// A router sample on its own can show a Wi-Fi hiccup.
    private func receive(router ms: Double?) {
        let now = Date()
        if let ms { lastRouterMs = ms }
        recentRouter = (ms, now)
        record(classifier.classify(LiveTick(at: now, routerMs: .some(ms), serverMs: .none)))
    }

    /// A server sample is judged with the latest router sample from the last 3 s, so a
    /// spike is blamed on the internet only when the Wi-Fi hop was fine at the same moment.
    private func receive(server ms: Double?) {
        let now = Date()
        if let ms { lastServerMs = ms }
        let router: Double?? = recentRouter.flatMap { now.timeIntervalSince($0.at) <= 3 ? .some($0.ms) : nil }
        record(classifier.classify(LiveTick(at: now, routerMs: router, serverMs: .some(ms))))
    }

    private func record(_ event: LiveEvent?) {
        guard let event else { return }
        events.append(event)
        if events.count > 500 { events.removeFirst(events.count - 500) }
    }

    private func checkMac() async {
        let state = await MacProbe.state()
        let now = Date()
        if state.awdlUp == true { record(classifier.report(LiveEvent(at: now, kind: .awdlBack, layer: .macWiFi))) }
        if let cpu = state.cpuPercent, cpu > Thresholds.standard.cpuRedPercent {
            record(classifier.report(LiveEvent(at: now, kind: .cpuBusy, layer: .mac, value: String(format: "%.0f%%", cpu))))
        }
        if state.thermal == .serious || state.thermal == .critical {
            record(classifier.report(LiveEvent(at: now, kind: .thermalHigh, layer: .mac)))
        }
        let snap = NetworkProbe.snapshot()
        if let link = snap.wifi {
            let key = (link.band, link.channel)
            if let last = lastLink, last.0 != key.0 || last.1 != key.1 {
                record(classifier.report(LiveEvent(at: now, kind: .linkChanged, layer: .macWiFi, value: link.channel.map { "ch \($0)" })))
            }
            lastLink = key
        }
    }
}

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
    /// Latest replies (not losses), for the dot: green needs both to be fresh.
    private var routerReply: (ms: Double, at: Date)?
    private var serverReply: (ms: Double, at: Date)?
    private var lastLink: (WiFiBand, Int?)?
    /// The gateway being pinged; a new one (another network) restarts the router ping.
    private var routerHost: String?
    /// Identifies the running session, so a check that finishes after "stop" changes nothing.
    private var session: UUID?

    /// Current health for the menu-bar dot.
    var grade: Grade {
        LiveHealth.grade(running: running, now: Date(), lastEventAt: events.last?.at,
                         router: routerReply, server: serverReply)
    }

    func start(router: String?, server: String) {
        guard !running else { return }
        running = true
        startedAt = Date()
        events = []
        classifier = LiveClassifier()
        // Nothing from an earlier session (maybe another network) carries over.
        lastRouterMs = nil; lastServerMs = nil
        recentRouter = nil; routerReply = nil; serverReply = nil; lastLink = nil
        startRouterPing(router)
        serverPing = StreamingPing(host: server, interval: 2) { [weak self] ms in
            Task { @MainActor in self?.receive(server: ms) }
        }
        serverPing?.start()
        let session = UUID()
        self.session = session
        macTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(10)) } catch { return }
                await self?.checkMac(session: session)
            }
        }
    }

    private func startRouterPing(_ host: String?) {
        routerPing?.stop()
        routerPing = nil
        routerHost = host
        guard let host else { return }
        routerPing = StreamingPing(host: host, interval: 1) { [weak self] ms in
            Task { @MainActor in self?.receive(router: ms) }
        }
        routerPing?.start()
    }

    /// Screenshots only: a running session with made-up readings.
    func loadDemo(at t: Date) {
        running = true
        startedAt = t.addingTimeInterval(-1_800)
        lastRouterMs = 3
        lastServerMs = 18
        routerReply = (3, t)
        serverReply = (18, t)
        events = [LiveEvent(at: t.addingTimeInterval(-1_200), kind: .spike, layer: .internet, value: "62 ms"),
                  LiveEvent(at: t.addingTimeInterval(-300), kind: .awdlBack, layer: .macWiFi)]
    }

    /// Stops and returns the session summary.
    @discardableResult
    func stop() -> SessionSummary? {
        guard running, let start = startedAt else { return nil }
        routerPing?.stop(); serverPing?.stop(); macTask?.cancel()
        routerPing = nil; serverPing = nil; macTask = nil
        session = nil
        running = false
        return SessionSummary(start: start, end: Date(), events: events)
    }

    /// A router sample on its own can show a Wi-Fi hiccup.
    private func receive(router ms: Double?) {
        let now = Date()
        if let ms { lastRouterMs = ms; routerReply = (ms, now) }
        recentRouter = (ms, now)
        record(classifier.classify(LiveTick(at: now, routerMs: .some(ms), serverMs: .none)))
    }

    /// A server sample is judged with the latest router sample from the last 3 s, so a
    /// spike is blamed on the internet only when the Wi-Fi hop was fine at the same moment.
    private func receive(server ms: Double?) {
        let now = Date()
        if let ms { lastServerMs = ms; serverReply = (ms, now) }
        let router: Double?? = recentRouter.flatMap { now.timeIntervalSince($0.at) <= 3 ? .some($0.ms) : nil }
        record(classifier.classify(LiveTick(at: now, routerMs: router, serverMs: .some(ms))))
    }

    private func record(_ event: LiveEvent?) {
        guard let event else { return }
        events.append(event)
        if events.count > 500 { events.removeFirst(events.count - 500) }
    }

    private func checkMac(session: UUID) async {
        let state = await MacProbe.state()
        guard running, self.session == session else { return }
        let now = Date()
        if state.awdlUp == true { record(classifier.report(LiveEvent(at: now, kind: .awdlBack, layer: .macWiFi))) }
        if let cpu = state.cpuPercent, cpu > Thresholds.standard.cpuRedPercent {
            record(classifier.report(LiveEvent(at: now, kind: .cpuBusy, layer: .mac, value: String(format: "%.0f%%", cpu))))
        }
        if state.thermal == .serious || state.thermal == .critical {
            record(classifier.report(LiveEvent(at: now, kind: .thermalHigh, layer: .mac)))
        }
        let snap = NetworkProbe.snapshot()
        // Another network (Wi-Fi to Ethernet, a new gateway): ping the router that's there now.
        if snap.router != routerHost {
            record(classifier.report(LiveEvent(at: now, kind: .networkChanged, layer: .macWiFi)))
            recentRouter = nil; routerReply = nil; lastRouterMs = nil; lastLink = nil
            startRouterPing(snap.router)
        }
        if let link = snap.wifi {
            let key = (link.band, link.channel)
            if let last = lastLink, last.0 != key.0 || last.1 != key.1 {
                record(classifier.report(LiveEvent(at: now, kind: .linkChanged, layer: .macWiFi, value: link.channel.map { "ch \($0)" })))
            }
            lastLink = key
        }
    }
}

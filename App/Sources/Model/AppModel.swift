import AppKit
import Foundation
import Observation
import GameReadyCore

/// Runs the pre-flight check and owns the app's state.
@MainActor @Observable
final class AppModel {
    enum Step: String, CaseIterable, Sendable {
        case connection, hop, internet, udp, mac, speed
    }

    let settings = AppSettings()
    let checklist = Checklist()
    let gameMode = GameModeController()
    let live = LiveMonitor()
    let history = HistoryStore(directory: GameModeController.supportDir)

    private(set) var results: [CheckResult] = []
    private(set) var verdict: Verdict?
    private(set) var lastCheck: Date?
    private(set) var running = false
    private(set) var step: Step?
    private(set) var stepsDone = 0
    private(set) var lastSpeedTest: Date?
    private(set) var entries: [HistoryEntry] = []
    private(set) var lastSession: SessionSummary?
    private(set) var router: String?

    private let grader = Grader()
    /// A one-run override (command line); nil uses the saved setting.
    var speedTestOverride: Bool?
    private var includeSpeed: Bool { speedTestOverride ?? settings.runSpeedTest }

    init() {
        try? history.prune()
        entries = history.load()
    }

    var stepCount: Int { includeSpeed ? Step.allCases.count : Step.allCases.count - 1 }

    // MARK: - Check

    func runCheck() async {
        guard !running else { return }   // a second click while running does nothing
        running = true
        stepsDone = 0
        results = []
        defer { running = false; step = nil }

        // Connection + Wi-Fi
        step = .connection
        let net = NetworkProbe.snapshot()
        router = net.router
        var out = [grader.connection(net.kind, band: net.wifi?.band), grader.wifi(net.wifi, kind: net.kind)]
        advance(out)

        // Hop and internet run together; UDP after (it's 200 queries spaced 20 ms).
        step = .hop
        let routerHost = net.router
        async let hopSamples: [Double?] = routerHost == nil ? [] : PingProbe.run(host: routerHost!, count: 100, interval: 0.1)
        async let cfSamples = PingProbe.run(host: Endpoints.cloudflareDNSv4, count: 50, interval: 0.1)
        async let gameSamples = PingProbe.run(host: settings.gameServerHost, count: 50, interval: 0.1)
        let hop = await hopSamples
        out.append(hop.isEmpty ? .notMeasured(.hop) : grader.hop(PingStats(samples: hop)))
        advance(out)

        step = .internet
        let cf = await cfSamples, game = await gameSamples
        out.append(grader.internet(["Cloudflare": PingStats(samples: cf), "Game server": PingStats(samples: game)]))
        advance(out)

        step = .udp
        async let v4 = UDPProbe.run(server: Endpoints.cloudflareDNSv4)
        async let v6: [Double?]? = net.hasGlobalIPv6 ? await UDPProbe.run(server: Endpoints.cloudflareDNSv6) : nil
        let u4 = PingStats(samples: await v4)
        let u6 = await v6.map { PingStats(samples: $0) }
        out.append(grader.udp(v4: u4, v6: u6))
        out.append(grader.ipv6(hasGlobalAddress: net.hasGlobalIPv6, udpV6: u6))
        advance(out)

        // Line busy? Idle latency now vs. the best of recent checks.
        let idle = PingStats.median(cf)
        out.append(grader.lineFree(idleMedianMs: idle, bestRecentMs: bestRecentIdle()))

        step = .mac
        let mac = await MacProbe.state()
        out.append(grader.mac(mac))
        let noisy = AppsProbe.runningNoisy(enabled: settings.quitApps).compactMap(\.localizedName)
        out.append(grader.apps(noisy: noisy, timeMachineRunning: await AppsProbe.timeMachineRunning()))
        await checklist.detect()
        out.append(grader.checklist(checklist.states))
        advance(out)

        // Speed last: it's the only step that loads the line.
        if includeSpeed {
            step = .speed
            if let last = lastSpeedTest, Date().timeIntervalSince(last) < SpeedRun.minimumGap {
                out.append(CheckResult(id: .speed, grade: .unknown, findings: [.notMeasured],
                                       details: ["skipped": String(localized: "speed.tooSoon")]))
            } else {
                let m = await SpeedProbe.run(idleMedianMs: idle, latencyHost: Endpoints.cloudflareDNSv4)
                lastSpeedTest = Date()
                out.append(grader.speed(m))
            }
            advance(out)
        }

        finish(out, idle: idle)
    }

    private func advance(_ partial: [CheckResult]) {
        results = order(partial)
        stepsDone += 1
    }

    private func finish(_ out: [CheckResult], idle: Double?) {
        results = order(out)
        let v = Verdict(results: results)
        verdict = v
        lastCheck = Date()
        var record = CheckRecord(at: Date(), verdict: v.level, results: results)
        if let idle { record.idleMedianMs = idle }
        try? history.append(.check(record))
        entries = history.load()
    }

    private func order(_ r: [CheckResult]) -> [CheckResult] {
        let index = Dictionary(uniqueKeysWithValues: CheckID.allCases.enumerated().map { ($1, $0) })
        return r.sorted { index[$0.id, default: 0] < index[$1.id, default: 0] }
    }

    /// Best idle latency from checks in the last 14 days: this Mac's "quiet line" baseline.
    private func bestRecentIdle() -> Double? {
        let cutoff = Date().addingTimeInterval(-14 * 86_400)
        return entries.compactMap { entry -> Double? in
            if case .check(let c) = entry, c.at >= cutoff { return c.idleMedianMs }
            return nil
        }.min()
    }

    // MARK: - Game Mode and play

    func toggleGameMode() async {
        if gameMode.isOn || gameMode.leftOn {
            await gameMode.turnOff()
            if let summary = live.stop() {
                lastSession = summary
                try? history.append(.session(summary))
                entries = history.load()
            }
        } else {
            let apps = AppsProbe.runningNoisy(enabled: settings.quitApps)
            await gameMode.turnOn(quitting: apps)
            if gameMode.isOn {
                live.start(router: router ?? NetworkProbe.snapshot().router, server: settings.gameServerHost)
            }
        }
    }

    func play() {
        guard let url = URL(string: settings.playURL), url.scheme == "https" else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: settings.browser.bundleID) {
            NSWorkspace.shared.open([url], withApplicationAt: app, configuration: config)
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - History

    func deleteAllData() {
        try? history.deleteAll()
        entries = []
        lastSession = nil
    }

    func exportCSV() -> String {
        HistoryCSV.checks(entries.compactMap { if case .check(let c) = $0 { return c } else { return nil } })
    }
}

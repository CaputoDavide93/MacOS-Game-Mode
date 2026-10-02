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
    let changes = SessionChanges()
    let history = HistoryStore(directory: GameModeController.supportDir)

    private(set) var results: [CheckResult] = []
    private(set) var verdict: Verdict?
    private(set) var lastCheck: Date?
    private(set) var running = false
    private(set) var step: Step?
    private(set) var stepsDone = 0
    /// Persisted, so relaunching the app doesn't bypass the 2-minute gap (D6).
    private(set) var lastSpeedTest: Date? {
        get { UserDefaults.standard.object(forKey: "lastSpeedTest") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "lastSpeedTest") }
    }
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
        // An undo left over from a session whose Game Mode is already off (e.g. Better xCloud
        // couldn't be restored because no xbox.com tab was open): retry it quietly.
        Task { await retryPendingRestore() }
    }

    /// Holds the same lock as the Game Mode switch, so a retry can't interleave with a new session.
    func retryPendingRestore() async {
        guard !gameMode.isOn, !gameMode.leftOn, !switching, changes.hasPendingRestore else { return }
        switching = true
        defer { switching = false }
        await changes.restore()
    }

    var stepCount: Int { includeSpeed ? Step.allCases.count : Step.allCases.count - 1 }

    // MARK: - Check

    func runCheck() async {
        guard !running else { return }   // a second click while running does nothing
        await retryPendingRestore()
        running = true
        stepsDone = 0
        results = []
        verdict = nil   // never show the previous verdict next to new partial results
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
        // The game-server ping is Xbox's front door; other platforms are graded on Cloudflare alone.
        let pingGame = settings.platform == .xboxCloud
        async let gameSamples: [Double?] = pingGame ? PingProbe.run(host: settings.gameServerHost, count: 50, interval: 0.1) : []
        let hop = await hopSamples
        out.append(hop.isEmpty ? .notMeasured(.hop) : grader.hop(PingStats(samples: hop)))
        advance(out)

        step = .internet
        let cf = await cfSamples, game = await gameSamples
        var targets = ["Cloudflare": PingStats(samples: cf)]
        if pingGame { targets["Game server"] = PingStats(samples: game) }
        out.append(grader.internet(targets))
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
        if settings.platform.usesBetterXcloud {
            await changes.refreshXcloud(browser: settings.browser)
            checklist.applyBetterXcloud(changes.xcloudSettings)
        }
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

    /// True while Game Mode is switching; the switch ignores clicks until it settles.
    private(set) var switching = false
    private(set) var changesError: String?

    func toggleGameMode() async {
        guard !switching else { return }   // one transition at a time
        switching = true
        defer { switching = false }
        changesError = nil
        if gameMode.isOn || gameMode.leftOn {
            await gameMode.turnOff()
            await changes.restore()
            if let summary = live.stop() {
                lastSession = summary
                try? history.append(.session(summary))
                entries = history.load()
            }
        } else {
            let apps = AppsProbe.runningNoisy(enabled: settings.quitApps)
            await gameMode.turnOn(quitting: apps)
            if gameMode.isOn {
                do {
                    try await changes.apply(betterXcloud: settings.tuneBetterXcloud && settings.platform.usesBetterXcloud,
                                            browser: settings.browser)
                } catch {
                    // Couldn't record the originals: change nothing, and back out of Game Mode.
                    changesError = error.localizedDescription
                    await gameMode.turnOff()
                    await changes.restore()
                    return
                }
                live.start(router: router ?? NetworkProbe.snapshot().router, server: settings.gameServerHost)
            }
        }
    }

    /// Opens the chosen platform: its own Mac app when installed, otherwise the browser.
    func play() {
        let platform = settings.platform
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        if let id = platform.nativeAppBundleID, let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            NSWorkspace.shared.openApplication(at: app, configuration: config)
            return
        }
        let url = platform.playURL
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: settings.browser.bundleID) {
            NSWorkspace.shared.open([url], withApplicationAt: app, configuration: config)
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Demo data (screenshots only; never real measurements)

    func loadDemo() {
        results = [
            CheckResult(id: .connection, grade: .amber, findings: [.wifi6GHz]),
            CheckResult(id: .wifi, grade: .green, findings: [.wifiStrong], details: ["rssi": "-52 dBm", "channel": "37 (160 MHz)", "rate": "2402 Mbps"]),
            CheckResult(id: .hop, grade: .green, findings: [.hopSteady], details: ["avg": "3.9 ms", "max": "7.2 ms", "loss": "0.0%"]),
            CheckResult(id: .internet, grade: .green, findings: [.internetGood]),
            CheckResult(id: .udp, grade: .green, findings: [.udpClean]),
            CheckResult(id: .ipv6, grade: .green, findings: [.ipv6Ready]),
            CheckResult(id: .speed, grade: .green, findings: [.speedGood], details: ["down": "142 Mbps", "up": "138 Mbps", "rise": "+6 ms"]),
            CheckResult(id: .lineFree, grade: .green, findings: [.lineQuiet]),
            CheckResult(id: .mac, grade: .amber, findings: [.awdlOn]),
            CheckResult(id: .apps, grade: .green, findings: [.appsQuiet]),
            CheckResult(id: .checklist, grade: .green, findings: [.checklistDone]),
        ]
        verdict = Verdict(results: results)
        lastCheck = Date(timeIntervalSince1970: 1_790_000_000)
        let t = Date(timeIntervalSince1970: 1_790_003_600)
        entries = [
            .session(SessionSummary(start: t.addingTimeInterval(-3_000), end: t, events: [
                LiveEvent(at: t.addingTimeInterval(-2_400), kind: .spike, layer: .internet, value: "62 ms"),
                LiveEvent(at: t.addingTimeInterval(-900), kind: .awdlBack, layer: .macWiFi)])),
            .check(CheckRecord(at: t.addingTimeInterval(-3_100), verdict: .warning, results: results)),
            .check(CheckRecord(at: t.addingTimeInterval(-90_000), verdict: .ready, results: [])),
        ]
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

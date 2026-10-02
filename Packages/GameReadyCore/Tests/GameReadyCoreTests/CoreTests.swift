import Foundation
import Testing
@testable import GameReadyCore

@Suite struct PingStatsTests {
    @Test func basicStats() {
        let s = PingStats(samples: [10, 12, nil, 14])
        #expect(s.sent == 4 && s.received == 3)
        #expect(s.lossPercent == 25)
        #expect(s.minMs == 10 && s.maxMs == 14)
        #expect(s.avgMs == 12)
        #expect(s.jitterMs == 2)
    }

    @Test func emptyIsEmptyNotZero() {
        let s = PingStats(samples: [nil, nil])
        #expect(s.isEmpty)
        #expect(s.avgMs == nil)
        #expect(s.lossPercent == 100)
    }

    @Test func noSamplesIsTotalLoss() {
        #expect(PingStats(samples: []).lossPercent == 100)
    }

    @Test func p95() {
        let s = PingStats(samples: (1...100).map { Double($0) })
        #expect(s.p95Ms == 95)
    }

    @Test func median() {
        #expect(PingStats.median([3, nil, 1, 2]) == 2)
        #expect(PingStats.median([4, 1, 2, 3]) == 2.5)
        #expect(PingStats.median([nil]) == nil)
    }
}

@Suite struct PingLineTests {
    @Test func ipv4Reply() {
        #expect(PingLine.parse("64 bytes from 1.1.1.1: icmp_seq=3 ttl=57 time=13.204 ms") == .reply(seq: 3, ms: 13.204))
    }

    @Test func ipv6Reply() {
        #expect(PingLine.parse("16 bytes from 2606:4700:4700::1111, icmp_seq=0 hlim=57 time=14.1 ms") == .reply(seq: 0, ms: 14.1))
    }

    @Test func timeout() {
        #expect(PingLine.parse("Request timeout for icmp_seq 5") == .timeout(seq: 5))
    }

    @Test func summaryLinesIgnored() {
        #expect(PingLine.parse("round-trip min/avg/max/stddev = 8.1/12.5/19.2/2.4 ms") == .other)
        #expect(PingLine.parse("PING 1.1.1.1 (1.1.1.1): 56 data bytes") == .other)
    }

    @Test func samplesFillGapsAsLost() {
        let out = """
        PING 1.1.1.1 (1.1.1.1): 56 data bytes
        64 bytes from 1.1.1.1: icmp_seq=0 ttl=57 time=10.0 ms
        Request timeout for icmp_seq 1
        64 bytes from 1.1.1.1: icmp_seq=2 ttl=57 time=12.0 ms
        """
        #expect(PingLine.samples(from: out, count: 4) == [10, nil, 12, nil])
    }
}

@Suite struct GraderTests {
    let g = Grader()

    @Test func connection() {
        #expect(g.connection(.ethernet, band: nil).grade == .green)
        #expect(g.connection(.wifi, band: .ghz6).grade == .amber)
        #expect(g.connection(.wifi, band: .ghz24).grade == .red)
        #expect(g.connection(.none, band: nil).grade == .red)
        #expect(g.connection(.wifi, band: .unknown).grade == .unknown)
    }

    @Test func wifi() {
        #expect(g.wifi(WiFiLink(band: .ghz6, rssi: -50, txRateMbps: 2400), kind: .wifi).grade == .green)
        #expect(g.wifi(WiFiLink(band: .ghz5, rssi: -65, txRateMbps: 800), kind: .wifi).grade == .amber)
        #expect(g.wifi(WiFiLink(band: .ghz5, rssi: -74, txRateMbps: 800), kind: .wifi).grade == .red)
        #expect(g.wifi(WiFiLink(band: .ghz5, rssi: -50, txRateMbps: 150), kind: .wifi).grade == .red)
        #expect(g.wifi(nil, kind: .wifi).grade == .unknown)
        #expect(g.wifi(nil, kind: .ethernet).grade == .green)
    }

    @Test func hopCatchesAWDLSpikes() {
        // The pattern AirDrop's radio (AWDL) causes: mostly fine, a few 70 ms pauses.
        let awdl = PingStats(samples: Array(repeating: 4.0, count: 94) + Array(repeating: 73.0, count: 6))
        #expect(g.hop(awdl).grade == .red)
        #expect(g.hop(awdl).findings.first == .hopPausing)
        #expect(g.hop(PingStats(samples: Array(repeating: 4.7, count: 100) + [7.9])).grade == .green)
        #expect(g.hop(PingStats(samples: [4, 4, 15])).grade == .amber)
        #expect(g.hop(PingStats(samples: [4, nil, 4])).findings.first == .hopLoss)
        #expect(g.hop(PingStats(samples: [nil])).grade == .unknown)
    }

    @Test func internetWorstTargetWins() {
        let good = PingStats(samples: Array(repeating: 13.0, count: 50))
        let bad = PingStats(samples: [13, 45, 13, 45, 13])
        let r = g.internet(["cloudflare": good, "game": bad])
        #expect(r.grade == .red)
        #expect(r.findings.first == .internetPoor)
        #expect(g.internet(["a": good]).grade == .green)
        #expect(g.internet([:]).grade == .unknown)
        #expect(g.internet(["a": PingStats(samples: [13, nil])]).findings.first == .internetLoss)
    }

    @Test func udp() {
        let clean = PingStats(samples: Array(repeating: 15.0, count: 200))
        #expect(g.udp(v4: clean, v6: clean).grade == .green)
        let oneLost = PingStats(samples: Array(repeating: 15.0, count: 199) + [nil])
        #expect(g.udp(v4: oneLost, v6: clean).grade == .amber)
        let lossy = PingStats(samples: Array(repeating: 15.0, count: 190) + Array(repeating: nil, count: 10))
        #expect(g.udp(v4: lossy, v6: nil).grade == .red)
        #expect(g.udp(v4: nil, v6: nil).grade == .unknown)
        #expect(g.udp(v4: PingStats(samples: [nil, nil]), v6: nil).grade == .red)
    }

    @Test func ipv6IsNeverRed() {
        let clean = PingStats(samples: [15, 15])
        #expect(g.ipv6(hasGlobalAddress: true, udpV6: clean).grade == .green)
        #expect(g.ipv6(hasGlobalAddress: false, udpV6: nil).grade == .amber)
        #expect(g.ipv6(hasGlobalAddress: true, udpV6: PingStats(samples: [nil])).grade == .amber)
    }

    @Test func speed() {
        let fine = SpeedMeasurement(downMbps: 140, upMbps: 130, idleMedianMs: 12, loadedDownMedianMs: 20, loadedUpMedianMs: 15)
        #expect(g.speed(fine).grade == .green)
        let bloat = SpeedMeasurement(downMbps: 150, upMbps: 150, idleMedianMs: 12, loadedDownMedianMs: 50, loadedUpMedianMs: 30)
        #expect(g.speed(bloat).grade == .amber)
        #expect(g.speed(bloat).findings.first == .speedBloatMild)
        let bad = SpeedMeasurement(downMbps: 150, upMbps: 150, idleMedianMs: 12, loadedDownMedianMs: 60, loadedUpMedianMs: 30)
        #expect(g.speed(bad).grade == .red)
        let slow = SpeedMeasurement(downMbps: 20, upMbps: 5, idleMedianMs: 12, loadedDownMedianMs: 14, loadedUpMedianMs: 14)
        #expect(g.speed(slow).findings.first == .speedTooSlow)
        let limited = SpeedMeasurement(downMbps: nil, upMbps: nil, idleMedianMs: 12, loadedDownMedianMs: nil, loadedUpMedianMs: nil, rateLimited: true)
        #expect(g.speed(limited).grade == .unknown)
        #expect(g.speed(nil).grade == .unknown)
        let noBaseline = SpeedMeasurement(downMbps: 140, upMbps: 130, idleMedianMs: nil, loadedDownMedianMs: 20, loadedUpMedianMs: 15)
        #expect(g.speed(noBaseline).grade != .green)   // can't vouch for latency under load
    }

    @Test func lineFree() {
        #expect(g.lineFree(idleMedianMs: 13, bestRecentMs: 12).grade == .green)
        #expect(g.lineFree(idleMedianMs: 30, bestRecentMs: 12).grade == .amber)
        #expect(g.lineFree(idleMedianMs: 45, bestRecentMs: 12).grade == .red)
        #expect(g.lineFree(idleMedianMs: 45, bestRecentMs: nil).grade == .green)
        #expect(g.lineFree(idleMedianMs: nil, bestRecentMs: 12).grade == .unknown)
    }

    @Test func mac() {
        let ready = MacState(awdlUp: false, lowPowerMode: false, onBattery: false, batteryPercent: 90, thermal: .nominal, cpuPercent: 10)
        #expect(g.mac(ready).grade == .green)
        var s = ready; s.awdlUp = true
        #expect(g.mac(s).grade == .amber && g.mac(s).findings.first == .awdlOn)
        s = ready; s.lowPowerMode = true
        #expect(g.mac(s).grade == .red)
        s = ready; s.onBattery = true; s.batteryPercent = 30
        #expect(g.mac(s).findings.contains(.batteryLow))
        s = ready; s.thermal = .serious
        #expect(g.mac(s).grade == .red)
        s = ready; s.lowPowerMode = true; s.awdlUp = true
        #expect(g.mac(s).findings == [.lowPowerOn, .awdlOn])   // worst first
    }

    @Test func appsAndChecklist() {
        #expect(g.apps(noisy: [], timeMachineRunning: false).grade == .green)
        #expect(g.apps(noisy: ["Zoom"], timeMachineRunning: false).grade == .amber)
        #expect(g.apps(noisy: [], timeMachineRunning: true).findings == [.timeMachineRunning])
        #expect(g.checklist([.init(key: "a", done: true)]).grade == .green)
        #expect(g.checklist([.init(key: "a", done: true), .init(key: "b", done: false)]).grade == .amber)
    }
}

@Suite struct SpeedRunTests {
    @Test func rateLimitedBodyIsInvalid() {
        // Cloudflare's 429: a 1-byte body in 0.05 s would otherwise read as a perfect run.
        let fake = Transfer(status: 429, bytesExpected: 25_000_000, bytesMoved: 1, seconds: 0.05, cutByTimeLimit: false)
        #expect(!fake.isValid)
        #expect(fake.isRateLimited)
        #expect(SpeedRun.mbps([fake, fake], windowSeconds: 10) == nil)
        #expect(SpeedRun.shouldFallBack([fake]))
    }

    @Test func shortBodyIsInvalid() {
        #expect(!Transfer(status: 200, bytesExpected: 25_000_000, bytesMoved: 1, seconds: 0.05, cutByTimeLimit: false).isValid)
        #expect(!Transfer(status: 200, bytesExpected: 25_000_000, bytesMoved: 20_000_000, seconds: 2, cutByTimeLimit: false).isValid)
        #expect(Transfer(status: 200, bytesExpected: 25_000_000, bytesMoved: 25_000_000, seconds: 2, cutByTimeLimit: false).isValid)
    }

    @Test func timeLimitedTransferCounts() {
        #expect(Transfer(status: 200, bytesExpected: 1_000_000_000, bytesMoved: 180_000_000, seconds: 10, cutByTimeLimit: true).isValid)
        #expect(!Transfer(status: 200, bytesExpected: nil, bytesMoved: 500, seconds: 10, cutByTimeLimit: true).isValid)
    }

    @Test func throughputUsesTheWindow() {
        let t = Transfer(status: 200, bytesExpected: 25_000_000, bytesMoved: 25_000_000, seconds: 2, cutByTimeLimit: false)
        // 4 × 25 MB in a 10 s window = 80 Mbps (not 4 × 100 Mbps per stream).
        #expect(SpeedRun.mbps([t, t, t, t], windowSeconds: 10) == 80)
        #expect(!SpeedRun.shouldFallBack([t]))
    }

    @Test func providersUseAllowedHostsOnly() {
        for p in SpeedProvider.allCases {
            #expect(Endpoints.allHosts.contains(p.downloadURL(bytes: 1).host!))
            if let up = p.uploadURL { #expect(Endpoints.allHosts.contains(up.host!)) }
        }
    }
}

@Suite struct VerdictTests {
    @Test func allGreenIsReady() {
        let r = CheckID.allCases.map { CheckResult(id: $0, grade: .green, findings: []) }
        #expect(Verdict(results: r).level == .ready)
        #expect(Verdict(results: r).problems.isEmpty)
    }

    @Test func redWinsAndSortsFirst() {
        let r = [CheckResult(id: .connection, grade: .amber, findings: [.wifi6GHz]),
                 CheckResult(id: .hop, grade: .red, findings: [.hopPausing]),
                 CheckResult(id: .internet, grade: .green, findings: []),
                 CheckResult(id: .udp, grade: .green, findings: [])]
        let v = Verdict(results: r)
        #expect(v.level == .notReady)
        #expect(v.problems.map(\.id) == [.hop, .connection])
    }

    @Test func unknownEssentialIsIncomplete() {
        let r = [CheckResult(id: .connection, grade: .green, findings: []), .notMeasured(.internet)]
        #expect(Verdict(results: r).level == .incomplete)
    }

    @Test func unknownExtraIsWarning() {
        let r = Verdict.essential.map { CheckResult(id: $0, grade: .green, findings: []) } + [.notMeasured(.speed)]
        #expect(Verdict(results: r).level == .warning)
    }

    @Test func nothingIsIncomplete() {
        #expect(Verdict(results: []).level == .incomplete)
    }
}

@Suite struct LiveClassifierTests {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test func routerSpikeIsMacWiFi() {
        var c = LiveClassifier(spikeMs: 40)
        let e = c.classify(LiveTick(at: t0, routerMs: .some(73), serverMs: .some(90)))
        #expect(e?.layer == .macWiFi && e?.kind == .spike)
    }

    @Test func serverOnlySpikeIsInternet() {
        var c = LiveClassifier(spikeMs: 40)
        let e = c.classify(LiveTick(at: t0, routerMs: .some(3), serverMs: .some(80)))
        #expect(e?.layer == .internet && e?.value == "80 ms")
    }

    @Test func lossIsReported() {
        var c = LiveClassifier(spikeMs: 40)
        #expect(c.classify(LiveTick(at: t0, routerMs: .some(3), serverMs: .some(nil)))?.kind == .loss)
    }

    @Test func noBlameWithoutARouterReading() {
        var c = LiveClassifier(spikeMs: 40)
        #expect(c.classify(LiveTick(at: t0, routerMs: .none, serverMs: .some(80))) == nil)
    }

    @Test func quietWindowDeduplicates() {
        var c = LiveClassifier(spikeMs: 40)
        #expect(c.classify(LiveTick(at: t0, routerMs: .some(3), serverMs: .some(80))) != nil)
        #expect(c.classify(LiveTick(at: t0.addingTimeInterval(4), routerMs: .some(3), serverMs: .some(80))) == nil)
        #expect(c.classify(LiveTick(at: t0.addingTimeInterval(12), routerMs: .some(3), serverMs: .some(80))) != nil)
        // A different layer is not muted by the internet one.
        #expect(c.classify(LiveTick(at: t0.addingTimeInterval(13), routerMs: .some(70), serverMs: .some(80)))?.layer == .macWiFi)
    }

    @Test func calmTickIsQuiet() {
        var c = LiveClassifier(spikeMs: 40)
        #expect(c.classify(LiveTick(at: t0, routerMs: .some(3), serverMs: .some(18))) == nil)
    }

    @Test func summaryCounts() {
        let s = SessionSummary(start: t0, end: t0, events: [
            LiveEvent(at: t0, kind: .spike, layer: .internet),
            LiveEvent(at: t0, kind: .loss, layer: .internet),
            LiveEvent(at: t0, kind: .spike, layer: .macWiFi)])
        #expect(s.countByLayer[.internet] == 2 && s.countByLayer[.macWiFi] == 1)
    }
}

@Suite struct HistoryTests {
    func tempDir() -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    @Test func roundTripNewestFirst() throws {
        let store = HistoryStore(directory: tempDir())
        let now = Date()
        try store.append(.check(CheckRecord(at: now.addingTimeInterval(-60), verdict: .ready, results: [])))
        try store.append(.check(CheckRecord(at: now, verdict: .warning, results: [])))
        let all = store.load(now: now)
        #expect(all.count == 2)
        if case .check(let first) = all[0] { #expect(first.verdict == .warning) } else { Issue.record("not a check") }
    }

    @Test func pruneDropsOld() throws {
        let store = HistoryStore(directory: tempDir(), keepDays: 90)
        let now = Date()
        try store.append(.check(CheckRecord(at: now.addingTimeInterval(-100 * 86_400), verdict: .ready, results: [])))
        try store.append(.check(CheckRecord(at: now, verdict: .ready, results: [])))
        #expect(store.load(now: now).count == 1)
        try store.prune(now: now)
        let lines = try String(contentsOf: store.fileURL, encoding: .utf8).split(separator: "\n")
        #expect(lines.count == 1)
    }

    @Test func corruptLineIsSkipped() throws {
        let store = HistoryStore(directory: tempDir())
        try store.append(.check(CheckRecord(at: Date(), verdict: .ready, results: [])))
        let h = try FileHandle(forWritingTo: store.fileURL); try h.seekToEnd()
        try h.write(contentsOf: Data("{not json\n".utf8)); try h.close()
        #expect(store.load().count == 1)
    }

    @Test func deleteAll() throws {
        let store = HistoryStore(directory: tempDir())
        try store.append(.check(CheckRecord(at: Date(), verdict: .ready, results: [])))
        try store.deleteAll()
        #expect(store.load().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: store.fileURL.path))
    }

    @Test func csvEscapes() {
        #expect(HistoryCSV.escape("a,b") == "\"a,b\"")
        #expect(HistoryCSV.escape("say \"hi\"") == "\"say \"\"hi\"\"\"")
        #expect(HistoryCSV.escape("plain") == "plain")
        let csv = HistoryCSV.checks([CheckRecord(at: Date(timeIntervalSince1970: 0), verdict: .ready,
                                                 results: [CheckResult(id: .hop, grade: .green, findings: [.hopSteady])])])
        #expect(csv.contains("1970-01-01T00:00:00Z,ready,,,green:hopSteady"))
    }
}

@Suite struct DNSProbeTests {
    @Test func queryShape() {
        let q = DNSProbe.query(id: 0xBEEF)
        #expect(q.prefix(2) == Data([0xBE, 0xEF]))
        #expect(q.count == 12 + 13 + 4)   // header + "\x07example\x03com\x00" + type/class
    }

    @Test func matchesOnlyItsResponse() {
        var r = DNSProbe.query(id: 7); r[2] |= 0x80
        #expect(DNSProbe.isResponse(r, to: 7))
        #expect(!DNSProbe.isResponse(r, to: 8))
        #expect(!DNSProbe.isResponse(DNSProbe.query(id: 7), to: 7))   // a query, not a response
        #expect(!DNSProbe.isResponse(Data([0, 7]), to: 7))
    }
}

@Suite struct ReviewRegressionTests {
    @Test func absentEssentialChecksAreIncomplete() {
        // Only the connection was checked: hop, internet and UDP never ran.
        #expect(Verdict(results: [CheckResult(id: .connection, grade: .green, findings: [.ethernet])]).level == .incomplete)
    }

    @Test func missingUploadIsNotAPass() {
        let downOnly = SpeedMeasurement(downMbps: 140, upMbps: nil, idleMedianMs: 12, loadedDownMedianMs: 18, loadedUpMedianMs: nil)
        #expect(Grader().speed(downOnly).grade != .green)
    }

    @Test func failedAppendKeepsExistingHistory() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = HistoryStore(directory: dir)
        try store.append(.check(CheckRecord(at: Date(), verdict: .ready, results: [])))
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: store.fileURL.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: store.fileURL.path) }
        #expect(throws: (any Error).self) { try store.append(.check(CheckRecord(at: Date(), verdict: .warning, results: []))) }
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: store.fileURL.path)
        #expect(store.load().count == 1)
    }
}

@Suite struct GuardScriptTests {
    private func runBash(_ args: [String]) throws -> (Int32, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = args
        let out = Pipe(); p.standardOutput = out; p.standardError = out
        try p.run(); p.waitUntilExit()
        return (p.terminationStatus, String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
    }

    @Test func parsesWithMacOSBash() throws {
        #expect(try runBash(["-n", "-c", GuardScript.source]).0 == 0)
    }

    @Test func avoidsBash4Features() {
        // /bin/bash on macOS is 3.2.
        for feature in ["BASHPID", "declare -A", "mapfile", "readarray", "${var,,}", "|&"] {
            #expect(!GuardScript.source.contains(feature), "uses \(feature)")
        }
    }

    @Test func refusesToRunWithoutRoot() throws {
        let (status, output) = try runBash(["-c", GuardScript.source, "game-mode-guard", "/tmp/x"])
        #expect(status == 1 && output.contains("must run as root"))
    }

    @Test func restoresEverythingItChanges() {
        let s = GuardScript.source
        #expect(s.contains("ifconfig awdl0 up"))
        #expect(s.contains("pmset -b lowpowermode 1") && s.contains("pmset -c lowpowermode 1"))
        #expect(s.contains("tmutil enable"))
        #expect(s.contains("trap restore EXIT"))
    }

    @Test func onlyAcceptsTheGameReadyFlag() {
        #expect(GuardScript.source.contains(#"Application\ Support/Game\ Ready/gamemode\.on$"#))
    }
}

@Suite struct HistoryCompatibilityTests {
    @Test func recordWithoutIdleStillDecodes() throws {
        let json = #"{"check":{"_0":{"id":"7C2F0D1E-9E1B-4F6B-9C8E-2B7D5A1E3F40","at":"2026-10-01T20:00:00Z","verdict":"ready","results":[]}}}"#
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        let entry = try d.decode(HistoryEntry.self, from: Data(json.utf8))
        if case .check(let c) = entry { #expect(c.idleMedianMs == nil) } else { Issue.record("not a check") }
    }
}

/// Privacy promise: the app talks only to the hosts in `Endpoints`. Any other host literal
/// in the sources fails this test.
@Suite struct EndpointGuardTests {
    private var repo: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()   // GameReadyCoreTests
            .deletingLastPathComponent().deletingLastPathComponent()   // Packages/GameReadyCore
            .deletingLastPathComponent().deletingLastPathComponent()   // repo root
    }

    private func swiftFiles() -> [URL] {
        let roots = ["App/Sources", "Packages/GameReadyCore/Sources"].map { repo.appendingPathComponent($0) }
        return roots.flatMap { root in
            (FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? [])
                .filter { $0.pathExtension == "swift" }
        }
    }

    @Test func sourcesExist() { #expect(swiftFiles().count > 10) }

    @Test func onlyAllowedHosts() throws {
        // URLs and bare host names / IPv4 addresses inside string literals.
        let url = try Regex(#"https?://([A-Za-z0-9.-]+)"#)
        let host = try Regex(#""((?:[a-z0-9-]+\.)+(?:com|net|org|io|de|uk|co))""#)
        let ipv4 = try Regex(#""(\d{1,3}(?:\.\d{1,3}){3})""#)
        var offenders = [String]()
        for file in swiftFiles() {
            let text = try String(contentsOf: file, encoding: .utf8)
            for regex in [url, host, ipv4] {
                for match in text.matches(of: regex) {
                    guard let h = match.output[1].substring.map(String.init) else { continue }
                    if !Endpoints.allHosts.contains(h) && !h.hasPrefix("com.apple.") && !h.hasPrefix("io.github.")
                        && !Self.bundleIDs.contains(h) {
                        offenders.append("\(file.lastPathComponent): \(h)")
                    }
                }
            }
        }
        #expect(offenders.isEmpty, "hosts not in Endpoints: \(offenders)")
    }

    /// Reverse-DNS bundle identifiers look like hosts but are never contacted.
    static let bundleIDs: Set<String> = [
        "us.zoom.xos", "com.microsoft.teams2", "com.microsoft.OneDrive", "com.getdropbox.dropbox",
        "com.google.drivefs", "com.valvesoftware.steam", "com.google.Chrome", "com.microsoft.edgemac",
    ]
}

@Suite struct GradeCodingTests {
    @Test func encodesAsWord() throws {
        #expect(String(decoding: try JSONEncoder().encode([Grade.amber]), as: UTF8.self) == #"["amber"]"#)
        #expect(try JSONDecoder().decode([Grade].self, from: Data(#"["red","unknown"]"#.utf8)) == [.red, .unknown])
        #expect(throws: (any Error).self) { try JSONDecoder().decode([Grade].self, from: Data(#"["purple"]"#.utf8)) }
    }

    @Test func noNegativeRiseInDetails() {
        let m = SpeedMeasurement(downMbps: 100, upMbps: 100, idleMedianMs: 12, loadedDownMedianMs: 11.6, loadedUpMedianMs: 11)
        #expect(Grader().speed(m).details["rise"] == "+0 ms")
    }
}

@Suite struct GuardScriptReviewTests {
    let s = GuardScript.source

    @Test func loopRevalidatesTheFlagEveryTime() {
        // A flag swapped for a symlink (or re-owned) after start must stop the guard.
        #expect(s.contains(#"while flag_ok; do"#))
        #expect(s.contains(#"[[ -f "$FLAG" && ! -L "$FLAG" ]]"#))
    }

    @Test func restoresAirDropOnlyIfItWasUp() {
        #expect(s.contains("awdl_was_up"))
        #expect(s.contains(#"[[ "$awdl_was_up" == "1" ]] && ifconfig awdl0 up"#))
    }

    @Test func lowPowerIsPerPowerSource() {
        #expect(!s.contains("pmset -a lowpowermode"))
        #expect(s.contains("pmset -b lowpowermode") && s.contains("pmset -c lowpowermode"))
    }
}

@Suite struct ReviewThreeTests {
    let g = Grader()

    @Test func unreachableGameServerIsNotAPass() {
        let cf = PingStats(samples: Array(repeating: 12.0, count: 50))
        let dead = PingStats(samples: Array(repeating: nil, count: 50))
        let r = g.internet(["Cloudflare": cf, "Game server": dead])
        #expect(r.grade != .green)
        #expect(r.findings.contains(.notMeasured))
        // ...and as an essential check it makes the verdict incomplete, not ready.
        let all = Verdict.essential.filter { $0 != .internet }.map { CheckResult(id: $0, grade: .green, findings: []) } + [r]
        #expect(Verdict(results: all).level == .incomplete)
    }

    @Test func missingLinkRateIsNotAPass() {
        #expect(g.wifi(WiFiLink(band: .ghz6, rssi: -50, txRateMbps: nil), kind: .wifi).grade != .green)
    }

    @Test func guardTakesAnAtomicLockBeforeTouchingSettings() {
        let s = GuardScript.source
        guard let lock = s.range(of: #"mkdir "$LOCK""#), let capture = s.range(of: "awdl_was_up=") else {
            Issue.record("no atomic lock"); return
        }
        #expect(lock.lowerBound < capture.lowerBound)
        #expect(s.contains(#"rmdir "$LOCK""#))
    }
}

@Suite struct PlatformTests {
    @Test func everyPlatformOpensAnAllowedHTTPSPage() {
        for p in GamingPlatform.allCases {
            #expect(p.playURL.scheme == "https")
            #expect(Endpoints.allHosts.contains(p.playURL.host!), "\(p) host not in Endpoints")
        }
        #expect(GamingPlatform.xboxCloud.usesBetterXcloud && !GamingPlatform.geforceNow.usesBetterXcloud)
    }
}

@Suite struct SharingSettingTests {
    @Test func applyAndRestoreArguments() {
        let a = SharingSetting.airDrop
        #expect(a.applyArguments == ["write", "com.apple.sharingd", "DiscoverableMode", "-string", "Off"])
        #expect(a.restoreArguments(original: "Contacts Only") == ["write", "com.apple.sharingd", "DiscoverableMode", "-string", "Contacts Only"])
        // Absent before = the macOS default → restore by deleting, never by guessing a value.
        #expect(a.restoreArguments(original: nil) == ["delete", "com.apple.sharingd", "DiscoverableMode"])
        let h = SharingSetting.handoffAdvertise
        #expect(h.applyArguments.first == "-currentHost")
        #expect(h.restoreArguments(original: "1") == ["-currentHost", "write", h.domain, h.key, "-bool", "true"])
    }

    @Test func boolsCompareAcrossReadAndWriteForms() {
        #expect(SharingSetting.universalControl.isGameValue("1"))
        #expect(!SharingSetting.universalControl.isGameValue("0"))
        #expect(SharingSetting.handoffAdvertise.isGameValue("0"))
        #expect(!SharingSetting.airDrop.isGameValue(nil))
    }

    @Test func restorePlanSurvivesDisk() throws {
        let plan = RestorePlan(sharing: [.airDrop: "Contacts Only", .universalControl: nil],
                               betterXcloud: [BetterXcloud.Key.maxBitrate: .number(5_000_000), BetterXcloud.Key.preferIPv6: nil])
        let back = try JSONDecoder().decode(RestorePlan.self, from: JSONEncoder().encode(plan))
        #expect(back == plan)
        #expect(back.sharing[.universalControl]! == nil)   // absent stays absent
    }
}

@Suite struct BetterXcloudTests {
    @Test func parse() {
        #expect(BetterXcloud.parse(nil) == nil)
        #expect(BetterXcloud.parse("null") == nil)
        #expect(BetterXcloud.parse("[1]") == nil)
        let s = BetterXcloud.parse(#"{"server.ipv6.prefer":true,"stream.video.maxBitrate":0,"server.region":"UkSouth"}"#)
        #expect(s?["server.ipv6.prefer"] == .bool(true))
        #expect(s?["stream.video.maxBitrate"] == .number(0))
    }

    @Test func snapshotOnlyHoldsWhatThePresetChanges() {
        let current: [String: JSONValue] = ["server.ipv6.prefer": .bool(true), "stream.video.maxBitrate": .number(5_120_000),
                                            "server.region": .string("UkSouth")]
        let snap = BetterXcloud.snapshot(of: current)
        #expect(snap.keys.sorted() == ["stream.video.codecProfile", "stream.video.maxBitrate"])
        #expect(snap["stream.video.maxBitrate"]! == .number(5_120_000))
        #expect(snap["stream.video.codecProfile"]! == nil)        // absent before → delete on undo
        #expect(snap["server.region"] == nil)                     // region is never touched
    }

    @Test func presetStatus() {
        var s: [String: JSONValue] = ["server.ipv6.prefer": .bool(true), "stream.video.maxBitrate": .number(0),
                                      "stream.video.codecProfile": .string("high")]
        #expect(BetterXcloud.matchesPreset(s) && BetterXcloud.qualityDone(s) && BetterXcloud.ipv6Done(s))
        s["stream.video.codecProfile"] = .string("normal")
        #expect(!BetterXcloud.matchesPreset(s) && !BetterXcloud.qualityDone(s))
    }

    @Test func writeScriptCarriesValuesAsJSONNotCode() throws {
        let js = try BetterXcloud.writeScript(["stream.video.codecProfile": .string("x');alert(1);//"), "server.ipv6.prefer": nil])
        // The hostile string ends up inside a JSON string literal, escaped; the removal is listed by name.
        #expect(js.contains(#""stream.video.codecProfile":"x');alert(1);\/\/""#) || js.contains(#""stream.video.codecProfile":"x');alert(1);//""#))
        #expect(js.contains(#"var r=["server.ipv6.prefer"]"#))
        #expect(js.hasPrefix("(function(){") && js.hasSuffix("})()"))
    }

    @Test func writeScriptRunsInJavaScriptCore() throws {
        // Execute the generated script against a fake localStorage and check the result.
        let js = try BetterXcloud.writeScript(["stream.video.maxBitrate": .number(0), "server.ipv6.prefer": nil])
        let harness = """
        var store={'BetterXcloud':'{"server.ipv6.prefer":true,"server.region":"UkSouth"}'};
        var localStorage={getItem:function(k){return k in store?store[k]:null},setItem:function(k,v){store[k]=String(v)}};
        \(js)
        """
        let out = try runJS(harness)
        let saved = BetterXcloud.parse(out)
        #expect(saved?["stream.video.maxBitrate"] == .number(0))
        #expect(saved?["server.ipv6.prefer"] == nil)
        #expect(saved?["server.region"] == .string("UkSouth"))
    }

    private func runJS(_ source: String) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-l", "JavaScript", "-e", source]
        let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
        try p.run(); p.waitUntilExit()
        return String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@Suite struct BrowserScriptTests {
    private func compiles(_ source: String) throws -> Bool {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".applescript")
        try source.write(to: url, atomically: true, encoding: .utf8)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osacompile")
        p.arguments = ["-o", url.deletingPathExtension().appendingPathExtension("scpt").path, url.path]
        p.standardError = Pipe(); p.standardOutput = Pipe()
        try p.run(); p.waitUntilExit()
        return p.terminationStatus == 0
    }

    @Test func compilesForEveryBrowser() throws {
        let js = try BetterXcloud.writeScript(BetterXcloud.preset.mapValues { Optional($0) })
        // AppleScript takes a browser's commands from the installed app, so only installed ones can compile.
        let browsers = [("Google Chrome", "com.google.Chrome", false), ("Safari", "com.apple.Safari", true),
                        ("Microsoft Edge", "com.microsoft.edgemac", false)]
        var compiled = 0
        for (name, id, safari) in browsers where FileManager.default.fileExists(atPath: "/Applications/\(name).app")
            || FileManager.default.fileExists(atPath: "/System/Volumes/Preboot/Cryptexes/App/System/Applications/\(name).app") {
            #expect(try compiles(BrowserScripts.run(js, bundleID: id, safari: safari)), "\(name)")
            compiled += 1
        }
        #expect(compiled >= 1)
    }

    @Test func hostileTextStaysInsideTheString() throws {
        // AppleScript must read the literal back as exactly the original text: nothing runs.
        let hostile = #"x" & (do shell script "id") & "\"#
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", "return " + BrowserScripts.appleScriptString(hostile)]
        let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
        try p.run(); p.waitUntilExit()
        let back = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        #expect(back.trimmingCharacters(in: .newlines) == hostile)
        #expect(try compiles(BrowserScripts.run(hostile, bundleID: "com.apple.Safari", safari: true)))
    }
}

/// Exercises the real `defaults` tool on a throwaway domain, never a real setting.
@Suite(.serialized) struct SharingRoundTripTests {
    let domain = "io.github.caputodavide93.gameready.tests"

    private func defaults(_ args: [String]) throws -> (Int32, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        p.arguments = args
        let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
        try p.run(); p.waitUntilExit()
        return (p.terminationStatus, String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines))
    }

    @Test func absentKeyIsRestoredByDeleting() throws {
        let s = SharingSetting(domain: domain, key: "Mode", currentHost: false, kind: .string, gameValue: "Off", reloadProcess: nil)
        _ = try defaults(["delete", domain])
        #expect(try defaults(s.readArguments).0 != 0)           // absent to begin with
        _ = try defaults(s.applyArguments)
        #expect(s.isGameValue(try defaults(s.readArguments).1))
        _ = try defaults(s.restoreArguments(original: nil))
        #expect(try defaults(s.readArguments).0 != 0)           // absent again
        _ = try defaults(["delete", domain])
    }

    @Test func boolValueRoundTrips() throws {
        let s = SharingSetting(domain: domain, key: "Allowed", currentHost: false, kind: .bool, gameValue: "false", reloadProcess: nil)
        _ = try defaults(["write", domain, "Allowed", "-bool", "true"])
        let original = try defaults(s.readArguments).1          // "1"
        _ = try defaults(s.applyArguments)
        #expect(try defaults(s.readArguments).1 == "0")
        _ = try defaults(s.restoreArguments(original: original))
        #expect(try defaults(s.readArguments).1 == "1")
        _ = try defaults(["delete", domain])
    }
}

@Suite struct ReviewFourTests {
    @Test func onlyAGenuineMissingKeyCountsAsAbsent() {
        #expect(SharingSetting.classifyRead(status: 0, output: "Off\n", error: "") == .value("Off"))
        #expect(SharingSetting.classifyRead(status: 1, output: "",
            error: "The domain/default pair of (com.apple.sharingd, DiscoverableMode) does not exist") == .absent)
        #expect(SharingSetting.classifyRead(status: 1, output: "", error: "Domain com.apple.universalcontrol not found") == .absent)
        #expect(SharingSetting.classifyRead(status: 1, output: "", error: "Could not find key 'X' in domain 'Y'") == .absent)
        // Anything else is an error: never recorded as "absent" (which would delete a real value on restore).
        #expect(SharingSetting.classifyRead(status: 1, output: "", error: "Permission denied") == .failed)
        #expect(SharingSetting.classifyRead(status: -1, output: "", error: "") == .failed)
    }

    @Test func planRemembersTheBrowser() throws {
        let plan = RestorePlan(sharing: [:], betterXcloud: ["k": .bool(true)], betterXcloudBrowser: "com.apple.Safari")
        #expect(try JSONDecoder().decode(RestorePlan.self, from: JSONEncoder().encode(plan)).betterXcloudBrowser == "com.apple.Safari")
    }

    @Test func scriptRefusesPagesThatAreNotXbox() throws {
        func run(host: String) throws -> String {
            let js = BrowserScripts.guarded("'ran'")
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = ["-l", "JavaScript", "-e", "var location={hostname:'\(host)'};\n" + js]
            let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
            try p.run(); p.waitUntilExit()
            return String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        #expect(try run(host: "www.xbox.com") == "ran")
        #expect(try run(host: "xbox.com") == "ran")
        #expect(try run(host: "attacker.example") == BrowserScripts.notXboxMarker)
        #expect(try run(host: "xbox.com.attacker.example") == BrowserScripts.notXboxMarker)
        #expect(try run(host: "notxbox.com") == BrowserScripts.notXboxMarker)
    }
}

@Suite struct ReadinessTests {
    func result(_ id: CheckID, _ g: Grade, _ f: [Finding] = []) -> CheckResult { CheckResult(id: id, grade: g, findings: f) }

    @Test func scoreWeightsAndHalves() {
        let all = CheckID.allCases.map { result($0, .green) }
        #expect(ReadinessScore.score(all) == 100)
        #expect(ReadinessScore.score([]) == nil)
        // connection (2) amber → loses 1 of 14.5 → 93
        var r = all; r[0] = result(.connection, .amber)
        #expect(ReadinessScore.score(r) == 93)
        r[0] = result(.connection, .red)
        #expect(ReadinessScore.score(r) == 86)
        #expect(ReadinessScore.weights.keys.count == CheckID.allCases.count)   // every check has a weight
    }

    @Test func gameModeOffIsAlwaysAFix() {
        let c = FixPlanner.Context(gameModeOn: false, betterXcloudNeedsTuning: false, betterXcloudBlocked: false, noisyApps: [])
        #expect(FixPlanner.plan([], c).fixes == [.gameMode])
        var on = c; on.gameModeOn = true
        #expect(FixPlanner.plan([], on).fixes.isEmpty)
    }

    @Test func appsAreSortedAndOnlyBeforeGameMode() {
        let c = FixPlanner.Context(gameModeOn: false, betterXcloudNeedsTuning: true, betterXcloudBlocked: false, noisyApps: ["Zoom", "Photos"])
        #expect(FixPlanner.plan([], c).fixes == [.gameMode, .betterXcloud, .quitApps(["Photos", "Zoom"])])
    }

    @Test func adviceFromFindings() {
        let c = FixPlanner.Context(gameModeOn: true, betterXcloudNeedsTuning: false, betterXcloudBlocked: true, noisyApps: [])
        let p = FixPlanner.plan([result(.connection, .amber, [.wifi6GHz]), result(.speed, .amber, [.speedBloatMild]),
                                 result(.mac, .amber, [.onBattery])], c)
        #expect(p.advice == [.useCable, .plugIn, .turnOnSQM, .setUpBetterXcloud])
    }

    @Test func basicStates() {
        let green = Verdict(results: CheckID.allCases.map { result($0, .green) })
        #expect(BasicState.from(verdict: nil, plan: FixPlan(fixes: [], advice: [])) == .unchecked)
        #expect(BasicState.from(verdict: green, plan: FixPlan(fixes: [.gameMode], advice: [])) == .canFix)
        #expect(BasicState.from(verdict: green, plan: FixPlan(fixes: [], advice: [])) == .ready)
        #expect(BasicState.from(verdict: green, plan: FixPlan(fixes: [], advice: [.useCable])) == .readyWithAdvice)
        let red = Verdict(results: CheckID.allCases.map { result($0, $0 == .udp ? .red : .green) })
        #expect(BasicState.from(verdict: red, plan: FixPlan(fixes: [], advice: [.slowLine])) == .problem)
    }
}

@Suite struct ReviewSevenTests {
    func r(_ id: CheckID, _ g: Grade, _ f: [Finding] = []) -> CheckResult { CheckResult(id: id, grade: g, findings: f) }

    @Test func unfixableFailureIsNotHiddenByAFix() {
        // UDP is losing packets (nothing Game Ready can fix) while Game Mode is also off.
        let results = CheckID.allCases.map { $0 == .udp ? r(.udp, .red, [.udpLossy]) : r($0, .green) }
        let v = Verdict(results: results)
        #expect(BasicState.from(verdict: v, plan: FixPlan(fixes: [.gameMode], advice: [.slowLine])) == .problemButCanFix)
    }

    @Test func fixableFailureStaysCanFix() {
        // A pausing Wi-Fi hop with AirDrop on is exactly what Game Mode fixes.
        let results = CheckID.allCases.map { $0 == .hop ? r(.hop, .red, [.hopPausing]) : $0 == .mac ? r(.mac, .amber, [.awdlOn]) : r($0, .green) }
        #expect(BasicState.from(verdict: Verdict(results: results), plan: FixPlan(fixes: [.gameMode], advice: [])) == .canFix)
    }

    @Test func noScoreUntilEveryCheckIsIn() {
        // Only two passing results so far: not a 100.
        #expect(ReadinessScore.score([r(.connection, .green), r(.wifi, .green)], complete: false) == nil)
        #expect(ReadinessScore.score(CheckID.allCases.map { r($0, .green) }, complete: true) == 100)
    }
}

@Suite struct ReviewEightTests {
    func r(_ id: CheckID, _ g: Grade, _ f: [Finding] = []) -> CheckResult { CheckResult(id: id, grade: g, findings: f) }
    let on = FixPlanner.Context(gameModeOn: true, betterXcloudNeedsTuning: false, betterXcloudBlocked: false, noisyApps: [])

    @Test func warningWithNoMappedAdviceIsNeverPlainReady() {
        // Game Mode on, internet a bit slow: no fix, no specific advice. Must not read "all good".
        let results = CheckID.allCases.map { $0 == .internet ? r(.internet, .amber, [.internetSlowish]) : r($0, .green) }
        let plan = FixPlanner.plan(results, on)
        #expect(plan.advice == [.seeAdvanced])
        #expect(BasicState.from(verdict: Verdict(results: results), plan: plan) == .readyWithAdvice)
    }

    @Test func allGreenStaysReady() {
        let results = CheckID.allCases.map { r($0, .green) }
        let plan = FixPlanner.plan(results, on)
        #expect(plan.isEmpty)
        #expect(BasicState.from(verdict: Verdict(results: results), plan: plan) == .ready)
    }

    @Test func warningCoveredByAFixNeedsNoExtraAdvice() {
        // AirDrop on with Game Mode off: Game Mode is the answer, nothing generic to add.
        let off = FixPlanner.Context(gameModeOn: false, betterXcloudNeedsTuning: false, betterXcloudBlocked: false, noisyApps: [])
        let results = CheckID.allCases.map { $0 == .mac ? r(.mac, .amber, [.awdlOn]) : r($0, .green) }
        #expect(FixPlanner.plan(results, off).advice.isEmpty)
    }
}

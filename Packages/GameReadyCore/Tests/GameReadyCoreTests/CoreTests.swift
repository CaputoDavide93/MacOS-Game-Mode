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
        #expect(s.contains("pmset -a lowpowermode 1"))
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

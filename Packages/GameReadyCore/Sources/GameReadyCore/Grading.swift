import Foundation

/// Pure grading: measurements in, `CheckResult` out. Every rule is in `Thresholds`.
public struct Grader: Sendable {
    public var t: Thresholds
    public init(_ thresholds: Thresholds = .standard) { t = thresholds }

    private func ms(_ v: Double?) -> String { v.map { String(format: "%.1f ms", $0) } ?? "–" }

    // C1
    public func connection(_ kind: ConnectionKind, band: WiFiBand?) -> CheckResult {
        switch kind {
        case .ethernet: return CheckResult(id: .connection, grade: .green, findings: [.ethernet])
        case .none: return CheckResult(id: .connection, grade: .red, findings: [.notConnected])
        case .other: return CheckResult(id: .connection, grade: .amber, findings: [.notMeasured])
        case .wifi:
            switch band ?? .unknown {
            case .ghz6: return CheckResult(id: .connection, grade: .amber, findings: [.wifi6GHz])
            case .ghz5: return CheckResult(id: .connection, grade: .amber, findings: [.wifi5GHz])
            case .ghz24: return CheckResult(id: .connection, grade: .red, findings: [.wifi24GHz])
            case .unknown: return CheckResult(id: .connection, grade: .unknown, findings: [.wifiUnknown])
            }
        }
    }

    // C2 — only meaningful on Wi-Fi; Ethernet passes.
    public func wifi(_ link: WiFiLink?, kind: ConnectionKind) -> CheckResult {
        if kind == .ethernet { return CheckResult(id: .wifi, grade: .green, findings: [.ethernet]) }
        guard let link, let rssi = link.rssi else { return .notMeasured(.wifi) }
        var details = ["rssi": "\(rssi) dBm"]
        if let c = link.channel { details["channel"] = "\(c)" + (link.widthMHz.map { " (\($0) MHz)" } ?? "") }
        if let r = link.txRateMbps { details["rate"] = String(format: "%.0f Mbps", r) }
        let rate = link.txRateMbps
        if rssi < t.wifiRSSIAmber || (rate.map { $0 < t.wifiRateRedMbps } ?? false) {
            return CheckResult(id: .wifi, grade: .red, findings: [.wifiPoor], details: details)
        }
        if rssi < t.wifiRSSIGreen || (rate.map { $0 < t.wifiRateGreenMbps } ?? false) {
            return CheckResult(id: .wifi, grade: .amber, findings: [.wifiWeak], details: details)
        }
        return CheckResult(id: .wifi, grade: .green, findings: [.wifiStrong], details: details)
    }

    // C3 — the Mac's own hop to the router. Spikes here are the Mac, not the internet.
    public func hop(_ s: PingStats) -> CheckResult {
        guard !s.isEmpty, let max = s.maxMs else { return .notMeasured(.hop) }
        let details = ["avg": ms(s.avgMs), "max": ms(max), "loss": String(format: "%.1f%%", s.lossPercent)]
        if s.lossPercent > 0 { return CheckResult(id: .hop, grade: .red, findings: [.hopLoss], details: details) }
        if max > t.hopMaxAmberMs { return CheckResult(id: .hop, grade: .red, findings: [.hopPausing], details: details) }
        if max > t.hopMaxGreenMs { return CheckResult(id: .hop, grade: .amber, findings: [.hopSpiky], details: details) }
        return CheckResult(id: .hop, grade: .green, findings: [.hopSteady], details: details)
    }

    // C4 — internet: graded on the worse of the targets measured.
    public func internet(_ targets: [String: PingStats]) -> CheckResult {
        let measured = targets.filter { !$0.value.isEmpty }
        guard !measured.isEmpty else { return .notMeasured(.internet) }
        var details = [String: String]()
        var grade = Grade.green
        var findings = [Finding]()
        for (name, s) in measured.sorted(by: { $0.key < $1.key }) {
            details[name] = "\(ms(s.avgMs)) avg, \(ms(s.jitterMs)) jitter, " + String(format: "%.1f%% loss", s.lossPercent)
            let avg = s.avgMs ?? .infinity, jitter = s.jitterMs ?? .infinity
            let g: Grade, f: Finding
            if s.lossPercent > 0 { g = .red; f = .internetLoss }
            else if avg > t.internetAvgAmberMs || jitter > t.internetJitterAmberMs { g = .red; f = .internetPoor }
            else if avg > t.internetAvgGreenMs || jitter > t.internetJitterGreenMs { g = .amber; f = .internetSlowish }
            else { g = .green; f = .internetGood }
            if g > grade { grade = g; findings.insert(f, at: 0) } else if !findings.contains(f) { findings.append(f) }
        }
        return CheckResult(id: .internet, grade: grade, findings: findings, details: details)
    }

    // C5 — UDP, which is what game streams use. Graded on the worse of IPv4/IPv6.
    public func udp(v4: PingStats?, v6: PingStats?) -> CheckResult {
        let runs = [("IPv4", v4), ("IPv6", v6)].compactMap { name, s in s.map { (name, $0) } }
        guard !runs.isEmpty, runs.contains(where: { $0.1.sent > 0 }) else { return .notMeasured(.udp) }
        var details = [String: String]()
        var grade = Grade.green
        var findings = [Finding]()
        for (name, s) in runs {
            details[name] = String(format: "%.1f%% lost", s.lossPercent) + ", p95 \(ms(s.p95Ms))"
            let g: Grade, f: Finding
            if s.isEmpty || s.lossPercent > t.udpLossAmberPercent { g = .red; f = .udpLossy }
            else if s.lossPercent > 0 { g = .amber; f = .udpSomeLoss }
            else if (s.p95Ms ?? .infinity) > t.udpP95GreenMs { g = .amber; f = .udpSlow }
            else { g = .green; f = .udpClean }
            if g > grade { grade = g; findings.insert(f, at: 0) } else if !findings.contains(f) { findings.append(f) }
        }
        return CheckResult(id: .udp, grade: grade, findings: findings, details: details)
    }

    // C6 — IPv6 is a bonus (it can skip carrier-grade NAT), never a failure.
    public func ipv6(hasGlobalAddress: Bool, udpV6: PingStats?) -> CheckResult {
        let works = hasGlobalAddress && (udpV6.map { !$0.isEmpty && $0.lossPercent <= t.udpLossAmberPercent } ?? false)
        return works
            ? CheckResult(id: .ipv6, grade: .green, findings: [.ipv6Ready])
            : CheckResult(id: .ipv6, grade: .amber, findings: [.ipv6Missing])
    }

    // C7
    public func speed(_ m: SpeedMeasurement?) -> CheckResult {
        guard let m else { return .notMeasured(.speed) }
        if m.rateLimited && m.downMbps == nil { return CheckResult(id: .speed, grade: .unknown, findings: [.speedRateLimited]) }
        guard let down = m.downMbps else { return .notMeasured(.speed) }
        var details = ["down": String(format: "%.0f Mbps", down)]
        if let up = m.upMbps { details["up"] = String(format: "%.0f Mbps", up) }
        if let rise = m.loadRiseMs { details["rise"] = String(format: "+%.0f ms", max(0, rise)) }
        var grade = Grade.green
        var findings = [Finding]()
        func add(_ g: Grade, _ f: Finding) {
            if g > grade { grade = g; findings.insert(f, at: 0) } else { findings.append(f) }
        }
        if down < t.downAmberMbps { add(.red, .speedTooSlow) }
        else if down < t.downGreenMbps || (m.upMbps.map { $0 < t.upGreenMbps } ?? false) { add(.amber, .speedSlow) }
        if let rise = m.loadRiseMs {
            if rise > t.loadRiseAmberMs { add(.red, .speedBloatBad) }
            else if rise > t.loadRiseGreenMs { add(.amber, .speedBloatMild) }
        } else {
            add(.unknown, .notMeasured)
        }
        if m.upMbps == nil { add(.unknown, .notMeasured) }   // upload not measured: can't vouch for it
        if m.rateLimited { add(.amber, .speedRateLimited) }
        if findings.isEmpty { findings = [.speedGood] }
        return CheckResult(id: .speed, grade: grade, findings: findings, details: details)
    }

    // C8 — idle latency now vs. the best this Mac has seen recently.
    public func lineFree(idleMedianMs: Double?, bestRecentMs: Double?) -> CheckResult {
        guard let now = idleMedianMs else { return .notMeasured(.lineFree) }
        guard let best = bestRecentMs else {
            return CheckResult(id: .lineFree, grade: .green, findings: [.lineQuiet], details: ["now": ms(now)])
        }
        let rise = now - best
        let details = ["now": ms(now), "usual": ms(best)]
        if rise > t.lineBusyRedMs { return CheckResult(id: .lineFree, grade: .red, findings: [.lineBusy], details: details) }
        if rise > t.lineBusyAmberMs { return CheckResult(id: .lineFree, grade: .amber, findings: [.lineMaybeBusy], details: details) }
        return CheckResult(id: .lineFree, grade: .green, findings: [.lineQuiet], details: details)
    }

    // C9
    public func mac(_ s: MacState) -> CheckResult {
        var grade = Grade.green
        var findings = [Finding]()
        func add(_ g: Grade, _ f: Finding) {
            if g > grade { grade = g; findings.insert(f, at: 0) } else { findings.append(f) }
        }
        if s.lowPowerMode { add(.red, .lowPowerOn) }
        if s.thermal == .serious || s.thermal == .critical { add(.red, .thermalHigh) }
        if let cpu = s.cpuPercent, cpu > t.cpuRedPercent { add(.red, .cpuBusy) }
        if s.awdlUp == true { add(.amber, .awdlOn) }
        if s.onBattery {
            if let pct = s.batteryPercent, pct < t.batteryAmberPercent { add(.amber, .batteryLow) }
            else { add(.amber, .onBattery) }
        }
        if findings.isEmpty { findings = [.macReady] }
        var details = ["thermal": s.thermal.rawValue]
        if let cpu = s.cpuPercent { details["cpu"] = String(format: "%.0f%%", cpu) }
        if let pct = s.batteryPercent { details["battery"] = "\(pct)%" + (s.onBattery ? "" : " (charging)") }
        return CheckResult(id: .mac, grade: grade, findings: findings, details: details)
    }

    // C10 — `noisy` are display names of running apps from the user's list.
    public func apps(noisy: [String], timeMachineRunning: Bool) -> CheckResult {
        var findings = [Finding]()
        if timeMachineRunning { findings.append(.timeMachineRunning) }
        if !noisy.isEmpty { findings.append(.appsNoisy) }
        guard !findings.isEmpty else { return CheckResult(id: .apps, grade: .green, findings: [.appsQuiet]) }
        return CheckResult(id: .apps, grade: .amber, findings: findings,
                           details: noisy.isEmpty ? [:] : ["running": noisy.sorted().joined(separator: ", ")])
    }

    // C11
    public func checklist(_ items: [ChecklistItemState]) -> CheckResult {
        let open = items.filter { !$0.done }
        return open.isEmpty
            ? CheckResult(id: .checklist, grade: .green, findings: [.checklistDone])
            : CheckResult(id: .checklist, grade: .amber, findings: [.checklistOpen],
                          details: ["open": "\(open.count) of \(items.count)"])
    }
}

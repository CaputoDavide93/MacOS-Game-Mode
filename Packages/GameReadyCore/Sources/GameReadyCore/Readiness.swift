import Foundation

/// The number in Advanced's ring: how many checks pass, weighted by how much they matter for
/// a smooth stream. Green counts fully, amber half, red and "couldn't measure" not at all.
/// Deterministic and explainable: the same results always give the same score.
public enum ReadinessScore {
    public static let weights: [CheckID: Double] = [
        .connection: 2, .wifi: 1.5, .hop: 2, .internet: 2, .udp: 2, .ipv6: 0.5,
        .speed: 1.5, .lineFree: 1, .mac: 1, .apps: 0.5, .checklist: 0.5,
    ]

    /// 0–100, or nil when nothing has been checked. While a check is still running
    /// (`complete: false`) there is no score, so a half-finished run can't read as 100.
    public static func score(_ results: [CheckResult], complete: Bool = true) -> Int? {
        guard complete else { return nil }
        var total = 0.0, got = 0.0
        for r in results {
            let w = weights[r.id] ?? 1
            total += w
            switch r.grade {
            case .green: got += w
            case .amber: got += w / 2
            case .red, .unknown: break
            }
        }
        guard total > 0 else { return nil }
        return Int((got / total * 100).rounded())
    }
}

/// What Basic's "Fix & Play" will do for you, and what only you can do.
public enum Fix: Equatable, Sendable, Hashable {
    /// AirDrop radio off, Handoff, Universal Control, Low Power Mode, Time Machine, sleep.
    case gameMode
    /// The Better xCloud preset (needs the browser's one-time permission).
    case betterXcloud
    /// Quit these apps (display names).
    case quitApps([String])
}

public enum Advice: String, Equatable, Sendable, CaseIterable {
    case useCable, moveCloser, plugIn, coolDown, lineBusy, turnOnSQM, slowLine, setUpBetterXcloud, notMeasured
    /// Something isn't green and nothing more specific applies: never let it read as "all good".
    case seeAdvanced
}

public struct FixPlan: Equatable, Sendable {
    public var fixes: [Fix]
    public var advice: [Advice]
    public var isEmpty: Bool { fixes.isEmpty && advice.isEmpty }

    public init(fixes: [Fix], advice: [Advice]) { self.fixes = fixes; self.advice = advice }
}

public enum FixPlanner {
    /// The state of things Game Ready could change itself.
    public struct Context: Equatable, Sendable {
        public var gameModeOn: Bool
        /// Better xCloud is installed and readable, and differs from the preset.
        public var betterXcloudNeedsTuning: Bool
        /// Better xCloud is installed but the browser blocks access (one-time setup).
        public var betterXcloudBlocked: Bool
        public var noisyApps: [String]

        public init(gameModeOn: Bool, betterXcloudNeedsTuning: Bool, betterXcloudBlocked: Bool, noisyApps: [String]) {
            self.gameModeOn = gameModeOn; self.betterXcloudNeedsTuning = betterXcloudNeedsTuning
            self.betterXcloudBlocked = betterXcloudBlocked; self.noisyApps = noisyApps
        }
    }

    public static func plan(_ results: [CheckResult], _ c: Context) -> FixPlan {
        let findings = Set(results.flatMap(\.findings))
        var fixes = [Fix]()
        // Game Mode fixes the Mac's own interruptions; suggest it whenever it's off.
        if !c.gameModeOn { fixes.append(.gameMode) }
        if c.betterXcloudNeedsTuning { fixes.append(.betterXcloud) }
        if !c.noisyApps.isEmpty && !c.gameModeOn { fixes.append(.quitApps(c.noisyApps.sorted())) }

        var advice = [Advice]()
        // A cable beats any Wi-Fi; and a hop that still pauses with Game Mode on is the Wi-Fi itself.
        let onWiFi = findings.contains(.wifi24GHz) || findings.contains(.wifi5GHz) || findings.contains(.wifi6GHz)
        let hopBad = findings.contains(.hopLoss) || (findings.contains(.hopPausing) && c.gameModeOn)
        if onWiFi || hopBad { advice.append(.useCable) }
        if findings.contains(.wifiWeak) || findings.contains(.wifiPoor) { advice.append(.moveCloser) }
        if findings.contains(.onBattery) || findings.contains(.batteryLow) { advice.append(.plugIn) }
        if findings.contains(.thermalHigh) { advice.append(.coolDown) }
        if findings.contains(.lineBusy) || findings.contains(.lineMaybeBusy) { advice.append(.lineBusy) }
        if findings.contains(.speedBloatBad) || findings.contains(.speedBloatMild) { advice.append(.turnOnSQM) }
        if findings.contains(.speedTooSlow) || findings.contains(.internetPoor) || findings.contains(.udpLossy) { advice.append(.slowLine) }
        if c.betterXcloudBlocked { advice.append(.setUpBetterXcloud) }
        if results.contains(where: { $0.grade == .unknown && Verdict.essential.contains($0.id) }) { advice.append(.notMeasured) }
        let uncovered = results.contains { r in
            (r.grade == .amber || r.grade == .red)
                && !(!fixes.isEmpty && !r.findings.isEmpty && r.findings.allSatisfy { BasicState.fixableFindings.contains($0) })
        }
        if advice.isEmpty && uncovered { advice.append(.seeAdvanced) }
        return FixPlan(fixes: fixes, advice: advice)
    }
}

/// Basic's headline, from the verdict and what's left to do.
public enum BasicState: String, Equatable, Sendable {
    /// Nothing checked yet.
    case unchecked
    /// Fixes Game Ready can apply.
    case canFix
    /// Something Game Ready can't fix is wrong, and there are fixes it can still make.
    case problemButCanFix
    /// Nothing to fix, but the user could improve something.
    case readyWithAdvice
    /// All good.
    case ready
    /// Something serious that Game Ready can't fix (e.g. a lossy line).
    case problem

    /// Findings Game Mode itself takes care of (the AirDrop radio, noisy apps, Time Machine,
    /// Low Power Mode, the checklist settings it changes).
    public static let fixableFindings: Set<Finding> = [.awdlOn, .hopPausing, .hopSpiky, .appsNoisy,
                                                        .timeMachineRunning, .lowPowerOn, .checklistOpen]

    public static func from(verdict: Verdict?, plan: FixPlan) -> BasicState {
        guard let verdict else { return .unchecked }
        // A red or unmeasured essential result that no fix covers is a real problem, even when
        // there are other fixes to make: never hide it behind "Almost ready".
        let unfixable = verdict.problems.contains { r in
            let serious = r.grade == .red || (r.grade == .unknown && Verdict.essential.contains(r.id))
            let covered = !plan.fixes.isEmpty && !r.findings.isEmpty && r.findings.allSatisfy { fixableFindings.contains($0) }
            return serious && !covered
        }
        if !plan.fixes.isEmpty { return unfixable ? .problemButCanFix : .canFix }
        if unfixable || verdict.level == .notReady || verdict.level == .incomplete { return .problem }
        return plan.advice.isEmpty && verdict.level == .ready ? .ready : .readyWithAdvice
    }
}

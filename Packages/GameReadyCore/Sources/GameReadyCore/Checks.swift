/// The pre-flight checks, in the order the results screen shows them.
public enum CheckID: String, Sendable, Codable, CaseIterable {
    case connection, wifi, hop, internet, udp, ipv6, speed, lineFree, mac, apps, checklist
}

/// What a result means, as a code. Only the UI turns codes into words, so the logic
/// stays testable and translatable.
public enum Finding: String, Sendable, Codable, CaseIterable {
    // connection / wifi
    case ethernet, wifi6GHz, wifi5GHz, wifi24GHz, notConnected
    case wifiStrong, wifiWeak, wifiPoor, wifiUnknown
    // hop
    case hopSteady, hopSpiky, hopPausing, hopLoss
    // internet
    case internetGood, internetSlowish, internetPoor, internetLoss
    // udp
    case udpClean, udpSomeLoss, udpLossy, udpSlow
    // ipv6
    case ipv6Ready, ipv6Missing
    // speed
    case speedGood, speedBloatMild, speedBloatBad, speedSlow, speedTooSlow, speedRateLimited
    // line free
    case lineQuiet, lineMaybeBusy, lineBusy
    // mac
    case macReady, awdlOn, lowPowerOn, onBattery, batteryLow, thermalHigh, cpuBusy
    // apps
    case appsQuiet, appsNoisy, timeMachineRunning
    // checklist
    case checklistDone, checklistOpen
    // anything
    case notMeasured
}

public struct CheckResult: Sendable, Codable, Equatable, Identifiable {
    public var id: CheckID
    public var grade: Grade
    /// Worst finding first; the UI shows the first one as the headline.
    public var findings: [Finding]
    /// Raw numbers for the "Details" disclosure, already formatted, never user content.
    public var details: [String: String]

    public init(id: CheckID, grade: Grade, findings: [Finding], details: [String: String] = [:]) {
        self.id = id
        self.grade = grade
        self.findings = findings
        self.details = details
    }

    public static func notMeasured(_ id: CheckID) -> CheckResult {
        CheckResult(id: id, grade: .unknown, findings: [.notMeasured])
    }
}

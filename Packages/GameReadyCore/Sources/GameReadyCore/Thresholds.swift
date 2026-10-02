/// Every pass/warn/fail boundary in one place. Defaults are tuned for cloud gaming at
/// 1080p–1440p (Xbox Cloud Gaming, GeForce NOW), which needs roughly 20 Mbps and,
/// above all, steady latency.
public struct Thresholds: Sendable, Codable, Equatable {
    // Wi-Fi link
    public var wifiRSSIGreen = -60
    public var wifiRSSIAmber = -70
    public var wifiRateGreenMbps = 600.0
    public var wifiRateRedMbps = 200.0

    // Mac → router hop. Spikes here are the Mac's own Wi-Fi (AirDrop/AWDL, scans).
    public var hopMaxGreenMs = 10.0
    public var hopMaxAmberMs = 30.0

    // Internet
    public var internetAvgGreenMs = 25.0
    public var internetAvgAmberMs = 40.0
    public var internetJitterGreenMs = 5.0
    public var internetJitterAmberMs = 10.0

    // UDP (DNS probe)
    public var udpP95GreenMs = 30.0
    public var udpLossAmberPercent = 0.5

    // Speed and latency under load
    public var downGreenMbps = 40.0
    public var downAmberMbps = 25.0
    public var upGreenMbps = 10.0
    public var loadRiseGreenMs = 15.0
    public var loadRiseAmberMs = 40.0

    // "Is someone else using the line?": idle latency over the best seen this session
    public var lineBusyAmberMs = 10.0
    public var lineBusyRedMs = 25.0

    // Mac
    public var batteryAmberPercent = 50
    public var cpuRedPercent = 80.0

    // Live watch
    public var liveSpikeMs = 40.0

    public init() {}

    public static let standard = Thresholds()
}

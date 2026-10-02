import Foundation

/// A speed-test provider. Only hosts listed in `Endpoints` are allowed.
public enum SpeedProvider: String, Sendable, Codable, CaseIterable {
    case cloudflare, hetzner

    /// Download URL for one transfer of `bytes`. Hetzner serves a fixed 1 GB file, so its
    /// transfers are cut short by the time limit instead.
    public func downloadURL(bytes: Int) -> URL {
        switch self {
        case .cloudflare: return URL(string: "https://\(Endpoints.cloudflareSpeed)/__down?bytes=\(bytes)")!
        case .hetzner: return URL(string: "https://\(Endpoints.hetznerSpeed)/1GB.bin")!
        }
    }

    public var uploadURL: URL? {
        switch self {
        case .cloudflare: return URL(string: "https://\(Endpoints.cloudflareSpeed)/__up")!
        case .hetzner: return nil
        }
    }
}

/// One HTTP transfer as it actually happened.
public struct Transfer: Sendable, Equatable {
    public var status: Int
    public var bytesExpected: Int?
    public var bytesMoved: Int
    public var seconds: Double
    /// The transfer was stopped by our own time limit (not by the server).
    public var cutByTimeLimit: Bool

    public init(status: Int, bytesExpected: Int?, bytesMoved: Int, seconds: Double, cutByTimeLimit: Bool) {
        self.status = status; self.bytesExpected = bytesExpected; self.bytesMoved = bytesMoved
        self.seconds = seconds; self.cutByTimeLimit = cutByTimeLimit
    }

    /// A transfer counts only if the bytes really arrived. A rate-limited endpoint answers
    /// HTTP 429 with a 1-byte body, which would otherwise look like an instant, perfect run.
    public var isValid: Bool {
        guard (200..<300).contains(status), bytesMoved > 0, seconds > 0 else { return false }
        if cutByTimeLimit { return bytesMoved >= 1_000_000 }   // got at least 1 MB before we stopped it
        guard let expected = bytesExpected, expected > 0 else { return bytesMoved >= 1_000_000 }
        return Double(bytesMoved) >= Double(expected) * 0.9
    }

    public var isRateLimited: Bool { status == 429 }
}

public enum SpeedRun {
    /// Throughput of parallel streams over the same window: total bytes over the window,
    /// not the sum of per-stream speeds (which overstates when streams don't overlap).
    /// Returns nil when no transfer is valid.
    public static func mbps(_ transfers: [Transfer], windowSeconds: Double) -> Double? {
        let valid = transfers.filter(\.isValid)
        guard !valid.isEmpty, windowSeconds > 0 else { return nil }
        let bytes = valid.reduce(0) { $0 + $1.bytesMoved }
        return Double(bytes) * 8 / 1_000_000 / windowSeconds
    }

    /// Whether to fall back to the next provider: nothing valid came back.
    public static func shouldFallBack(_ transfers: [Transfer]) -> Bool {
        !transfers.contains(where: \.isValid)
    }

    public static func wasRateLimited(_ transfers: [Transfer]) -> Bool {
        transfers.contains(where: \.isRateLimited)
    }

    /// Minimum gap between speed tests: a test fills the whole household line.
    public static let minimumGap: TimeInterval = 120
}

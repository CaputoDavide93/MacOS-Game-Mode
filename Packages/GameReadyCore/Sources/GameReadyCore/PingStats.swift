import Foundation

/// Round-trip samples in milliseconds; `nil` is a lost packet.
public struct PingStats: Sendable, Codable, Equatable {
    public let sent: Int
    public let received: Int
    public let minMs: Double?
    public let avgMs: Double?
    public let maxMs: Double?
    public let p95Ms: Double?
    /// Mean absolute difference between consecutive received samples (RFC 3550-style, unsmoothed).
    public let jitterMs: Double?

    public var lossPercent: Double {
        sent == 0 ? 100 : Double(sent - received) * 100 / Double(sent)
    }

    /// True when nothing came back, so there is nothing to grade.
    public var isEmpty: Bool { received == 0 }

    public init(samples: [Double?]) {
        let got = samples.compactMap { $0 }
        sent = samples.count
        received = got.count
        guard !got.isEmpty else {
            minMs = nil; avgMs = nil; maxMs = nil; p95Ms = nil; jitterMs = nil
            return
        }
        let sorted = got.sorted()
        minMs = sorted.first
        maxMs = sorted.last
        avgMs = got.reduce(0, +) / Double(got.count)
        let index = min(sorted.count - 1, Int((Double(sorted.count) * 0.95).rounded(.up)) - 1)
        p95Ms = sorted[max(0, index)]
        if got.count > 1 {
            var total = 0.0
            for i in 1..<got.count { total += abs(got[i] - got[i - 1]) }
            jitterMs = total / Double(got.count - 1)
        } else {
            jitterMs = 0
        }
    }

    /// Median of the received samples, used as a baseline for "latency under load".
    public static func median(_ samples: [Double?]) -> Double? {
        let got = samples.compactMap { $0 }.sorted()
        guard !got.isEmpty else { return nil }
        let mid = got.count / 2
        return got.count % 2 == 0 ? (got[mid - 1] + got[mid]) / 2 : got[mid]
    }
}

/// Parses the output of macOS `/sbin/ping` and `/sbin/ping6`, line by line.
public enum PingLine: Equatable, Sendable {
    case reply(seq: Int, ms: Double)
    case timeout(seq: Int)
    case other

    public static func parse(_ line: String) -> PingLine {
        // "64 bytes from 1.1.1.1: icmp_seq=3 ttl=57 time=13.204 ms"
        // "16 bytes from 2606:4700:4700::1111, icmp_seq=0 hlim=57 time=14.1 ms"
        if let seq = Self.value(after: "icmp_seq=", in: line).flatMap({ Int($0) }),
           let time = Self.value(after: "time=", in: line).flatMap({ Double($0) }) {
            return .reply(seq: seq, ms: time)
        }
        // "Request timeout for icmp_seq 5"
        if line.hasPrefix("Request timeout for icmp_seq"),
           let seq = line.split(separator: " ").last.flatMap({ Int($0) }) {
            return .timeout(seq: seq)
        }
        return .other
    }

    private static func value(after key: String, in line: String) -> String? {
        guard let range = line.range(of: key) else { return nil }
        let rest = line[range.upperBound...]
        let token = rest.prefix { $0.isNumber || $0 == "." }
        return token.isEmpty ? nil : String(token)
    }

    /// Turns a whole ping run into samples ordered by sequence number. A sequence number
    /// that was sent (below `count`) but never answered counts as lost.
    public static func samples(from output: String, count: Int) -> [Double?] {
        var bySeq = [Int: Double]()
        for line in output.split(whereSeparator: \.isNewline) {
            if case let .reply(seq, ms) = parse(String(line)), bySeq[seq] == nil { bySeq[seq] = ms }
        }
        return (0..<count).map { bySeq[$0] }
    }
}

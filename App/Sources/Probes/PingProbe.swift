import Foundation
import GameReadyCore

/// ICMP ping through the system's `/sbin/ping` (`/sbin/ping6` for IPv6 addresses).
enum PingProbe {
    /// Sends `count` pings at `interval` seconds and returns one sample per sequence number.
    static func run(host: String, count: Int, interval: Double = 0.1, waitMs: Int = 1000) async -> [Double?] {
        let v6 = host.contains(":")
        let binary = v6 ? "/sbin/ping6" : "/sbin/ping"
        // -n numeric, -c count, -i interval; -W (ping) / -O-less ping6 waits per reply via -i timing.
        var args = ["-n", "-c", "\(count)", "-i", String(format: "%.2f", interval)]
        if !v6 { args += ["-W", "\(waitMs)"] }
        args.append(host)
        let budget = Double(count) * interval + Double(waitMs) / 1000 + 5
        let result = await Shell.run(binary, args, timeout: budget)
        return PingLine.samples(from: result.output, count: count)
    }
}

/// A long-running ping that reports each reply or loss as it happens (live watch).
final class StreamingPing: @unchecked Sendable {
    private let process = Process()
    private let pipe = Pipe()
    private var buffer = ""
    private var lastSeq = -1
    private let lock = NSLock()

    /// `onSample` receives a round trip in ms, or nil for a lost packet.
    init(host: String, interval: Double, onSample: @escaping @Sendable (Double?) -> Void) {
        let v6 = host.contains(":")
        process.executableURL = URL(fileURLWithPath: v6 ? "/sbin/ping6" : "/sbin/ping")
        process.arguments = ["-n", "-i", String(format: "%.1f", interval), host]
        process.standardOutput = pipe
        process.standardError = Pipe()
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            let chunk = String(decoding: handle.availableData, as: UTF8.self)
            for line in self.lines(appending: chunk) {
                switch PingLine.parse(line) {
                case let .reply(seq, ms):
                    self.reportGap(upTo: seq, onSample)
                    onSample(ms)
                case let .timeout(seq):
                    self.reportGap(upTo: seq, onSample)
                    onSample(nil)
                case .other:
                    break
                }
            }
        }
    }

    func start() { try? process.run() }

    func stop() {
        pipe.fileHandleForReading.readabilityHandler = nil
        if process.isRunning { process.terminate() }
    }

    deinit { stop() }

    private func lines(appending chunk: String) -> [String] {
        lock.lock(); defer { lock.unlock() }
        buffer += chunk
        var out = [String]()
        while let range = buffer.range(of: "\n") {
            out.append(String(buffer[..<range.lowerBound]))
            buffer.removeSubrange(..<range.upperBound)
        }
        return out
    }

    /// ping skips printing for some losses; a jump in sequence numbers is lost packets.
    private func reportGap(upTo seq: Int, _ onSample: @Sendable (Double?) -> Void) {
        lock.lock()
        let missing = lastSeq >= 0 ? max(0, seq - lastSeq - 1) : 0
        lastSeq = max(lastSeq, seq)
        lock.unlock()
        for _ in 0..<min(missing, 10) { onSample(nil) }
    }
}

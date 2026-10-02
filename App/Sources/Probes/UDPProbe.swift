import Foundation
import Network
import GameReadyCore

/// UDP loss and latency, measured with small DNS queries: the same transport game streams use.
///
/// One listener runs for the whole probe and records every answer by query id, so a late
/// answer can never be mistaken for, or swallow, the answer to a later query.
enum UDPProbe {
    static func run(server: String, count: Int = 200, spacingMs: Int = 20, timeoutMs: Int = 500) async -> [Double?] {
        let connection = NWConnection(host: NWEndpoint.Host(server), port: 53, using: .udp)
        let queue = DispatchQueue(label: "udp-probe")
        guard await ready(connection, queue: queue) else {
            connection.cancel()
            return Array(repeating: nil, count: count)
        }
        let log = ArrivalLog()
        listen(connection, log: log)

        var sentAt = [UInt64](repeating: 0, count: count)
        for i in 0..<count {
            sentAt[i] = DispatchTime.now().uptimeNanoseconds
            connection.send(content: DNSProbe.query(id: UInt16(i)), completion: .contentProcessed { _ in })
            try? await Task.sleep(for: .milliseconds(spacingMs))
        }
        try? await Task.sleep(for: .milliseconds(timeoutMs))   // let the last answers arrive
        connection.cancel()

        let arrivals = log.snapshot()
        let limit = UInt64(timeoutMs) * 1_000_000
        return (0..<count).map { i in
            guard let at = arrivals[UInt16(i)], at >= sentAt[i], at - sentAt[i] <= limit else { return nil }
            return Double(at - sentAt[i]) / 1_000_000
        }
    }

    private static func listen(_ c: NWConnection, log: ArrivalLog) {
        c.receiveMessage { data, _, _, error in
            let now = DispatchTime.now().uptimeNanoseconds
            if let data, data.count >= 12, data[data.startIndex + 2] & 0x80 != 0 {
                let id = UInt16(data[data.startIndex]) << 8 | UInt16(data[data.startIndex + 1])
                log.record(id: id, at: now)
            }
            if error == nil { listen(c, log: log) }
        }
    }

    private static func ready(_ c: NWConnection, queue: DispatchQueue) async -> Bool {
        await withCheckedContinuation { continuation in
            let once = Once()
            c.stateUpdateHandler = { state in
                switch state {
                case .ready: once.run { continuation.resume(returning: true) }
                case .failed, .cancelled: once.run { continuation.resume(returning: false) }
                default: break
                }
            }
            c.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 3) { once.run { continuation.resume(returning: false) } }
        }
    }
}

/// First arrival time per query id, from the receive callback's thread.
final class ArrivalLog: @unchecked Sendable {
    private var arrivals = [UInt16: UInt64]()
    private let lock = NSLock()
    func record(id: UInt16, at: UInt64) {
        lock.lock(); if arrivals[id] == nil { arrivals[id] = at }; lock.unlock()
    }
    func snapshot() -> [UInt16: UInt64] { lock.lock(); defer { lock.unlock() }; return arrivals }
}

/// Runs a closure at most once, from any thread.
final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var done = false
    func run(_ body: () -> Void) {
        lock.lock()
        guard !done else { lock.unlock(); return }
        done = true
        lock.unlock()
        body()
    }
}

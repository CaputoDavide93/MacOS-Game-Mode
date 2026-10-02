import Foundation
import GameReadyCore

/// Download and upload throughput with latency under load. Every transfer is checked by
/// `Transfer.isValid` before it counts (a rate-limited endpoint returns a 1-byte body).
enum SpeedProbe {
    static let streams = 4
    static let phaseSeconds: Double = 10
    static let downloadChunk = 25_000_000
    static let uploadChunk = 10_000_000

    static func run(idleMedianMs: Double?, latencyHost: String) async -> SpeedMeasurement {
        var rateLimited = false
        var down: Double?
        var loadedDown: Double?
        for provider in SpeedProvider.allCases {
            async let pings = PingProbe.run(host: latencyHost, count: Int(phaseSeconds / 0.2), interval: 0.2)
            let start = Date()
            let transfers = await downloadPhase(provider)
            let window = Date().timeIntervalSince(start)   // includes transfers that ran past the deadline
            let samples = await pings
            if SpeedRun.wasRateLimited(transfers) { rateLimited = true }
            if !SpeedRun.shouldFallBack(transfers) {
                down = SpeedRun.mbps(transfers, windowSeconds: window)
                loadedDown = PingStats.median(samples)
                break
            }
        }
        var up: Double?
        var loadedUp: Double?
        if let url = SpeedProvider.cloudflare.uploadURL {
            async let pings = PingProbe.run(host: latencyHost, count: Int(phaseSeconds / 0.2), interval: 0.2)
            let start = Date()
            let transfers = await uploadPhase(url)
            let window = Date().timeIntervalSince(start)   // the last uploads finish after the deadline
            let samples = await pings
            if SpeedRun.wasRateLimited(transfers) { rateLimited = true }
            if !SpeedRun.shouldFallBack(transfers) {
                up = SpeedRun.mbps(transfers, windowSeconds: window)
                loadedUp = PingStats.median(samples)
            }
        }
        return SpeedMeasurement(downMbps: down, upMbps: up, idleMedianMs: idleMedianMs,
                                loadedDownMedianMs: loadedDown, loadedUpMedianMs: loadedUp, rateLimited: rateLimited)
    }

    /// `streams` parallel loops, each fetching chunks back to back until the phase ends.
    private static func downloadPhase(_ provider: SpeedProvider) async -> [Transfer] {
        let deadline = Date().addingTimeInterval(phaseSeconds)
        return await withTaskGroup(of: [Transfer].self) { group in
            for _ in 0..<streams {
                group.addTask {
                    var out = [Transfer]()
                    while Date() < deadline {
                        let t = await fetch(provider.downloadURL(bytes: downloadChunk), deadline: deadline,
                                            expected: provider == .cloudflare ? downloadChunk : nil)
                        out.append(t)
                        if !t.isValid { break }   // rate-limited or failing: stop hammering
                    }
                    return out
                }
            }
            var all = [Transfer]()
            for await part in group { all += part }
            return all
        }
    }

    private static func uploadPhase(_ url: URL) async -> [Transfer] {
        let deadline = Date().addingTimeInterval(phaseSeconds)
        let body = Data((0..<uploadChunk).map { _ in UInt8.random(in: 0...255) })
        return await withTaskGroup(of: [Transfer].self) { group in
            for _ in 0..<streams {
                group.addTask {
                    var out = [Transfer]()
                    while Date() < deadline {
                        let t = await upload(url, body: body, deadline: deadline)
                        out.append(t)
                        if !t.isValid { break }
                    }
                    return out
                }
            }
            var all = [Transfer]()
            for await part in group { all += part }
            return all
        }
    }

    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        c.urlCache = nil
        c.httpCookieStorage = nil
        c.timeoutIntervalForRequest = phaseSeconds + 5
        return URLSession(configuration: c)
    }()

    /// Streams the body and counts bytes per received chunk, cancelling at the deadline.
    private static func fetch(_ url: URL, deadline: Date, expected: Int?) async -> Transfer {
        let counter = ByteCounter(deadline: deadline)
        let start = Date()
        let task = session.dataTask(with: url)
        task.delegate = counter
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                counter.onFinish = { continuation.resume() }
                task.resume()
            }
        } onCancel: { task.cancel() }
        return Transfer(status: counter.status, bytesExpected: expected, bytesMoved: counter.bytes,
                        seconds: Date().timeIntervalSince(start), cutByTimeLimit: counter.cut)
    }

    private static func upload(_ url: URL, body: Data, deadline: Date) async -> Transfer {
        let start = Date()
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = max(1, deadline.timeIntervalSinceNow + 2)
        do {
            let (_, response) = try await session.upload(for: request, from: body)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            return Transfer(status: status, bytesExpected: body.count, bytesMoved: (200..<300).contains(status) ? body.count : 0,
                            seconds: Date().timeIntervalSince(start), cutByTimeLimit: false)
        } catch {
            return Transfer(status: 0, bytesExpected: body.count, bytesMoved: 0,
                            seconds: Date().timeIntervalSince(start), cutByTimeLimit: false)
        }
    }
}

/// Counts bytes as they arrive and cancels the transfer at the deadline.
private final class ByteCounter: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    let deadline: Date
    private let lock = NSLock()
    private var _bytes = 0, _status = 0, _cut = false
    private var finished = false
    var onFinish: (() -> Void)?

    init(deadline: Date) { self.deadline = deadline }

    var bytes: Int { lock.lock(); defer { lock.unlock() }; return _bytes }
    var status: Int { lock.lock(); defer { lock.unlock() }; return _status }
    var cut: Bool { lock.lock(); defer { lock.unlock() }; return _cut }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        lock.lock(); _status = (response as? HTTPURLResponse)?.statusCode ?? 0; lock.unlock()
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        _bytes += data.count
        let over = Date() >= deadline
        if over { _cut = true }
        lock.unlock()
        if over { dataTask.cancel() }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let first = !finished
        finished = true
        let done = onFinish
        lock.unlock()
        if first { done?() }
    }
}

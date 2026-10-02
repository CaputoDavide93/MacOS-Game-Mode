import Foundation

/// One saved pre-flight check.
public struct CheckRecord: Sendable, Codable, Equatable, Identifiable {
    public var id: UUID
    public var at: Date
    public var verdict: VerdictLevel
    public var results: [CheckResult]
    /// Idle latency to the internet during this check: the baseline for "is the line busy?".
    public var idleMedianMs: Double?

    public init(id: UUID = UUID(), at: Date, verdict: VerdictLevel, results: [CheckResult], idleMedianMs: Double? = nil) {
        self.id = id; self.at = at; self.verdict = verdict; self.results = results; self.idleMedianMs = idleMedianMs
    }
}

public enum HistoryEntry: Sendable, Codable, Equatable {
    case check(CheckRecord)
    case session(SessionSummary)

    public var at: Date {
        switch self {
        case .check(let c): return c.at
        case .session(let s): return s.end
        }
    }
}

/// Append-only JSON-lines file in the app's support folder, pruned to `keepDays`.
/// Lines that don't decode (a crash mid-write, a future format) are skipped, never fatal.
public final class HistoryStore: @unchecked Sendable {
    public let fileURL: URL
    public let keepDays: Int
    private let lock = NSLock()
    private let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.sortedKeys]; return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()

    public init(directory: URL, keepDays: Int = 90) {
        fileURL = directory.appendingPathComponent("history.jsonl")
        self.keepDays = keepDays
    }

    public func append(_ entry: HistoryEntry) throws {
        lock.lock(); defer { lock.unlock() }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var line = try encoder.encode(entry)
        line.append(0x0A)
        // Create the file only if it doesn't exist; never replace an existing one,
        // or a failed open would wipe the history.
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            try line.write(to: fileURL, options: .withoutOverwriting)
            return
        }
        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
    }

    /// Newest first.
    public func load(now: Date = Date()) -> [HistoryEntry] {
        lock.lock(); defer { lock.unlock() }
        return readAll().filter { $0.at >= cutoff(now) }.sorted { $0.at > $1.at }
    }

    /// Rewrites the file without entries older than `keepDays`.
    public func prune(now: Date = Date()) throws {
        lock.lock(); defer { lock.unlock() }
        let kept = readAll().filter { $0.at >= cutoff(now) }
        var data = Data()
        for e in kept { data.append(try encoder.encode(e)); data.append(0x0A) }
        try data.write(to: fileURL, options: .atomic)
    }

    public func deleteAll() throws {
        lock.lock(); defer { lock.unlock() }
        if FileManager.default.fileExists(atPath: fileURL.path) { try FileManager.default.removeItem(at: fileURL) }
    }

    private func cutoff(_ now: Date) -> Date { now.addingTimeInterval(-Double(keepDays) * 86_400) }

    private func readAll() -> [HistoryEntry] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return data.split(separator: 0x0A).compactMap { try? decoder.decode(HistoryEntry.self, from: Data($0)) }
    }
}

/// CSV for pasting into a spreadsheet or a measurements log.
public enum HistoryCSV {
    public static func checks(_ records: [CheckRecord]) -> String {
        var rows = ["time,verdict," + CheckID.allCases.map(\.rawValue).joined(separator: ",")]
        let iso = ISO8601DateFormatter()
        for r in records {
            let byID = Dictionary(r.results.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let cells = CheckID.allCases.map { id -> String in
                guard let res = byID[id] else { return "" }
                return escape("\(res.grade):" + res.findings.map(\.rawValue).joined(separator: "|"))
            }
            rows.append(([iso.string(from: r.at), r.verdict.rawValue] + cells).joined(separator: ","))
        }
        return rows.joined(separator: "\n") + "\n"
    }

    public static func session(_ s: SessionSummary) -> String {
        let iso = ISO8601DateFormatter()
        var rows = ["time,layer,kind,value"]
        for e in s.events {
            rows.append([iso.string(from: e.at), e.layer.rawValue, e.kind.rawValue, escape(e.value ?? "")].joined(separator: ","))
        }
        return rows.joined(separator: "\n") + "\n"
    }

    static func escape(_ s: String) -> String {
        s.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" })
            ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            : s
    }
}

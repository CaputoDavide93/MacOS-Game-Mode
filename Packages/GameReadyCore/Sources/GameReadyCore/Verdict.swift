/// The one answer the home screen shows.
public enum VerdictLevel: String, Sendable, Codable {
    case ready, warning, notReady, incomplete
}

public struct Verdict: Sendable, Codable, Equatable {
    public var level: VerdictLevel
    /// Results that aren't green, worst first, then in check order.
    public var problems: [CheckResult]

    public init(results input: [CheckResult]) {
        // An essential check that never ran counts as "couldn't measure" (D4).
        let present = Set(input.map(\.id))
        let results = input.isEmpty ? input
            : input + Self.essential.subtracting(present).sorted { $0.rawValue < $1.rawValue }.map(CheckResult.notMeasured)
        let order = Dictionary(uniqueKeysWithValues: CheckID.allCases.enumerated().map { ($1, $0) })
        problems = results
            .filter { $0.grade != .green }
            .sorted { a, b in
                a.grade.effective != b.grade.effective
                    ? a.grade.effective > b.grade.effective
                    : order[a.id, default: 0] < order[b.id, default: 0]
            }
        if results.isEmpty {
            level = .incomplete
        } else {
            switch results.map(\.grade).worst {
            case .green: level = .ready
            case .red: level = .notReady
            default:
                // Couldn't measure something important → say so rather than "ready, with a warning".
                let blind = results.contains { $0.grade == .unknown && Self.essential.contains($0.id) }
                level = blind ? .incomplete : .warning
            }
        }
    }

    /// Checks without which the app can't vouch for the connection.
    public static let essential: Set<CheckID> = [.connection, .hop, .internet, .udp]
}

/// How a single check came out. `unknown` means the probe could not measure,
/// and it is never treated as a pass: a missing measurement grades amber.
public enum Grade: Int, Sendable, Codable, Comparable, CaseIterable {
    case green = 0
    case unknown = 1
    case amber = 2
    case red = 3

    public static func < (lhs: Grade, rhs: Grade) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Stored and exported as a word ("green"), not the severity number.
    public init(from decoder: Decoder) throws {
        let name = try decoder.singleValueContainer().decode(String.self)
        guard let g = Grade.allCases.first(where: { "\($0)" == name }) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "unknown grade \(name)"))
        }
        self = g
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode("\(self)")
    }

    /// The grade a verdict counts this as: `unknown` weighs like amber.
    public var effective: Grade { self == .unknown ? .amber : self }
}

public extension Sequence where Element == Grade {
    /// The worst grade in the sequence, with `unknown` counted as amber. Empty → unknown.
    var worst: Grade {
        var result: Grade?
        for grade in self {
            let g = grade.effective
            if result == nil || g > result! { result = g }
        }
        return result ?? .unknown
    }
}

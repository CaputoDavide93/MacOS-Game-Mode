import Foundation

/// A JSON value, enough to read and write Better xCloud's settings object faithfully.
public enum JSONValue: Sendable, Codable, Equatable, Hashable {
    case string(String), number(Double), bool(Bool), null
    case array([JSONValue]), object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b): try c.encode(b)
        case .null: try c.encodeNil()
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }
}

/// Better xCloud (github.com/redphx/better-xcloud) keeps its global settings as one JSON
/// object in the xbox.com page's localStorage, under `BetterXcloud`. The keys and values
/// below are taken from its source (`src/enums/pref-keys.ts`, `pref-values.ts`,
/// `global-settings-storage.ts`), checked 2 Oct 2026.
public enum BetterXcloud {
    public static let storageKey = "BetterXcloud"

    public enum Key {
        public static let region = "server.region"
        public static let preferIPv6 = "server.ipv6.prefer"
        public static let resolution = "stream.video.resolution"
        public static let codecProfile = "stream.video.codecProfile"
        /// Bits per second; 0 means "maximum" (the script maps the slider's max to 0).
        public static let maxBitrate = "stream.video.maxBitrate"
    }

    /// What "Apply Game Ready settings" sets. Region and resolution are left alone: region is
    /// personal, and resolution above 1080p is the Xbox site's own setting, not Better xCloud's.
    public static let preset: [String: JSONValue] = [
        Key.preferIPv6: .bool(true),
        Key.maxBitrate: .number(0),
        Key.codecProfile: .string("high"),
    ]

    /// Reads the settings object (or "null" when Better xCloud has never saved any).
    public static let readScript = "(function(){return localStorage.getItem('\(storageKey)');})()"

    /// Merges `changes` into the stored object (nil removes a key), saves it, and returns the
    /// saved text so the caller can verify it. `changes` is JSON-encoded, never spliced as code.
    public static func writeScript(_ changes: [String: JSONValue?]) throws -> String {
        let patch = changes.mapValues { $0 ?? .null }
        let removals = changes.filter { $0.value == nil }.map(\.key).sorted()
        let enc = JSONEncoder(); enc.outputFormatting = .sortedKeys
        let patchJSON = String(decoding: try enc.encode(patch), as: UTF8.self)
        let removeJSON = String(decoding: try enc.encode(removals), as: UTF8.self)
        return """
        (function(){var k='\(storageKey)';var s=JSON.parse(localStorage.getItem(k)||'{}');\
        var p=\(patchJSON);var r=\(removeJSON);\
        for(var x in p){s[x]=p[x];}for(var i=0;i<r.length;i++){delete s[r[i]];}\
        localStorage.setItem(k,JSON.stringify(s));return localStorage.getItem(k);})()
        """
    }

    /// Parses what `readScript` returned. nil = Better xCloud isn't there (or never saved).
    public static func parse(_ text: String?) -> [String: JSONValue]? {
        guard let text, text != "null", !text.isEmpty,
              let value = try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)),
              case .object(let object) = value else { return nil }
        return object
    }

    /// The keys the preset would change, each with its current value (nil = absent), so the
    /// change can be undone exactly.
    public static func snapshot(of current: [String: JSONValue]) -> [String: JSONValue?] {
        var out = [String: JSONValue?]()
        for (key, value) in preset where current[key] != value { out[key] = .some(current[key]) }
        return out
    }

    /// Whether the stored settings already match the preset.
    public static func matchesPreset(_ current: [String: JSONValue]) -> Bool {
        preset.allSatisfy { current[$0.key] == $0.value }
    }

    /// For the checklist: stream quality is "done" when bitrate is unlimited and the codec
    /// profile is high; IPv6 when it's preferred.
    public static func qualityDone(_ s: [String: JSONValue]) -> Bool {
        s[Key.maxBitrate] == .number(0) && s[Key.codecProfile] == .string("high")
    }

    public static func ipv6Done(_ s: [String: JSONValue]) -> Bool { s[Key.preferIPv6] == .bool(true) }
}

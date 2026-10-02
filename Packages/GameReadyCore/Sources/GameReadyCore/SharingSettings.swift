import Foundation

/// macOS settings Game Mode changes as the user (no root): the ones that wake the AirDrop
/// radio. Each is snapshotted before the change and restored exactly, including "the key
/// wasn't there" (the macOS default), which is restored by deleting the key.
public struct SharingSetting: Sendable, Codable, Equatable, Hashable {
    public enum Kind: String, Sendable, Codable { case string, bool }

    public var domain: String
    public var key: String
    public var currentHost: Bool
    public var kind: Kind
    /// The value Game Mode sets, as `defaults write` takes it.
    public var gameValue: String
    /// The process that must re-read the setting after it changes.
    public var reloadProcess: String?

    public static let airDrop = SharingSetting(domain: "com.apple.sharingd", key: "DiscoverableMode",
                                               currentHost: false, kind: .string, gameValue: "Off", reloadProcess: "sharingd")
    public static let handoffAdvertise = SharingSetting(domain: "com.apple.coreservices.useractivityd", key: "ActivityAdvertisingAllowed",
                                                        currentHost: true, kind: .bool, gameValue: "false", reloadProcess: nil)
    public static let handoffReceive = SharingSetting(domain: "com.apple.coreservices.useractivityd", key: "ActivityReceivingAllowed",
                                                      currentHost: true, kind: .bool, gameValue: "false", reloadProcess: nil)
    public static let universalControl = SharingSetting(domain: "com.apple.universalcontrol", key: "Disable",
                                                        currentHost: false, kind: .bool, gameValue: "true", reloadProcess: "UniversalControl")

    public static let all: [SharingSetting] = [.airDrop, .handoffAdvertise, .handoffReceive, .universalControl]

    /// `defaults` arguments to read the current value.
    public var readArguments: [String] { host + ["read", domain, key] }

    /// `defaults` arguments to set the Game Mode value.
    public var applyArguments: [String] { host + ["write", domain, key, "-\(kind.rawValue)", gameValue] }

    /// `defaults` arguments that put back what was there before.
    public func restoreArguments(original: String?) -> [String] {
        guard let original else { return host + ["delete", domain, key] }
        return host + ["write", domain, key, "-\(kind.rawValue)", Self.normalise(original, kind)]
    }

    /// Whether a value read back from `defaults read` equals the Game Mode value.
    public func isGameValue(_ read: String?) -> Bool {
        guard let read else { return false }
        return Self.normalise(read, kind) == Self.normalise(gameValue, kind)
    }

    public enum ReadResult: Equatable, Sendable { case value(String), absent, failed }

    /// Only a genuine "not set" from `defaults` counts as absent. Any other failure must stop
    /// Game Mode before it changes anything, or restore would delete a real value.
    public static func classifyRead(status: Int32, output: String, error: String) -> ReadResult {
        if status == 0 {
            let v = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return .value(v)
        }
        let e = error.lowercased()
        if status == 1 && (e.contains("does not exist") || e.contains("could not find key")
                           || (e.contains("domain") && e.contains("not found"))) {
            return .absent
        }
        return .failed
    }

    private var host: [String] { currentHost ? ["-currentHost"] : [] }

    /// `defaults read` prints booleans as 1/0; `defaults write -bool` takes true/false.
    public static func normalise(_ value: String, _ kind: Kind) -> String {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard kind == .bool else { return v }
        switch v.lowercased() {
        case "1", "true", "yes": return "true"
        default: return "false"
        }
    }
}

/// What a Game Mode session changed and must put back. Saved to disk before any change, so
/// a crash can still be undone on the next launch.
public struct RestorePlan: Sendable, Codable, Equatable {
    /// Original value per setting; nil means the key was absent (the macOS default).
    public var sharing: [SharingSetting: String?]
    /// Better xCloud keys the preset changed, with their original JSON values (nil = absent).
    public var betterXcloud: [String: JSONValue?]?
    /// The browser (bundle id) whose page was tuned: restore goes there, whatever the setting is now.
    public var betterXcloudBrowser: String?

    public init(sharing: [SharingSetting: String?] = [:], betterXcloud: [String: JSONValue?]? = nil,
                betterXcloudBrowser: String? = nil) {
        self.sharing = sharing
        self.betterXcloud = betterXcloud
        self.betterXcloudBrowser = betterXcloudBrowser
    }

    public var isEmpty: Bool { sharing.isEmpty && (betterXcloud?.isEmpty ?? true) }
}

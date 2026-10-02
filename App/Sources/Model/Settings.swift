import Foundation
import Observation
import GameReadyCore

enum Browser: String, CaseIterable, Identifiable, Sendable {
    case chrome, safari, edge
    var id: String { rawValue }
    var bundleID: String {
        switch self {
        case .chrome: return "com.google.Chrome"
        case .safari: return "com.apple.Safari"
        case .edge: return "com.microsoft.edgemac"
        }
    }
}

/// User preferences, in UserDefaults. Nothing here is sensitive.
@MainActor @Observable
final class AppSettings {
    private let defaults: UserDefaults

    var browser: Browser { didSet { defaults.set(browser.rawValue, forKey: "browser") } }
    var gameServerHost: String { didSet { defaults.set(gameServerHost, forKey: "gameServerHost") } }
    /// Bundle IDs of apps Game Mode quits.
    var quitApps: Set<String> { didSet { defaults.set(Array(quitApps), forKey: "quitApps") } }
    var runSpeedTest: Bool { didSet { defaults.set(runSpeedTest, forKey: "runSpeedTest") } }
    var platform: GamingPlatform { didSet { defaults.set(platform.rawValue, forKey: "platform") } }
    /// Opt-in: Game Mode also applies the Better xCloud preset (and undoes it on "off").
    var tuneBetterXcloud: Bool { didSet { defaults.set(tuneBetterXcloud, forKey: "tuneBetterXcloud") } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        browser = Browser(rawValue: defaults.string(forKey: "browser") ?? "") ?? .chrome
        gameServerHost = defaults.string(forKey: "gameServerHost") ?? Endpoints.defaultGameServerHost
        quitApps = Set(defaults.stringArray(forKey: "quitApps") ?? AppsProbe.knownNoisy.map(\.id))
        runSpeedTest = defaults.object(forKey: "runSpeedTest") as? Bool ?? true
        platform = GamingPlatform(rawValue: defaults.string(forKey: "platform") ?? "") ?? .xboxCloud
        tuneBetterXcloud = defaults.bool(forKey: "tuneBetterXcloud")
    }

    /// Only the built-in game server and play page are allowed (Endpoints, D-privacy).
    static let gameServers: [(host: String, label: String)] = [
        (Endpoints.defaultGameServerHost, "Xbox Cloud Gaming"),
    ]
}

import AppKit
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
    /// Brand names: never translated.
    var displayName: String {
        switch self {
        case .chrome: return "Chrome"
        case .safari: return "Safari"
        case .edge: return "Edge"
        }
    }
    init?(bundleID: String) {
        guard let b = Browser.allCases.first(where: { $0.bundleID == bundleID }) else { return nil }
        self = b
    }

    /// The browser macOS opens web links in.
    @MainActor static var systemDefaultBundleID: String? {
        NSWorkspace.shared.urlForApplication(toOpen: GamingPlatform.xboxCloud.playURL)
            .flatMap { Bundle(url: $0)?.bundleIdentifier }
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
    /// When the AirDrop-off profile is used (D24).
    var airDropBlock: AirDropBlock { didSet { defaults.set(airDropBlock.rawValue, forKey: "airDropBlock") } }
    /// Basic (one button) or Advanced (every number).
    var advancedMode: Bool { didSet { defaults.set(advancedMode, forKey: "advancedMode") } }

    /// `systemBrowser`: the Mac's default browser's bundle ID, used until the user picks one
    /// (Allow JavaScript from Apple Events is per browser, so the right one matters).
    init(defaults: UserDefaults = .standard, systemBrowser: String? = nil) {
        self.defaults = defaults
        let saved = Browser(rawValue: defaults.string(forKey: "browser") ?? "")?.bundleID
        browser = Browser(bundleID: BrowserChoice.initial(saved: saved, systemDefault: systemBrowser,
                                                          supported: Browser.allCases.map(\.bundleID))) ?? .chrome
        gameServerHost = defaults.string(forKey: "gameServerHost") ?? Endpoints.defaultGameServerHost
        quitApps = Set(defaults.stringArray(forKey: "quitApps") ?? AppsProbe.knownNoisy.map(\.id))
        runSpeedTest = defaults.object(forKey: "runSpeedTest") as? Bool ?? true
        platform = GamingPlatform(rawValue: defaults.string(forKey: "platform") ?? "") ?? .xboxCloud
        tuneBetterXcloud = defaults.bool(forKey: "tuneBetterXcloud")
        advancedMode = defaults.bool(forKey: "advancedMode")
        airDropBlock = AirDropBlock(rawValue: defaults.string(forKey: "airDropBlock") ?? "") ?? .never
    }

    /// Only the built-in game server and play page are allowed (Endpoints, D-privacy).
    static let gameServers: [(host: String, label: String)] = [
        (Endpoints.defaultGameServerHost, "Xbox Cloud Gaming"),
    ]
}

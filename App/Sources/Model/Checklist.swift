import AppKit
import Foundation
import Observation
import GameReadyCore

/// Settings a script can't change. Detected where macOS lets an app read them; otherwise
/// ticked by hand and remembered.
@MainActor @Observable
final class Checklist {
    enum Item: String, CaseIterable, Identifiable, Sendable {
        case locationServices, airDrop, handoff, universalControl, browserEnergySaver,
             streamQuality, streamIPv6, controllerUSB
        var id: String { rawValue }

        /// System Settings pane to open, if there is one.
        var settingsURL: URL? {
            switch self {
            case .locationServices: return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")
            case .airDrop, .handoff: return URL(string: "x-apple.systempreferences:com.apple.AirDrop-Handoff-Settings.extension")
            case .universalControl: return URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension")
            default: return nil
            }
        }
    }

    enum Source: Equatable { case detected, manual }

    private(set) var done: [Item: Bool] = [:]
    private(set) var source: [Item: Source] = [:]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        for item in Item.allCases {
            done[item] = defaults.bool(forKey: "checklist.\(item.rawValue)")
            source[item] = .manual
        }
    }

    func setDone(_ item: Item, _ value: Bool) {
        done[item] = value
        defaults.set(value, forKey: "checklist.\(item.rawValue)")
    }

    /// Screenshots only: a believable half-done list, not saved.
    func loadDemo() {
        for item in Item.allCases { done[item] = [.airDrop, .handoff, .streamQuality, .streamIPv6].contains(item) }
        source[.airDrop] = .detected; source[.handoff] = .detected
        source[.streamQuality] = .detected; source[.streamIPv6] = .detected
    }

    var states: [ChecklistItemState] { Item.allCases.map { ChecklistItemState(key: $0.rawValue, done: done[$0] ?? false) } }

    /// Reads what macOS exposes without special permissions. Anything unreadable stays manual.
    func detect() async {
        if let mode = await readDefault(domain: "com.apple.sharingd", key: "DiscoverableMode") {
            apply(.airDrop, mode == "Off")
        }
        if let adv = await readDefault(domain: "com.apple.coreservices.useractivityd", key: "ActivityAdvertisingAllowed", currentHost: true) {
            apply(.handoff, adv == "0")
        }
        if let disabled = await readDefault(domain: "com.apple.universalcontrol", key: "Disable") {
            apply(.universalControl, disabled == "1")
        }
    }

    /// Better xCloud's own settings answer two checklist items.
    func applyBetterXcloud(_ settings: [String: JSONValue]?) {
        guard let settings else { return }
        apply(.streamQuality, BetterXcloud.qualityDone(settings))
        apply(.streamIPv6, BetterXcloud.ipv6Done(settings))
    }

    private func apply(_ item: Item, _ value: Bool) {
        source[item] = .detected
        setDone(item, value)
    }

    private func readDefault(domain: String, key: String, currentHost: Bool = false) async -> String? {
        let args = (currentHost ? ["-currentHost"] : []) + ["read", domain, key]
        let r = await Shell.run("/usr/bin/defaults", args, timeout: 5)
        guard r.status == 0 else { return nil }
        let value = r.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

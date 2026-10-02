import Foundation
import Observation
import GameReadyCore

/// The user-level changes Game Mode makes (AirDrop, Handoff, Universal Control, and the
/// Better xCloud preset) and their undo. The plan is saved to disk before anything changes,
/// so a crash can still be undone; it's deleted only when everything is back.
@MainActor @Observable
final class SessionChanges {
    enum XcloudStatus: Equatable {
        case unknown, notInstalled, noTab, jsDisabled, notAllowed, browserClosed, failed
        case matches, differs
        case applied, restorePending
    }

    private(set) var xcloud: XcloudStatus = .unknown
    private(set) var xcloudSettings: [String: JSONValue]?

    static let planURL = GameModeController.supportDir.appendingPathComponent("restore-plan.json")

    var hasPendingRestore: Bool { FileManager.default.fileExists(atPath: Self.planURL.path) }

    // MARK: - Apply

    enum ApplyError: LocalizedError {
        case cannotRead(String), cannotSave, unreadablePlan
        var errorDescription: String? {
            switch self {
            case .cannotRead(let key): return String(format: L("ui.changes.cannotRead"), key)
            case .cannotSave: return L("ui.changes.cannotSave")
            case .unreadablePlan: return L("ui.changes.unreadablePlan")
            }
        }
    }

    /// Snapshots and changes the sharing settings, and the Better xCloud preset if asked.
    /// Nothing changes unless every original was read and the plan is safely on disk.
    func apply(betterXcloud: Bool, browser: Browser) async throws {
        // An existing plan that can't be read holds originals we'd otherwise overwrite: stop.
        // (Not `try?`: that flattens "no plan yet", the normal case, into the same nil as a failure.)
        let existing: RestorePlan?
        do { existing = try loadPlanStrict() } catch { throw ApplyError.unreadablePlan }
        var plan = existing ?? RestorePlan()
        for setting in SharingSetting.all where plan.sharing[setting] == nil {
            switch await read(setting) {
            case .value(let v): plan.sharing[setting] = .some(v)
            case .absent: plan.sharing[setting] = .some(nil)   // not set: the macOS default
            case .failed: throw ApplyError.cannotRead(setting.key)
            }
        }
        try save(plan)
        for setting in SharingSetting.all { await write(setting.applyArguments) }
        await reload()

        if betterXcloud {
            await applyXcloud(into: &plan, browser: browser)
            try? save(plan)
        }
    }

    private func applyXcloud(into plan: inout RestorePlan, browser: Browser) async {
        switch await BrowserBridge.run(BetterXcloud.readScript, in: browser) {
        case .value(let text):
            guard let current = BetterXcloud.parse(text) else { xcloud = .notInstalled; return }
            let snapshot = BetterXcloud.snapshot(of: current)
            guard !snapshot.isEmpty else { xcloud = .matches; xcloudSettings = current; return }
            // A pending undo for another browser must be finished first, or one would be lost.
            if let pending = plan.betterXcloudBrowser, pending != browser.bundleID, plan.betterXcloud?.isEmpty == false {
                xcloud = .restorePending; return
            }
            // Keep the oldest original if an earlier session's undo is still pending.
            plan.betterXcloud = (plan.betterXcloud ?? [:]).merging(snapshot) { old, _ in old }
            plan.betterXcloudBrowser = browser.bundleID
            guard (try? save(plan)) != nil else { xcloud = .failed; return }
            let changes = BetterXcloud.preset.mapValues { Optional($0) }
            guard let js = try? BetterXcloud.writeScript(changes),
                  case .value(let saved) = await BrowserBridge.run(js, in: browser),
                  let after = BetterXcloud.parse(saved), BetterXcloud.matchesPreset(after) else {
                xcloud = .failed; return
            }
            xcloudSettings = after
            xcloud = .applied
        case let other:
            xcloud = status(for: other)
        }
    }

    // MARK: - Restore

    /// Puts back everything in the saved plan. Better xCloud is restored in the browser it was
    /// tuned in, which needs an open xbox.com tab; otherwise that part is retried next time.
    /// False when a plan exists but can't be read: it stays on disk and the caller says so.
    @discardableResult
    func restore() async -> Bool {
        let loaded: RestorePlan?
        do { loaded = try loadPlanStrict() } catch { return false }
        guard var plan = loaded else { return true }
        for (setting, original) in plan.sharing { await write(setting.restoreArguments(original: original)) }
        await reload()
        // Only what reads back as the original leaves the plan; anything else is retried next time.
        for (setting, original) in plan.sharing {
            let back: Bool
            switch (await read(setting), original) {
            case (.absent, nil): back = true
            case (.value(let now), .some(let o)): back = SharingSetting.normalise(now, setting.kind) == SharingSetting.normalise(o, setting.kind)
            default: back = false
            }
            if back { plan.sharing.removeValue(forKey: setting) }
        }

        if let changes = plan.betterXcloud, !changes.isEmpty {
            let browser = plan.betterXcloudBrowser.flatMap { id in Browser.allCases.first { $0.bundleID == id } } ?? .chrome
            if let js = try? BetterXcloud.writeScript(changes),
               case .value(let saved) = await BrowserBridge.run(js, in: browser),
               let after = BetterXcloud.parse(saved),
               changes.allSatisfy({ after[$0.key] == $0.value }) {
                plan.betterXcloud = nil
                plan.betterXcloudBrowser = nil
                xcloudSettings = after
                xcloud = BetterXcloud.matchesPreset(after) ? .matches : .differs
            } else {
                xcloud = .restorePending
            }
        }
        if plan.isEmpty { try? FileManager.default.removeItem(at: Self.planURL) } else { try? save(plan) }
        return true
    }

    // MARK: - Read (checklist)

    func refreshXcloud(browser: Browser) async {
        switch await BrowserBridge.run(BetterXcloud.readScript, in: browser) {
        case .value(let text):
            guard let s = BetterXcloud.parse(text) else { xcloud = .notInstalled; xcloudSettings = nil; return }
            xcloudSettings = s
            if hasPendingRestore, loadPlan()?.betterXcloud?.isEmpty == false {
                xcloud = BetterXcloud.matchesPreset(s) ? .applied : .differs
            } else {
                xcloud = BetterXcloud.matchesPreset(s) ? .matches : .differs
            }
        case let other:
            xcloud = status(for: other)
        }
    }

    /// Screenshots only: Better xCloud found but not tuned yet.
    func loadDemoDiffers() {
        xcloud = .differs
        xcloudSettings = [BetterXcloud.Key.maxBitrate: .number(5_120_000)]
    }

    /// Screenshots only.
    func loadDemo() {
        xcloud = .applied
        xcloudSettings = BetterXcloud.preset
    }

    // MARK: - Helpers

    private func status(for outcome: BrowserBridge.Outcome) -> XcloudStatus {
        switch outcome {
        case .noTab: return .noTab
        case .jsDisabled: return .jsDisabled
        case .notAllowed: return .notAllowed
        case .notRunning: return .browserClosed
        case .failed: return .failed
        case .value: return .unknown
        }
    }

    private func read(_ setting: SharingSetting) async -> SharingSetting.ReadResult {
        let r = await Shell.run("/usr/bin/defaults", setting.readArguments, timeout: 5)
        return SharingSetting.classifyRead(status: r.status, output: r.output, error: r.error)
    }

    private func write(_ arguments: [String]) async {
        _ = await Shell.run("/usr/bin/defaults", arguments, timeout: 5)
    }

    /// The agents re-read their settings when restarted; launchd starts them again at once.
    private func reload() async {
        for name in Set(SharingSetting.all.compactMap(\.reloadProcess)) {
            _ = await Shell.run("/usr/bin/killall", [name], timeout: 5)
        }
    }

    private func loadPlan() -> RestorePlan? { (try? loadPlanStrict()) ?? nil }

    /// nil = no plan on disk. Throws when a plan exists but can't be read or decoded.
    private func loadPlanStrict() throws -> RestorePlan? {
        guard FileManager.default.fileExists(atPath: Self.planURL.path) else { return nil }
        let data = try Data(contentsOf: Self.planURL)
        return try JSONDecoder().decode(RestorePlan.self, from: data)
    }

    private func save(_ plan: RestorePlan) throws {
        do {
            try FileManager.default.createDirectory(at: GameModeController.supportDir, withIntermediateDirectories: true)
            try JSONEncoder().encode(plan).write(to: Self.planURL, options: .atomic)
        } catch {
            throw ApplyError.cannotSave
        }
    }
}

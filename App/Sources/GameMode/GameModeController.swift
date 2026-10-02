import AppKit
import Foundation
import IOKit.pwr_mgt
import Observation
import GameReadyCore

/// Game Mode: the privileged guard (AirDrop radio, Low Power Mode, Time Machine) plus the
/// user-level parts (no sleep, quiet apps). See D8 in docs/decisions.md.
@MainActor @Observable
final class GameModeController {
    enum Phase: Equatable { case off, starting, on, stopping, failed(String) }

    private(set) var phase: Phase = .off
    private var sleepAssertion: IOPMAssertionID = 0
    private var watchdog: Task<Void, Never>?

    static let supportDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Game Ready", isDirectory: true)
    }()
    static let flagURL = supportDir.appendingPathComponent("gamemode.on")

    var isOn: Bool { phase == .on || phase == .starting }

    /// A flag left behind by a crash or a kill: offer to turn Game Mode off.
    var leftOn: Bool { FileManager.default.fileExists(atPath: Self.flagURL.path) && phase == .off }

    func turnOn(quitting apps: [NSRunningApplication]) async {
        guard !isOn else { return }
        phase = .starting
        do {
            try FileManager.default.createDirectory(at: Self.supportDir, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: Self.flagURL.path) {
                try Data().write(to: Self.flagURL)
            }
            try await startGuard()
        } catch {
            try? FileManager.default.removeItem(at: Self.flagURL)
            phase = .failed(error.localizedDescription)
            return
        }
        holdAwake(true)
        for app in apps { app.terminate() }
        phase = .on
        startWatchdog()
    }

    /// Deleting the flag is the whole of "off": the guard notices within 5 s and restores.
    func turnOff() async {
        guard phase == .on || phase == .starting || leftOn || isFailed else { return }
        phase = .stopping
        watchdog?.cancel()
        try? FileManager.default.removeItem(at: Self.flagURL)
        holdAwake(false)
        // Wait until the guard has put AirDrop back, so the UI tells the truth.
        for _ in 0..<16 {
            if NetworkProbe.isUp("awdl0") != false { break }
            try? await Task.sleep(for: .milliseconds(500))
        }
        phase = .off
    }

    private var isFailed: Bool { if case .failed = phase { return true }; return false }

    private func startGuard() async throws {
        // One administrator prompt per session. The script text comes from the signed
        // binary (`GuardScript`); the only argument is our own flag path.
        let command = "/bin/bash -c " + Self.shellQuote(GuardScript.source) + " game-mode-guard " + Self.shellQuote(Self.flagURL.path)
        let source = "do shell script \"\(Self.appleScriptEscape(command))\" with administrator privileges"
        let result: (ok: Bool, message: String) = await Task.detached {
            var error: NSDictionary?
            let output = NSAppleScript(source: source)?.executeAndReturnError(&error)
            if let error { return (false, error[NSAppleScript.errorMessage] as? String ?? "cancelled") }
            return (true, output?.stringValue ?? "")
        }.value
        guard result.ok else { throw GameModeError.guardFailed(result.message) }
    }

    /// While on, re-check every 10 s that the flag still exists (another window may have
    /// turned Game Mode off) and keep the UI honest.
    private func startWatchdog() {
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard let self else { return }
                if !FileManager.default.fileExists(atPath: Self.flagURL.path) {
                    self.holdAwake(false)
                    self.phase = .off
                    return
                }
            }
        }
    }

    private func holdAwake(_ on: Bool) {
        if on, sleepAssertion == 0 {
            IOPMAssertionCreateWithName(kIOPMAssertPreventUserIdleDisplaySleep as CFString,
                                        IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                        "Game Mode is on" as CFString, &sleepAssertion)
        } else if !on, sleepAssertion != 0 {
            IOPMAssertionRelease(sleepAssertion)
            sleepAssertion = 0
        }
    }

    nonisolated static func shellQuote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    nonisolated static func appleScriptEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}

enum GameModeError: LocalizedError {
    case guardFailed(String)
    var errorDescription: String? {
        switch self {
        case .guardFailed(let m): return m
        }
    }
}

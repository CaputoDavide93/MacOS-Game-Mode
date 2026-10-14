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

    /// Called when the session ends without the user turning it off: the flag went (another
    /// window), or the guard died or hit its 12-hour limit. The model runs the full "off".
    var onEndedUnexpectedly: (@MainActor () async -> Void)?

    /// A guard is running: its pid file names a live bash process. Root's process answers
    /// `kill(pid, 0)` with EPERM, which still means it exists; the path check stops a pid
    /// left by a killed guard, since reused by another program, from counting.
    nonisolated static var guardAlive: Bool {
        guard let text = try? String(contentsOfFile: GuardScript.pidPath, encoding: .utf8),
              let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)), pid > 0,
              kill(pid, 0) == 0 || errno == EPERM else { return false }
        var path = [UInt8](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &path, UInt32(path.count))
        guard length > 0 else { return false }
        return String(decoding: path.prefix(Int(length)), as: UTF8.self).hasSuffix("/bash")
    }

    /// Waits for a guard to exit, up to `seconds`. True once none is running.
    private func waitForGuardToExit(seconds: Double) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Self.guardAlive && Date() < deadline {
            do { try await Task.sleep(for: .milliseconds(500)) } catch { break }
        }
        return !Self.guardAlive
    }

    /// A guard ended without restoring (a restart, a kill): its originals are still on disk.
    var needsPrivilegedRestore: Bool {
        FileManager.default.fileExists(atPath: GuardScript.journalPath) && !Self.guardAlive
    }

    /// Screenshots only: shows Game Mode as on without touching the system.
    func loadDemoOn() { phase = .on }

    var flagPresent: Bool { FileManager.default.fileExists(atPath: Self.flagURL.path) }

    /// A flag left behind by a crash or a kill, or a dead guard's originals: offer to turn
    /// Game Mode off.
    var leftOn: Bool { phase == .off && (flagPresent || needsPrivilegedRestore) }

    func turnOn(quitting apps: [NSRunningApplication]) async {
        guard !isOn else { return }
        phase = .starting
        do {
            // A previous session's guard still on its way out would answer "already running"
            // and then exit, leaving this one unguarded: let it finish first.
            if !flagPresent, !(await waitForGuardToExit(seconds: 15)) {
                throw GameModeError.guardFailed("")
            }
            try FileManager.default.createDirectory(at: Self.supportDir, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: Self.flagURL.path) {
                try Data().write(to: Self.flagURL)
            }
            try await startGuard()
        } catch GameModeError.cancelled {
            try? FileManager.default.removeItem(at: Self.flagURL)
            phase = .off
            return
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
    /// False when something privileged may not be back (the guard outlived the wait, or a
    /// dead guard's originals couldn't be restored). `mayPrompt: false` (quit) never asks for
    /// the password; a dead guard's originals then wait for the "left on" banner.
    @discardableResult
    func turnOff(mayPrompt: Bool = true) async -> Bool {
        guard phase == .on || phase == .starting || leftOn || isFailed else { return true }
        phase = .stopping
        watchdog?.cancel()
        try? FileManager.default.removeItem(at: Self.flagURL)
        holdAwake(false)
        // Wait until the guard has restored everything and exited, so the UI tells the truth.
        // One loop is 5 s, then the restore itself.
        var restored = await waitForGuardToExit(seconds: 15)
        // A guard that died never restored: put its originals back (one password prompt).
        if restored, needsPrivilegedRestore {
            if mayPrompt { _ = try? await runGuard("--restore") }
            restored = !needsPrivilegedRestore
        }
        phase = .off
        return restored
    }

    private var isFailed: Bool { if case .failed = phase { return true }; return false }

    private func startGuard() async throws {
        try await runGuard(Self.flagURL.path)
    }

    /// One administrator prompt. The script text comes from the signed binary (`GuardScript`);
    /// the only argument is our own flag path, or `--restore`.
    @discardableResult
    private func runGuard(_ argument: String) async throws -> String {
        let command = "/bin/bash -c " + Self.shellQuote(GuardScript.source) + " game-mode-guard " + Self.shellQuote(argument)
        let source = "do shell script \"\(Self.appleScriptEscape(command))\" with administrator privileges"
        let result: (ok: Bool, cancelled: Bool, message: String) = await Task.detached {
            var error: NSDictionary?
            let output = NSAppleScript(source: source)?.executeAndReturnError(&error)
            if let error {
                let number = error[NSAppleScript.errorNumber] as? Int ?? 0
                return (false, number == -128, error[NSAppleScript.errorMessage] as? String ?? "")
            }
            return (true, false, output?.stringValue ?? "")
        }.value
        if result.cancelled { throw GameModeError.cancelled }
        guard result.ok else { throw GameModeError.guardFailed(result.message) }
        return result.message
    }

    /// While on, re-check every 10 s that the flag still exists (another window may have
    /// turned Game Mode off) and that the guard is still running (it stops after 12 hours,
    /// or may be killed). Either way the whole session ends, not just the switch.
    private func startWatchdog() {
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard let self, !Task.isCancelled, self.phase == .on else { return }
                if !FileManager.default.fileExists(atPath: Self.flagURL.path) || !Self.guardAlive {
                    // Its own task: "off" cancels this watchdog, which must not cut "off" short.
                    let end = self.onEndedUnexpectedly
                    Task { @MainActor [weak self] in
                        if let end { await end() } else { await self?.turnOff() }
                    }
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
    /// The user dismissed the password prompt: not an error worth a message.
    case cancelled
    var errorDescription: String? {
        switch self {
        case .guardFailed(let m): return m
        case .cancelled: return nil
        }
    }
}

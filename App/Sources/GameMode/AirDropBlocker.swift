import AppKit
import Foundation
import Observation
import GameReadyCore

/// The AirDrop-off configuration profile (D24): written to the support folder and opened, so
/// macOS lists it in System Settings → General → Device Management for the user to approve.
/// macOS allows nothing else. Removing it is the guard's job (`--remove-airdrop`).
@MainActor @Observable
final class AirDropBlocker {
    /// nil until checked.
    private(set) var installed: Bool?
    /// Opened, not yet approved: say what to do, and look again when the user comes back.
    private(set) var awaitingApproval = false

    static let profileURL = GameModeController.supportDir.appendingPathComponent(AirDropProfile.fileName)
    /// Ventura and later: General → Device Management.
    private static let deviceManagement = URL(string: "x-apple.systempreferences:com.apple.Profiles-Settings.extension")

    func refresh() async {
        let r = await Shell.run("/usr/sbin/system_profiler", ["SPConfigurationProfileDataType"], timeout: 20)
        guard r.status == 0 else { return }   // unknown stays unknown, never "not installed"
        installed = AirDropProfile.isInstalled(systemProfilerOutput: r.output)
        // `awaitingApproval` is cleared only by the model, which first decides whether a late
        // approval needs a warning (any refresh could otherwise swallow it).
    }

    /// Hands the profile to macOS. False if it couldn't be written.
    @discardableResult
    func offerInstall() -> Bool {
        do {
            try FileManager.default.createDirectory(at: GameModeController.supportDir, withIntermediateDirectories: true)
            try Data(AirDropProfile.source.utf8).write(to: Self.profileURL, options: .atomic)
        } catch {
            return false
        }
        guard NSWorkspace.shared.open(Self.profileURL) else { return false }
        if let pane = Self.deviceManagement { _ = NSWorkspace.shared.open(pane) }   // a shortcut; the profile is listed either way
        awaitingApproval = true
        return true
    }

    /// Approved after its Game Mode session ended: nothing will remove it by itself.
    func noteSeen() { awaitingApproval = false }

    func noteRemoved() {
        installed = false
        awaitingApproval = false
    }

    /// Screenshots only.
    func loadDemo(installed: Bool) { self.installed = installed }
}

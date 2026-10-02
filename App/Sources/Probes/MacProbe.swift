import AppKit
import Foundation
import IOKit.ps
import GameReadyCore

enum MacProbe {
    static func state() async -> MacState {
        let power = powerSource()
        let thermal: ThermalLevel
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermal = .nominal
        case .fair: thermal = .fair
        case .serious: thermal = .serious
        case .critical: thermal = .critical
        @unknown default: thermal = .fair
        }
        return MacState(awdlUp: NetworkProbe.isUp("awdl0"),
                        lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
                        onBattery: power.onBattery, batteryPercent: power.percent,
                        thermal: thermal, cpuPercent: await cpuPercent())
    }

    private static func powerSource() -> (onBattery: Bool, percent: Int?) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return (false, nil) }
        for source in list {
            guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            let onBattery = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSBatteryPowerValue
            let current = d[kIOPSCurrentCapacityKey] as? Int
            let max = d[kIOPSMaxCapacityKey] as? Int
            let pct = (current != nil && (max ?? 0) > 0) ? current! * 100 / max! : nil
            return (onBattery, pct)
        }
        return (false, nil)   // a desktop Mac: always on mains
    }

    /// Whole-machine CPU use over a 0.5 s window.
    static func cpuPercent() async -> Double? {
        guard let a = ticks() else { return nil }
        try? await Task.sleep(for: .milliseconds(500))
        guard let b = ticks() else { return nil }
        let busy = Double(b.busy - a.busy), total = Double(b.total - a.total)
        return total > 0 ? busy * 100 / total : nil
    }

    private static func ticks() -> (busy: UInt64, total: UInt64)? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let user = UInt64(info.cpu_ticks.0), system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2), nice = UInt64(info.cpu_ticks.3)
        return (user + system + nice, user + system + idle + nice)
    }
}

/// Apps that scan Wi-Fi, ask for location or sync in the background, and Time Machine.
enum AppsProbe {
    /// Bundle identifiers, so a renamed app is still recognised. Display name for the UI.
    static let knownNoisy: [(id: String, name: String)] = [
        ("us.zoom.xos", "Zoom"), ("com.apple.Maps", "Maps"), ("com.apple.weather", "Weather"),
        ("com.apple.Photos", "Photos"), ("com.apple.Music", "Music"),
        ("com.microsoft.teams2", "Microsoft Teams"), ("com.microsoft.OneDrive", "OneDrive"),
        ("com.getdropbox.dropbox", "Dropbox"), ("com.google.drivefs", "Google Drive"),
        ("com.valvesoftware.steam", "Steam"),
    ]

    @MainActor
    static func runningNoisy(enabled: Set<String>) -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { app in
            guard let id = app.bundleIdentifier else { return false }
            return enabled.contains(id)
        }
    }

    static func timeMachineRunning() async -> Bool {
        let r = await Shell.run("/usr/bin/tmutil", ["status"], timeout: 5)
        return r.output.contains("Running = 1")
    }
}

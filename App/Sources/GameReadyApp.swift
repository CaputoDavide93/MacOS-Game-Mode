import AppKit
import SwiftUI
import GameReadyCore

@main
struct GameReadyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    /// Owned by the delegate, so quitting cleans up even if the main window never opened.
    private var model: AppModel { delegate.model }

    var body: some Scene {
        Window("Game Ready", id: "main") {
            RootView()
                .environment(model)
                .toolbar { ToolbarItem(placement: .principal) { ModeSwitch().environment(model) } }
        }
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 520, height: 640)

        Settings {
            SettingsView().environment(model)
        }

        MenuBarExtra {
            MenuBarView().environment(model)
        } label: {
            Image(systemName: menuSymbol)
                .accessibilityLabel(Text("Game Ready"))
        }
        .menuBarExtraStyle(.window)
    }

    /// The dot in the menu bar: live health while Game Mode is on.
    private var menuSymbol: String {
        guard model.live.running else { return "gamecontroller" }
        switch model.live.grade {
        case .green: return "circle.fill"
        case .red: return "exclamationmark.circle.fill"
        default: return "circle.lefthalf.filled"
        }
    }
}

/// On quit, Game Mode is switched off so nothing stays changed behind the user's back.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // A headless run (--screenshots, --check) builds its own model; this one must not prune the
    // history or retry a restore behind it.
    let model = AppModel(demo: CommandLine.arguments.contains("--screenshots") || CommandLine.arguments.contains("--check"))

    /// `Game Ready --check [--no-speed]`: run one check, print the results as JSON, quit.
    /// Used for testing and for scripting; it never touches Game Mode.
    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--screenshots"), i + 1 < args.count {
            MainActor.assumeIsolated { Screenshots.render(to: URL(fileURLWithPath: args[i + 1])) }
            exit(0)
        }
        guard args.contains("--check") else { return }
        MainActor.assumeIsolated {
            NSApp.setActivationPolicy(.prohibited)
            let model = AppModel(housekeeping: false)
            if args.contains("--no-speed") { model.speedTestOverride = false }   // this run only, not saved
            Task { @MainActor in
                await model.runCheck()
                let enc = JSONEncoder()
                enc.outputFormatting = [.prettyPrinted, .sortedKeys]
                struct Out: Encodable { let verdict: VerdictLevel?; let results: [CheckResult] }
                if let data = try? enc.encode(Out(verdict: model.verdict?.level, results: model.results)) {
                    FileHandle.standardOutput.write(data)
                    FileHandle.standardOutput.write(Data("\n".utf8))
                }
                exit(model.verdict?.level == .ready ? 0 : 1)
            }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated {
            // Also clean up a Game Mode left on by a crash, or the root guard would outlive us.
            guard model.gameMode.isOn || model.gameMode.leftOn || model.switching else { return .terminateNow }
            Task { @MainActor in
                await model.shutDown()
                sender.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

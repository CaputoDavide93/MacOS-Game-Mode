import Foundation
import GameReadyCore

/// Runs a JavaScript snippet in an open xbox.com tab, through the browser's own AppleScript
/// support. Needs two one-time permissions: the browser's "Allow JavaScript from Apple
/// Events" and macOS's Automation prompt ("Game Ready wants to control Chrome").
enum BrowserBridge {
    enum Outcome: Equatable, Sendable {
        case value(String?)
        case noTab           // no xbox.com tab open
        case jsDisabled      // the browser's "Allow JavaScript from Apple Events" is off
        case notAllowed      // the user said no to the Automation prompt
        case notRunning      // the browser isn't open
        case failed(String)
    }

    static let marker = BrowserScripts.noTabMarker

    static func run(_ js: String, in browser: Browser) async -> Outcome {
        let source = BrowserScripts.run(js, bundleID: browser.bundleID, safari: browser == .safari)
        return await AppleScriptRunner.shared.run(source)
    }
}

/// NSAppleScript isn't thread-safe: every script runs on one serial queue.
final class AppleScriptRunner: @unchecked Sendable {
    static let shared = AppleScriptRunner()
    private let queue = DispatchQueue(label: "applescript")

    func run(_ source: String) async -> BrowserBridge.Outcome {
        await withCheckedContinuation { continuation in
            queue.async {
                var error: NSDictionary?
                let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
                if let error {
                    let number = error[NSAppleScript.errorNumber] as? Int ?? 0
                    let message = error[NSAppleScript.errorMessage] as? String ?? ""
                    if number == -1743 { continuation.resume(returning: .notAllowed); return }
                    if number == -600 { continuation.resume(returning: .notRunning); return }
                    if message.localizedCaseInsensitiveContains("javascript") && message.localizedCaseInsensitiveContains("off")
                        || message.localizedCaseInsensitiveContains("Allow JavaScript from Apple Events") {
                        continuation.resume(returning: .jsDisabled); return
                    }
                    continuation.resume(returning: .failed(message))
                    return
                }
                let text = result?.stringValue
                continuation.resume(returning: text == BrowserBridge.marker ? .noTab : .value(text))
            }
        }
    }
}

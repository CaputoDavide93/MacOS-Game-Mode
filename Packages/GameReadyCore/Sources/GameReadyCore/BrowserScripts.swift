/// AppleScript that runs a JavaScript snippet in the first xbox.com tab of a browser.
/// Pure text, so tests can compile it with `osacompile`.
public enum BrowserScripts {
    public static let noTabMarker = "__GAME_READY_NO_TAB__"
    public static let notXboxMarker = "__GAME_READY_NOT_XBOX__"

    /// Wraps `js` so it runs only when the page's real host is xbox.com or a subdomain.
    /// A URL that merely contains "xbox.com" (`attacker.example/?xbox.com`) is refused.
    public static func guarded(_ js: String) -> String {
        "(function(){var h=String(location.hostname).toLowerCase();"
            + "if(h!=='xbox.com'&&!/\\.xbox\\.com$/.test(h))return '\(notXboxMarker)';"
            + "return \(js);})()"
    }

    /// `safari` uses Safari's `do JavaScript`; Chromium browsers (Chrome, Edge) use `execute … javascript`.
    /// Tries each tab whose address mentions xbox.com; the page itself confirms its host
    /// (`guarded`), and the first genuine xbox.com page answers.
    public static func run(_ js: String, bundleID: String, safari: Bool) -> String {
        let code = appleScriptString(guarded(js))
        let call = safari ? "do JavaScript \(code) in t" : "execute t javascript \(code)"
        return """
        if application id "\(bundleID)" is not running then return "\(noTabMarker)"
        tell application id "\(bundleID)"
          repeat with w in windows
            repeat with t in tabs of w
              if URL of t contains "\(Endpoints.xboxTabMatch)" then
                set r to \(call)
                if r is not "\(notXboxMarker)" then return r
              end if
            end repeat
          end repeat
        end tell
        return "\(noTabMarker)"
        """
    }

    /// A quoted AppleScript string literal.
    public static func appleScriptString(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}

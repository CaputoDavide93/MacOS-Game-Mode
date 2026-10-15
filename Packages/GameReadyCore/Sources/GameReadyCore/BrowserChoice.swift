/// Which browser Game Ready reads Better xCloud in. "Allow JavaScript from Apple Events" is a
/// per-browser switch, so talking to the wrong browser looks exactly like that switch being off.
public enum BrowserChoice {
    /// The saved choice; on first launch, the Mac's default browser if Game Ready supports it.
    /// The first supported browser otherwise.
    public static func initial(saved: String?, systemDefault: String?, supported: [String]) -> String {
        if let saved, supported.contains(saved) { return saved }
        if let systemDefault, supported.contains(systemDefault) { return systemDefault }
        return supported[0]
    }

    /// When the chosen browser isn't open but exactly one other supported browser is, that one
    /// is probably where the game is: offer to switch. Nil when there's nothing to suggest.
    public static func suggestion(selected: String, running: [String], supported: [String]) -> String? {
        guard !running.contains(selected) else { return nil }
        let others = Set(running).intersection(supported).subtracting([selected])
        return others.count == 1 ? others.first : nil
    }
}

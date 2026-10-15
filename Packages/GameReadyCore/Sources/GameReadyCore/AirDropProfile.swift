/// AirDrop off by configuration profile (D24). On current macOS that's the only switch an app
/// can offer: AirDrop ignores its preference key, and macOS won't install a profile without
/// the user approving it in System Settings → General → Device Management. Removing it is
/// done by the guard script as root (`--remove-airdrop`, or when a Game Mode session ends).
public enum AirDropProfile {
    public static let identifier = "io.github.caputodavide93.gameready.airdrop"
    public static let fileName = "Game-Ready-AirDrop-Off.mobileconfig"

    /// A restrictions payload (`allowAirDrop` false), which Apple allows installing by hand on
    /// macOS. Fixed UUIDs, so installing it again replaces it rather than adding a second one.
    /// No DOCTYPE: a plist doesn't need it, and the sources name no host outside `Endpoints`.
    public static let source = #"""
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
	<key>PayloadContent</key>
	<array>
		<dict>
			<key>PayloadType</key>
			<string>com.apple.applicationaccess</string>
			<key>PayloadIdentifier</key>
			<string>io.github.caputodavide93.gameready.airdrop.restrictions</string>
			<key>PayloadUUID</key>
			<string>6F0C4E2A-5B1D-4C7E-9A3F-2D8B1E7C4A90</string>
			<key>PayloadVersion</key>
			<integer>1</integer>
			<key>PayloadDisplayName</key>
			<string>AirDrop off</string>
			<key>allowAirDrop</key>
			<false/>
		</dict>
	</array>
	<key>PayloadDisplayName</key>
	<string>Game Ready: AirDrop off</string>
	<key>PayloadDescription</key>
	<string>Turns AirDrop off so it can't pause the Wi-Fi while you play. Remove it in Game Ready, or in System Settings → General → Device Management.</string>
	<key>PayloadIdentifier</key>
	<string>io.github.caputodavide93.gameready.airdrop</string>
	<key>PayloadOrganization</key>
	<string>Game Ready</string>
	<key>PayloadScope</key>
	<string>System</string>
	<key>PayloadRemovalDisallowed</key>
	<false/>
	<key>PayloadType</key>
	<string>Configuration</string>
	<key>PayloadUUID</key>
	<string>2B9E7D14-0C3A-4F86-B5E1-7A4C9D2F6E31</string>
	<key>PayloadVersion</key>
	<integer>1</integer>
</dict>
</plist>
"""#

    /// From `system_profiler SPConfigurationProfileDataType`, which lists installed profiles
    /// without root. Only a line that ends in exactly our identifier ("Identifier: …") counts:
    /// not the payload's longer identifier, and not a mention inside another profile's text.
    public static func isInstalled(systemProfilerOutput: String) -> Bool {
        systemProfilerOutput.split(separator: "\n").contains { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            guard let sep = t.range(of: ": ") else { return t == identifier }
            // An identifier field ("Identifier", "Profile Identifier") holding exactly ours.
            return t[..<sep.lowerBound].lowercased().hasSuffix("identifier") && t[sep.upperBound...] == identifier
        }
    }
}

/// When Game Ready keeps AirDrop off with the profile.
public enum AirDropBlock: String, CaseIterable, Sendable {
    /// No profile: Game Mode still holds the AirDrop radio down while it's on.
    case never
    /// Offered when Game Mode turns on (the user approves it); removed when Game Mode goes off.
    case gameMode
    /// Installed once (the user approves it) and kept until the user removes it in Game Ready.
    case always
}

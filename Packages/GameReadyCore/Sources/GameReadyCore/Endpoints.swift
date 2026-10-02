/// Every host the app ever contacts. The app makes no other network request:
/// `EndpointGuardTests` fails on any other host literal in the sources.
public enum Endpoints {
    /// Speed test (download + upload).
    public static let cloudflareSpeed = "speed.cloudflare.com"
    /// Speed test fallback (download only, HTTPS), used when the first is rate-limited.
    public static let hetznerSpeed = "nbg1-speed.hetzner.com"
    /// Latency and UDP (DNS) probes.
    public static let cloudflareDNSv4 = "1.1.1.1"
    public static let cloudflareDNSv6 = "2606:4700:4700::1111"
    /// A game-streaming region to ping. Default: Xbox Cloud Gaming, UK South front door.
    public static let defaultGameServerHost = "uks.core.gssv-play-prod.xboxlive.com"
    /// Opened in the browser by "Play"; the app never fetches these.
    public static let defaultPlayURL = "https://www.xbox.com/play"
    public static let geforceNowWeb = "play.geforcenow.com"
    public static let lunaWeb = "luna.amazon.com"

    /// The name the UDP probe asks 1.1.1.1 about. Resolved by the DNS server, never contacted.
    public static let dnsQueryName = "example.com"

    /// Text used to find the Xbox tab in the browser. Matched against tab URLs, never contacted.
    public static let xboxTabMatch = "xbox.com"

    public static let allHosts: Set<String> = [
        cloudflareSpeed, hetznerSpeed, cloudflareDNSv4, cloudflareDNSv6,
        defaultGameServerHost, "www.xbox.com", dnsQueryName, geforceNowWeb, lunaWeb, xboxTabMatch,
    ]
}

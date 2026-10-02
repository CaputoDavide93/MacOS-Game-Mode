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
    /// Opened in the browser by "Play"; the app never fetches it.
    public static let defaultPlayURL = "https://www.xbox.com/play"

    /// The name the UDP probe asks 1.1.1.1 about. Resolved by the DNS server, never contacted.
    public static let dnsQueryName = "example.com"

    public static let allHosts: Set<String> = [
        cloudflareSpeed, hetznerSpeed, cloudflareDNSv4, cloudflareDNSv6,
        defaultGameServerHost, "www.xbox.com", dnsQueryName,
    ]
}

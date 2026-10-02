import Foundation

/// Cloud-gaming services the Play button can open. URLs are opened in the browser and never
/// fetched by the app; `Endpoints` lists their hosts.
public enum GamingPlatform: String, Sendable, Codable, CaseIterable, Identifiable {
    case xboxCloud, geforceNow, amazonLuna

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .xboxCloud: return "Xbox Cloud Gaming"
        case .geforceNow: return "GeForce NOW"
        case .amazonLuna: return "Amazon Luna"
        }
    }

    public var playURL: URL {
        switch self {
        case .xboxCloud: return URL(string: Endpoints.defaultPlayURL)!
        case .geforceNow: return URL(string: "https://\(Endpoints.geforceNowWeb)")!
        case .amazonLuna: return URL(string: "https://\(Endpoints.lunaWeb)")!
        }
    }

    /// The platform's own Mac app, used instead of the browser when it's installed.
    public var nativeAppBundleID: String? {
        switch self {
        case .geforceNow: return "com.nvidia.gfnpc.mall"
        default: return nil
        }
    }

    /// Better xCloud only runs on Xbox Cloud Gaming.
    public var usesBetterXcloud: Bool { self == .xboxCloud }
}

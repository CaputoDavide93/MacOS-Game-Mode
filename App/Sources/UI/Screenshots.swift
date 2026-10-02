import AppKit
import SwiftUI

/// `Game Ready --screenshots <dir>`: renders each screen with demo data, light and dark,
/// to `<screen>-<light|dark>.png`. Uses a real offscreen window so AppKit controls draw.
@MainActor
enum Screenshots {
    static func render(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let model = AppModel()
        model.loadDemo()
        for tab in ContentView.Tab.allCases {
            for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                let view = ContentView(tab: tab).environment(model)
                write(view, size: NSSize(width: 440, height: 680), appearance: appearance,
                      to: dir.appendingPathComponent("\(tab.rawValue)-\(name).png"))
            }
        }
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            write(SettingsView().environment(model), size: NSSize(width: 460, height: 560), appearance: appearance,
                  to: dir.appendingPathComponent("settings-\(name).png"))
        }
    }

    /// `Game Ready --icon <dir>`: draws the app icon at every size the asset catalogue needs.
    static func icon(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var images = [[String: String]]()
        for (points, scales) in [(16, [1, 2]), (32, [1, 2]), (128, [1, 2]), (256, [1, 2]), (512, [1, 2])] {
            for scale in scales {
                let px = points * scale
                let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
                write(AppIconView().frame(width: CGFloat(px), height: CGFloat(px)), size: NSSize(width: px, height: px),
                      appearance: .aqua, to: dir.appendingPathComponent(name), scale: 1)
                images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
            }
        }
        let json: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
        if let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: dir.appendingPathComponent("Contents.json"))
        }
    }

    private static func write(_ view: some View, size: NSSize, appearance: NSAppearance.Name, to url: URL, scale: CGFloat = 2) {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))   // let SwiftUI settle
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
        rep.size = size
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}

/// The mark: a controller with a "ready" tick on the app's teal, in the macOS icon shape.
struct AppIconView: View {
    var body: some View {
        GeometryReader { g in
            let s = g.size.width
            ZStack {
                RoundedRectangle(cornerRadius: s * 0.225, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.23, green: 0.49, blue: 0.46), Color(red: 0.15, green: 0.36, blue: 0.34)],
                                         startPoint: .top, endPoint: .bottom))
                    .padding(s * 0.1)
                Image(systemName: "gamecontroller.fill")
                    .resizable().scaledToFit()
                    .foregroundStyle(Color(red: 0.97, green: 0.96, blue: 0.93))
                    .frame(width: s * 0.5)
                    .offset(y: -s * 0.02)
                Circle().fill(Color(red: 0.49, green: 0.83, blue: 0.63))
                    .frame(width: s * 0.2, height: s * 0.2)
                    .overlay(Image(systemName: "checkmark").font(.system(size: s * 0.11, weight: .heavy))
                        .foregroundStyle(Color(red: 0.06, green: 0.09, blue: 0.15)))
                    .offset(x: s * 0.22, y: s * 0.2)
            }
            .frame(width: s, height: s)
        }
    }
}

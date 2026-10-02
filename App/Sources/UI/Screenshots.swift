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
            write(MenuBarView().environment(model).frame(maxHeight: .infinity, alignment: .top)
                    .background(Color(nsColor: .windowBackgroundColor)),
                  size: NSSize(width: 300, height: 200), appearance: appearance,
                  to: dir.appendingPathComponent("menubar-\(name).png"))
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


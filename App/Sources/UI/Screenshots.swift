import AppKit
import SwiftUI

/// `Game Ready --screenshots <dir>`: every screen with demo data, as a whole window on a
/// made-up desktop, light and dark. Uses a real offscreen window so AppKit controls draw.
@MainActor
enum Screenshots {
    static func render(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let basicSize = CGSize(width: 520, height: 640), advSize = CGSize(width: 900, height: 640)
        for (name, dark) in [("light", false), ("dark", true)] {
            // Basic, before Fix & Play: Game Mode off, so there are fixes to make.
            let before = AppModel(demo: true); before.loadDemo(gameModeOn: false)
            shot(BasicView(), model: before, window: basicSize, dark: dark, name: "basic-\(name)", dir: dir)
            // Basic, after: Game Mode on, everything applied.
            let after = AppModel(demo: true); after.loadDemo(gameModeOn: true)
            shot(BasicView(), model: after, window: basicSize, dark: dark, name: "basic-ready-\(name)", dir: dir)
            let advanced = AppModel(demo: true); advanced.loadDemo(gameModeOn: true)
            advanced.settings.advancedMode = true   // the title-bar switch shows Advanced
            for page in AdvancedView.Page.allCases {
                shot(AdvancedView(page: page), model: advanced, window: advSize, dark: dark, name: "advanced-\(page.rawValue)-\(name)", dir: dir)
            }
            shot(MenuBarView().frame(maxHeight: .infinity, alignment: .top), model: after, window: CGSize(width: 300, height: 210),
                 dark: dark, name: "menubar-\(name)", dir: dir, chrome: false)
        }
    }

    private static func shot(_ view: some View, model: AppModel, window: CGSize, dark: Bool, name: String, dir: URL, chrome: Bool = true) {
        let canvas = chrome ? CGSize(width: window.width + 200, height: window.height + 180) : window
        let scene = ZStack {
            if chrome {
                FakeWallpaper(dark: dark)
                FakeWindow { view.environment(model) }
                    .frame(width: window.width, height: window.height)
            } else {
                view.environment(model).background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .environment(model)
        .frame(width: canvas.width, height: canvas.height)
        .environment(\.colorScheme, dark ? .dark : .light)
        write(scene, size: NSSize(width: canvas.width, height: canvas.height), appearance: dark ? .darkAqua : .aqua,
              to: dir.appendingPathComponent("\(name).png"))
    }

    static func write(_ view: some View, size: NSSize, appearance: NSAppearance.Name, to url: URL, scale: CGFloat = 2) {
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

/// A made-up desktop wallpaper: soft colour fields, nothing from a real Mac.
struct FakeWallpaper: View {
    var dark: Bool
    var body: some View {
        ZStack {
            LinearGradient(colors: dark ? [Color(red: 0.07, green: 0.09, blue: 0.16), Color(red: 0.12, green: 0.10, blue: 0.22)]
                                        : [Color(red: 0.62, green: 0.74, blue: 0.86), Color(red: 0.86, green: 0.78, blue: 0.84)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(dark ? Color(red: 0.16, green: 0.33, blue: 0.40) : Color(red: 0.55, green: 0.80, blue: 0.78))
                .frame(width: 760).blur(radius: 140).offset(x: -380, y: 260)
            Circle().fill(dark ? Color(red: 0.32, green: 0.18, blue: 0.40) : Color(red: 0.95, green: 0.80, blue: 0.70))
                .frame(width: 680).blur(radius: 150).offset(x: 420, y: -240)
        }
    }
}

/// A macOS window frame drawn for screenshots: title bar with traffic lights and the
/// Basic | Advanced switch, rounded corners, shadow.
struct FakeWindow<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                HStack(spacing: 8) {
                    ForEach([Color(red: 1, green: 0.37, blue: 0.34), Color(red: 1, green: 0.74, blue: 0.18),
                             Color(red: 0.16, green: 0.78, blue: 0.25)], id: \.self) { c in
                        Circle().fill(c).frame(width: 12, height: 12)
                            .overlay(Circle().strokeBorder(.black.opacity(0.12), lineWidth: 0.5))
                    }
                    Spacer()
                }
                .padding(.horizontal, 14)
                ModeSwitch()
            }
            .frame(height: 52)
            .background(Color(nsColor: .windowBackgroundColor))
            Divider()
            content
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.black.opacity(0.18), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.35), radius: 28, y: 16)
    }
}

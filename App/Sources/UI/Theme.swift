import AppKit
import SwiftUI
import GameReadyCore

/// Colours and controls (docs/design.md). Surfaces and text are the system's own, so the app
/// looks like a Mac app; the one brand colour is "ready" green. Every pair passes WCAG AA.
enum Theme {
    // System surfaces and text
    static let surface = Color(nsColor: .windowBackgroundColor)
    static let card = Color(nsColor: .controlBackgroundColor)
    static let sidebar = Color(nsColor: .underPageBackgroundColor)
    static let text = Color(nsColor: .labelColor)
    static let textVariant = Color(nsColor: .secondaryLabelColor)
    static let outline = Color(nsColor: .separatorColor)

    /// "Ready" green: neon in dark (11.1:1 on window), deep green in light (5.4:1 on white).
    static let ready = dynamic(light: 0x0B7A3E, dark: 0x19F27A)
    /// Text drawn on top of `ready`.
    static let onReady = dynamic(light: 0xFFFFFF, dark: 0x0F1826)
    static let primary = ready
    static let good = ready
    static let warn = dynamic(light: 0xB25000, dark: 0xFF9F0A)
    static let bad = dynamic(light: 0xC4291C, dark: 0xFF6961)

    static let padding: CGFloat = 20

    static func color(_ grade: Grade) -> Color {
        switch grade {
        case .green: return good
        case .amber: return warn
        case .red: return bad
        case .unknown: return textVariant
        }
    }

    static func symbol(_ grade: Grade) -> String {
        switch grade {
        case .green: return "checkmark.circle.fill"
        case .amber: return "exclamationmark.triangle.fill"
        case .red: return "xmark.octagon.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(hex: dark) : NSColor(hex: light)
        })
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
                  blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
    }
}

/// A filled capsule button. Drawn by hand so it keeps its colour in every window state
/// (and in screenshots, where windows are never key).
struct FilledButtonStyle: ButtonStyle {
    var tint: Color = .accentColor
    var foreground: Color = .white
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(foreground)
            .padding(.horizontal, 18).frame(minHeight: 36)
            .background(tint.opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.4), in: Capsule())
            .contentShape(Capsule())
    }
}

/// A macOS-style switch in the given tint, drawn so "on" always looks on.
struct TintedSwitchStyle: ToggleStyle {
    var tint: Color
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.label
            Capsule()
                .fill(configuration.isOn ? tint : Color.secondary.opacity(0.3))
                .frame(width: 38, height: 22)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle().fill(.white).frame(width: 18, height: 18).padding(2).shadow(color: .black.opacity(0.2), radius: 1, y: 0.5)
                }
                .opacity(enabled ? 1 : 0.5)
                .animation(.easeOut(duration: 0.15), value: configuration.isOn)
        }
        .contentShape(Rectangle())
        .onTapGesture { if enabled { configuration.isOn.toggle() } }
        .focusable(enabled)
        .onKeyPress(.space) { if enabled { configuration.isOn.toggle() }; return .handled }
        // Assistive technologies see a real switch, with its label and state.
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }.toggleStyle(.switch)
        }
    }
}

/// A grouped container like System Settings' rows.
struct RowGroup<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title { Text(title).font(.headline).foregroundStyle(Theme.text).padding(.leading, 4) }
            VStack(spacing: 0) { content }
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.outline.opacity(0.6)))
        }
    }
}

/// Kept for the Checklist and History rows: a plain grouped card.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.outline.opacity(0.6)))
    }
}

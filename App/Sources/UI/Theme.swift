import AppKit
import SwiftUI
import GameReadyCore

/// Every colour the app uses (docs/design.md). Views never hard-code a colour.
enum Theme {
    static let surface = dynamic(light: 0xF7F4EE, dark: 0x0F1826)
    static let card = dynamic(light: 0xFFFDF9, dark: 0x1A2638)
    static let text = dynamic(light: 0x1B2A41, dark: 0xEDEFF3)
    static let textVariant = dynamic(light: 0x55606E, dark: 0xB7C1CE)
    static let primary = dynamic(light: 0x2F6F69, dark: 0x8CC7BF)
    static let onPrimary = dynamic(light: 0xFFFFFF, dark: 0x0F1826)
    static let good = dynamic(light: 0x2E7D4F, dark: 0x7DD3A0)
    static let warn = dynamic(light: 0x8A5A00, dark: 0xF2C14E)
    static let bad = dynamic(light: 0xB3261E, dark: 0xF2938C)
    static let outline = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDark ? NSColor(hex: 0xEDEFF3, alpha: 0.14) : NSColor(hex: 0x1B2A41, alpha: 0.12)
    })

    static let cardRadius: CGFloat = 18
    static let buttonRadius: CGFloat = 14
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

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { $0.isDark ? NSColor(hex: dark) : NSColor(hex: light) })
    }
}

private extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }
}

private extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
                  blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
    }
}

/// A card: paper background, hairline border, no shadow.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.outline, lineWidth: 1))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(Theme.onPrimary)
            .background(Theme.primary.opacity(enabled ? (configuration.isPressed ? 0.85 : 1) : 0.4),
                        in: RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Theme.buttonRadius))
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(Theme.primary)
            .background(Theme.primary.opacity(configuration.isPressed ? 0.12 : 0.0001),
                        in: RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous).strokeBorder(Theme.primary.opacity(0.6), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: Theme.buttonRadius))
    }
}

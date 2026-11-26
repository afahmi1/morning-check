import SwiftUI

/// Ash at night, paper by day. The scarab artwork stays independent of the UI palette.
struct DayBreakPalette {
    let canvas: Color
    let panel: Color
    let field: Color
    let ink: Color
    let muted: Color
    let rule: Color
    let outline: Color
    let accent: Color
    let selection: Color
    let steady: Color
    let caution: Color
    let destructive: Color

    init(_ scheme: ColorScheme) {
        let dark = scheme == .dark
        canvas = Self.color(dark ? 0x232322 : 0xF4EEDD)
        panel = Self.color(dark ? 0x2C2C2B : 0xFFFBF1)
        field = Self.color(dark ? 0x353533 : 0xEAE2CC)
        ink = Self.color(dark ? 0xEDE6D3 : 0x2E2C28)
        muted = Self.color(dark ? 0xC5BCAB : 0x5F584B)
        rule = Self.color(dark ? 0x47453F : 0xD9CFB6)
        outline = Self.color(dark ? 0x79766C : 0x877E69)
        accent = Self.color(dark ? 0xA48CFF : 0x943B16)
        selection = Self.color(dark ? 0x352E40 : 0xF1DDC7)
        steady = Self.color(dark ? 0xA3C997 : 0x39683E)
        caution = Self.color(dark ? 0xE0B25E : 0x80510F)
        destructive = Self.color(dark ? 0xFF9F9D : 0x9E3333)
    }

    private static func color(_ rgb: UInt32) -> Color {
        Color(.sRGB, red: Double((rgb >> 16) & 255) / 255,
              green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255, opacity: 1)
    }
}

extension Font {
    static let dayBreakDisplay = Font.system(.largeTitle, design: .serif, weight: .semibold)
    static let dayBreakSection = Font.system(.title2, design: .serif, weight: .semibold)
    static let dayBreakWristTitle = Font.system(.title3, design: .serif, weight: .semibold)
}

struct DayBreakRule: View {
    let palette: DayBreakPalette

    var body: some View {
        Rectangle().fill(palette.rule).frame(height: 1).accessibilityHidden(true)
    }
}

extension View {
    func dayBreakPanel(_ palette: DayBreakPalette, radius: CGFloat = 12) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return background(palette.panel, in: shape)
            .overlay { shape.strokeBorder(palette.rule, lineWidth: 1).allowsHitTesting(false) }
    }
}

struct DayBreakActionStyle: ButtonStyle {
    enum Prominence { case primary, secondary }

    let palette: DayBreakPalette
    var prominence: Prominence = .primary
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        let solid = prominence == .primary && enabled
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(solid ? palette.canvas : (enabled ? palette.ink : palette.muted))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(minWidth: 44, minHeight: 44)
            .background(solid ? palette.ink : palette.field, in: Capsule())
            .overlay { Capsule().strokeBorder(solid ? .clear : palette.outline, lineWidth: 1).allowsHitTesting(false) }
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.76 : 1)
    }
}

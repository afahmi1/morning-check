import SwiftUI

/// DayBreak roles, shared by the phone and Watch. The scarab artwork stays independent.
struct DayBreakPalette {
    let theme: DayBreakAppearance.Theme
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
    let onAccent: Color

    init(_ scheme: ColorScheme, appearance: DayBreakAppearance = .init()) {
        theme = appearance.theme
        switch theme {
        case .thermocline:
            let colors = Thermocline.Palette.self
            canvas = colors.bgToken.color(for: scheme)
            panel = colors.surface1Token.color(for: scheme)
            field = Thermocline.surface3
            ink = colors.textToken.color(for: scheme)
            muted = Thermocline.text2
            rule = ink.opacity(0.10)
            outline = colors.text3Token.color(for: scheme).opacity(0.7)
            accent = appearance.accent.color(for: scheme)
            onAccent = appearance.accent.onColor(for: scheme)
            selection = accent.opacity(0.14)
            steady = Thermocline.success
            caution = appearance.accent.spark(for: scheme)
            destructive = Thermocline.danger
        case .paperAsh:
            // The exact Paper and Ash colors from 330f44c.
            let dark = scheme == .dark
            canvas = Self.color(dark ? 0x232322 : 0xF4EEDD)
            panel = Self.color(dark ? 0x2C2C2B : 0xFFFBF1)
            field = Self.color(dark ? 0x353533 : 0xEAE2CC)
            ink = Self.color(dark ? 0xEDE6D3 : 0x2E2C28)
            muted = Self.color(dark ? 0xC5BCAB : 0x5F584B)
            rule = Self.color(dark ? 0x47453F : 0xD9CFB6)
            outline = Self.color(dark ? 0x79766C : 0x877E69)
            accent = Self.color(dark ? 0xA48CFF : 0x943B16)
            onAccent = dark ? canvas : panel
            selection = Self.color(dark ? 0x352E40 : 0xF1DDC7)
            steady = Self.color(dark ? 0xA3C997 : 0x39683E)
            caution = Self.color(dark ? 0xE0B25E : 0x80510F)
            destructive = Self.color(dark ? 0xFF9F9D : 0x9E3333)
        }
    }

    private static func color(_ rgb: UInt32) -> Color {
        Color(.sRGB, red: Double((rgb >> 16) & 255) / 255,
              green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255, opacity: 1)
    }

    var displayFont: Font { theme == .paperAsh ? .system(.largeTitle, design: .serif, weight: .semibold) : .largeTitle.weight(.medium) }
    var sectionFont: Font { theme == .paperAsh ? .system(.title2, design: .serif, weight: .semibold) : .title2.weight(.medium) }
    var wristTitleFont: Font { theme == .paperAsh ? .system(.title3, design: .serif, weight: .semibold) : .title3.weight(.medium) }
    var numberFont: Font { theme == .paperAsh ? displayFont.monospacedDigit() : .system(.largeTitle, design: .monospaced, weight: .medium) }
    var numberSectionFont: Font { theme == .paperAsh ? sectionFont.monospacedDigit() : .system(.title2, design: .monospaced, weight: .medium) }
    var choiceFont: Font { theme == .paperAsh ? .headline.monospacedDigit() : .system(.headline, design: .monospaced, weight: .medium) }
    var wristChoiceFont: Font { theme == .paperAsh ? choiceFont.weight(.semibold) : choiceFont }
    var axisFont: Font { theme == .paperAsh ? .caption2 : .system(.caption2, design: .monospaced) }
    var workspaceRadius: CGFloat { theme == .paperAsh ? 9 : Thermocline.Radius.sm }
    var fieldRadius: CGFloat { theme == .paperAsh ? 10 : Thermocline.Radius.sm }
}

struct DayBreakRule: View {
    let palette: DayBreakPalette

    var body: some View {
        Rectangle().fill(palette.rule).frame(height: 1).accessibilityHidden(true)
    }
}

extension View {
    func dayBreakPanel(_ palette: DayBreakPalette, radius: CGFloat = Thermocline.Radius.md) -> some View {
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let solid = prominence == .primary && enabled
        let classic = palette.theme == .paperAsh
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(solid ? (classic ? palette.canvas : palette.onAccent) : (enabled ? palette.ink : palette.muted))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(minWidth: 44, minHeight: 44)
            .background(solid ? (classic ? palette.ink : palette.accent) : palette.field, in: Capsule())
            .overlay { Capsule().strokeBorder(solid ? .clear : palette.outline, lineWidth: 1).allowsHitTesting(false) }
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.76 : 1)
            .animation(reduceMotion || classic ? nil : Thermocline.Motion.micro, value: configuration.isPressed)
    }
}

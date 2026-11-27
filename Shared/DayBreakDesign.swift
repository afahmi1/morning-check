import SwiftUI

/// Thermocline roles. Colors are Thermocline's dynamic light/dark tokens (dark on watchOS).
/// The scarab artwork stays independent of the UI palette.
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
        canvas = Thermocline.bg
        panel = Thermocline.surface1
        field = Thermocline.surface3
        ink = Thermocline.text
        muted = Thermocline.text2
        rule = Thermocline.line
        outline = Thermocline.text3.opacity(0.7)
        accent = Thermocline.lead
        selection = Thermocline.lead.opacity(0.14)
        steady = Thermocline.success
        caution = Thermocline.spark
        destructive = Thermocline.danger
    }
}

extension Font {
    static let dayBreakDisplay = Thermocline.Font.ui(34, weight: .medium, relativeTo: .largeTitle)
    static let dayBreakSection = Thermocline.Font.ui(22, weight: .medium, relativeTo: .title2)
    static let dayBreakWristTitle = Thermocline.Font.ui(18, weight: .medium, relativeTo: .title3)
    /// Tabular numerals: restedness choices and the 0-100 score.
    static let dayBreakNumber = Thermocline.Font.mono(34, weight: .medium, relativeTo: .largeTitle)
    static let dayBreakNumberSection = Thermocline.Font.mono(22, weight: .medium, relativeTo: .title2)
    static let dayBreakChoice = Thermocline.Font.mono(17, weight: .medium, relativeTo: .headline)
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
            .animation(Thermocline.Motion.micro, value: configuration.isPressed)
    }
}

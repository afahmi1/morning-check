// Thermocline v1.0 design tokens for SwiftUI. iOS 17+, macOS 14+, watchOS 10+. No dependencies.
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public enum Thermocline {

    // MARK: Colors (dynamic light/dark; watchOS uses dark values)
    public enum Palette {
        static func hex(_ v: UInt32) -> (r: Double, g: Double, b: Double) {
            (Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
        }
        static func make(light: UInt32, dark: UInt32) -> Color {
            #if os(watchOS)
            let c = hex(dark)
            return Color(red: c.r, green: c.g, blue: c.b)
            #elseif canImport(UIKit)
            return Color(UIColor { trait in
                let c = hex(trait.userInterfaceStyle == .dark ? dark : light)
                return UIColor(red: c.r, green: c.g, blue: c.b, alpha: 1)
            })
            #elseif canImport(AppKit)
            return Color(NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                let c = hex(isDark ? dark : light)
                return NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1)
            })
            #else
            let c = hex(dark)
            return Color(red: c.r, green: c.g, blue: c.b)
            #endif
        }
    }

    public static let bg         = Palette.make(light: 0xE4E0D7, dark: 0x13181D)
    public static let surface1   = Palette.make(light: 0xEEEAE1, dark: 0x1A2026)
    public static let surface2   = Palette.make(light: 0xF5F1E7, dark: 0x22272B)
    public static let surface3   = Palette.make(light: 0xDCD8CF, dark: 0x2A3036)
    public static let text       = Palette.make(light: 0x13181D, dark: 0xEBE7DE)
    public static let text2      = Palette.make(light: 0x474047, dark: 0xB5AEA5)
    public static let text3      = Palette.make(light: 0x645C64, dark: 0x9D959D)
    public static let lead       = Palette.make(light: 0x186377, dark: 0x6BCDC2)
    public static let onLead     = Palette.make(light: 0xEBE7DE, dark: 0x13181D)
    public static let link       = Palette.make(light: 0x186377, dark: 0x6FB3D0)
    public static let macawMid   = Palette.make(light: 0x2D8591, dark: 0x37949D)
    /// Macaw gold. Once per view.
    public static let spark      = Palette.make(light: 0xAE6B00, dark: 0xF4B21F)
    public static let danger     = Palette.make(light: 0xCE0A04, dark: 0xE62F10)
    public static let success    = Palette.make(light: 0x4B6801, dark: 0xA3C54F)
    public static let secondary  = Palette.make(light: 0x693D24, dark: 0xD0986A)
    public static let warm       = Palette.make(light: 0xA73B00, dark: 0xED732D)
    public static let plum       = Palette.make(light: 0x6C3D6B, dark: 0xB985B7)
    /// Hairlines: text color at 10% / 18%.
    public static let line       = text.opacity(0.10)
    public static let lineStrong = text.opacity(0.18)

    // MARK: Radius, Space
    public enum Radius {
        public static let xs: CGFloat = 4, sm: CGFloat = 8, md: CGFloat = 12, lg: CGFloat = 18, xl: CGFloat = 28
        public static let full: CGFloat = 9999
    }
    public enum Space {
        public static let s1: CGFloat = 4, s2: CGFloat = 8, s3: CGFloat = 12, s4: CGFloat = 16
        public static let s5: CGFloat = 24, s6: CGFloat = 32, s7: CGFloat = 48, s8: CGFloat = 64, s9: CGFloat = 96
    }

    // MARK: Motion (120/200/320ms, no bounce)
    public enum Motion {
        public static let micro = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.12)
        public static let standard = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.20)
        public static let large = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.32)
        public static let exit = Animation.timingCurve(0.4, 0, 1, 1, duration: 0.20)
    }

    // MARK: Fonts (Geist / JetBrains Mono if registered, else system; scales with Dynamic Type)
    public enum Font {
        static func isRegistered(_ name: String) -> Bool {
            #if canImport(UIKit)
            return UIFont(name: name, size: 12) != nil
            #elseif canImport(AppKit)
            return NSFont(name: name, size: 12) != nil
            #else
            return false
            #endif
        }
        public static func ui(_ size: CGFloat, weight: SwiftUI.Font.Weight = .regular, relativeTo style: SwiftUI.Font.TextStyle = .body) -> SwiftUI.Font {
            let name = weight == .regular ? "Geist-Regular" : (weight == .semibold || weight == .bold ? "Geist-SemiBold" : "Geist-Medium")
            if isRegistered(name) { return .custom(name, size: size, relativeTo: style) }
            return .system(size: size, weight: weight)
        }
        public static func mono(_ size: CGFloat, weight: SwiftUI.Font.Weight = .regular, relativeTo style: SwiftUI.Font.TextStyle = .body) -> SwiftUI.Font {
            let name = weight == .regular ? "JetBrainsMono-Regular" : "JetBrainsMono-Medium"
            if isRegistered(name) { return .custom(name, size: size, relativeTo: style) }
            return .system(size: size, weight: weight, design: .monospaced)
        }
        public static var body: SwiftUI.Font { ui(15) }
        public static var headline: SwiftUI.Font { ui(24, weight: .medium, relativeTo: .title2) }
        public static var display: SwiftUI.Font { ui(44, weight: .medium, relativeTo: .largeTitle) }
        /// 11pt mono label; apply `.textCase(.uppercase).tracking(1.3)` at the call site.
        public static var label: SwiftUI.Font { mono(11, weight: .medium, relativeTo: .caption) }
        public static var data: SwiftUI.Font { mono(13, relativeTo: .footnote) }
    }
}

// MARK: - Glass (one layer at a time)
public struct ThermoclineGlass: ViewModifier {
    var radius: CGFloat
    var thin: Bool
    public func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background(thin ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(.regularMaterial), in: shape)
            .overlay(shape.strokeBorder(Thermocline.text.opacity(0.12), lineWidth: 1))
    }
}

public extension View {
    func thermoclineGlass(radius: CGFloat = Thermocline.Radius.md, thin: Bool = false) -> some View {
        modifier(ThermoclineGlass(radius: radius, thin: thin))
    }
}

// MARK: - Lateral line divider: five pores then a hairline
public struct LateralLine: View {
    public var sparkLast = false
    public init(sparkLast: Bool = false) { self.sparkLast = sparkLast }
    public var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(0..<5, id: \.self) { i in
                    Circle().fill(sparkLast && i == 4 ? Thermocline.spark : Thermocline.text3)
                        .frame(width: 3, height: 3)
                }
            }
            Rectangle().fill(Thermocline.lineStrong).frame(height: 1)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Finch bars: 2pt on, 2pt off progress
public struct FinchBars: View {
    public var progress: Double
    public var height: CGFloat = 8
    public init(progress: Double, height: CGFloat = 8) { self.progress = progress; self.height = height }
    public var body: some View {
        GeometryReader { geo in
            let n = max(Int(geo.size.width / 4), 1)
            let filled = Int((Double(n) * min(max(progress, 0), 1)).rounded())
            HStack(spacing: 2) {
                ForEach(0..<n, id: \.self) { i in
                    Rectangle()
                        .fill(i < filled ? Thermocline.lead : Thermocline.text3.opacity(0.35))
                        .frame(width: 2)
                }
            }
        }
        .frame(height: height)
        .animation(Thermocline.Motion.large, value: progress)
        .accessibilityElement()
        .accessibilityValue(Text("\(Int((progress * 100).rounded())) percent"))
    }
}

// MARK: - Horizon-eye mark: circle, horizon line, spark dot right of center
public struct HorizonEyeMark: View {
    public var monochrome = false
    public init(monochrome: Bool = false) { self.monochrome = monochrome }
    public var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height, cx = w / 2, cy = h / 2
            let r = min(h * 0.355, w * 0.21)
            let lw = max(h * 0.058, 1)
            let ink = GraphicsContext.Shading.color(Thermocline.text)
            ctx.stroke(Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r)), with: ink, lineWidth: lw)
            var line = Path()
            line.move(to: CGPoint(x: w * 0.045, y: cy)); line.addLine(to: CGPoint(x: w * 0.955, y: cy))
            ctx.stroke(line, with: ink, style: StrokeStyle(lineWidth: lw, lineCap: .round))
            let dr = r * 0.26
            ctx.fill(Path(ellipseIn: CGRect(x: cx + r * 0.48 - dr, y: cy - dr, width: 2 * dr, height: 2 * dr)),
                     with: .color(monochrome ? Thermocline.text : Thermocline.spark))
        }
        .aspectRatio(44.0 / 26.0, contentMode: .fit)
        .accessibilityLabel("Thermocline")
    }
}

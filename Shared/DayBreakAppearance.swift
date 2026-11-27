import SwiftUI

struct DayBreakAppearance: Equatable {
    enum Theme: String, CaseIterable, Identifiable {
        case thermocline, paperAsh

        var id: Self { self }
        var title: String { self == .thermocline ? "Thermocline" : "Paper & Ash" }

        func name(for scheme: ColorScheme) -> String {
            self == .thermocline ? title : (scheme == .dark ? "Ash" : "Paper")
        }
    }

    var theme: Theme = .thermocline
    var mode: Thermocline.Mode = .system
    var accent: Thermocline.Accent = .crown

    var summary: String {
        switch theme {
        case .thermocline: "\(theme.title) · \(accent.displayName) · \(mode.displayName)"
        case .paperAsh: "\(theme.title) · \(mode.displayName)"
        }
    }

    private static let defaultsKey = "dayBreakAppearance"

    static func load(from defaults: UserDefaults?) -> Self {
        Self(payload: defaults?.dictionary(forKey: defaultsKey)) ?? Self()
    }

    func save(to defaults: UserDefaults?) {
        defaults?.set(payload, forKey: Self.defaultsKey)
    }

    var payload: [String: String] {
        ["theme": theme.rawValue, "mode": mode.rawValue, "accent": accent.rawValue]
    }

    init(theme: Theme = .thermocline, mode: Thermocline.Mode = .system, accent: Thermocline.Accent = .crown) {
        self.theme = theme
        self.mode = mode
        self.accent = accent
    }

    init?(payload: Any?) {
        guard let fields = payload as? [String: String],
              let theme = fields["theme"].flatMap(Theme.init(rawValue:)),
              let mode = fields["mode"].flatMap(Thermocline.Mode.init(rawValue:)),
              let accent = fields["accent"].flatMap(Thermocline.Accent.init(rawValue:)) else { return nil }
        self.init(theme: theme, mode: mode, accent: accent)
    }
}

private struct DayBreakPaletteKey: EnvironmentKey {
    static let defaultValue = DayBreakPalette(.light)
}

extension EnvironmentValues {
    var dayBreakPalette: DayBreakPalette {
        get { self[DayBreakPaletteKey.self] }
        set { self[DayBreakPaletteKey.self] = newValue }
    }
}

private struct DayBreakAppearanceStyle: ViewModifier {
    let appearance: DayBreakAppearance
    @Environment(\.colorScheme) private var systemScheme

    func body(content: Content) -> some View {
        #if os(watchOS)
        let scheme: ColorScheme = .dark
        #else
        let scheme = appearance.mode.colorScheme ?? systemScheme
        #endif
        let palette = DayBreakPalette(scheme, appearance: appearance)
        content
            .environment(\.dayBreakPalette, palette)
            .thermoclineAccent(appearance.accent)
            .tint(palette.accent)
            #if os(iOS)
            .preferredColorScheme(appearance.mode.colorScheme)
            #endif
    }
}

extension View {
    /// Apply once per presentation so native controls and DayBreak's palette update together.
    func dayBreakAppearance(_ appearance: DayBreakAppearance) -> some View {
        modifier(DayBreakAppearanceStyle(appearance: appearance))
    }
}

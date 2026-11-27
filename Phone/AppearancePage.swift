import SwiftUI

struct AppearancePage: View {
    @ObservedObject var model: PhoneModel
    @Environment(\.dayBreakPalette) private var palette
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var appearance: DayBreakAppearance { model.appearance }
    private var previewScheme: ColorScheme { appearance.mode.colorScheme ?? scheme }
    private var stackChoices: Bool { typeSize >= .xxxLarge }
    private var choiceLayout: AnyLayout {
        stackChoices ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(alignment: .top, spacing: 8))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                themePicker
                modePicker
                accentPicker
            }
            .foregroundStyle(palette.ink)
            .padding(.vertical, 20).dayBreakPhoneGutter()
        }
        .background(palette.canvas.ignoresSafeArea())
        .navigationTitle("Appearance").navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(palette.canvas, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .sensoryFeedback(.selection, trigger: appearance)
    }

    private var themePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            heading("Theme")
            choiceLayout {
                ForEach(DayBreakAppearance.Theme.allCases) { theme in
                    choice(theme.title, selected: theme == appearance.theme, isDefault: theme == .thermocline) {
                        update(\.theme, to: theme)
                    } preview: {
                        DayBreakThemeThumbnail(theme: theme, scheme: previewScheme, accent: appearance.accent)
                    }
                    .accessibilityHint(theme == .paperAsh ? "Original colors and serif prompts" : "")
                    .accessibilityIdentifier("theme-\(theme.rawValue)")
                }
            }
        }
    }

    private var modePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            heading("Mode")
            choiceLayout {
                ForEach(Thermocline.Mode.allCases) { mode in
                    choice(mode.displayName, selected: mode == appearance.mode) {
                        update(\.mode, to: mode)
                    } preview: {
                        if appearance.theme == .thermocline {
                            ModeThumbnail(mode: mode, accent: appearance.accent)
                        } else {
                            PaperAshModeThumbnail(mode: mode)
                        }
                    }
                    .accessibilityHint(mode == .system ? "Follows your iPhone’s appearance" : "")
                    .accessibilityIdentifier("mode-\(mode.rawValue)")
                }
            }
            Text("Your Watch always uses the dark palette.")
                .font(.footnote).foregroundStyle(palette.muted)
        }
    }

    private var accentPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            heading("Accent")
            if appearance.theme == .thermocline {
                let count = typeSize >= .accessibility3 ? 1 : (stackChoices ? 2 : 4)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4, alignment: .top), count: count), spacing: 4) {
                    ForEach(Thermocline.Accent.allCases) { accent in
                        let selected = accent == appearance.accent
                        Button { update(\.accent, to: accent) } label: {
                            VStack(spacing: 0) {
                                AccentSwatch(accent: accent, selected: selected).accessibilityHidden(true)
                                Text(accent.displayName)
                                    .font(.footnote.weight(selected ? .semibold : .regular))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, minHeight: 44).padding(.bottom, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(accent.displayName)
                        .accessibilityHint(accent.source)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                        .accessibilityIdentifier("accent-\(accent.rawValue)")
                    }
                }
                .padding(4).dayBreakPanel(palette)
            } else {
                HStack(spacing: 8) {
                    Circle().fill(palette.accent).frame(width: 28, height: 28)
                        .frame(width: 44, height: 44).accessibilityHidden(true)
                    Text(previewScheme == .dark ? "Fixed to Ash’s original violet." : "Fixed to Paper’s original burnt orange.")
                        .font(.subheadline).foregroundStyle(palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading).dayBreakPanel(palette)
            }
        }
    }

    private func heading(_ title: String) -> some View {
        Text(title).font(palette.sectionFont).accessibilityAddTraits(.isHeader)
    }

    private func choice<Preview: View>(
        _ title: String, selected: Bool, isDefault: Bool = false,
        action: @escaping () -> Void, @ViewBuilder preview: () -> Preview
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: Thermocline.Radius.md, style: .continuous)
        let layout = stackChoices ? AnyLayout(HStackLayout(spacing: 12)) : AnyLayout(VStackLayout(spacing: 7))
        return Button(action: action) {
            layout {
                preview().accessibilityHidden(true)
                VStack(alignment: stackChoices ? .leading : .center, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    if isDefault { Text("Default").font(.caption2).foregroundStyle(palette.muted) }
                }
                .frame(maxWidth: stackChoices ? .infinity : nil, alignment: .leading)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: isDefault || title == "Paper & Ash" ? 92 : 80)
            .background(palette.panel, in: shape)
            .overlay {
                shape.strokeBorder(selected ? palette.accent : palette.outline, lineWidth: selected ? 2 : 1)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.accent)
                        .padding(7)
                        .accessibilityHidden(true).allowsHitTesting(false)
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isDefault ? "Default" : "")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func update<Value>(_ key: WritableKeyPath<DayBreakAppearance, Value>, to value: Value) {
        var next = appearance
        next[keyPath: key] = value
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = reduceMotion
        withTransaction(transaction) { model.changeAppearance(to: next) }
    }
}

/// The same mini check-in in each theme, including a sample rating from the 1–5 scale.
private struct DayBreakThemeThumbnail: View {
    let theme: DayBreakAppearance.Theme
    let scheme: ColorScheme
    let accent: Thermocline.Accent

    var body: some View {
        let palette = DayBreakPalette(scheme, appearance: .init(theme: theme, accent: accent))
        let classic = theme == .paperAsh
        Group {
            if classic {
                PaperAshMiniScene(scheme: scheme)
                    .clipShape(.rect(cornerRadius: 8))
                    .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(palette.outline, lineWidth: 1) }
            } else {
                ThermoclineThemeThumbnail(accent: accent, colorScheme: scheme)
            }
        }
        .overlay(alignment: .topLeading) {
            Text("Rested?")
                .font(.system(size: 6.5, weight: .semibold, design: classic ? .serif : .default))
                .foregroundStyle(palette.ink).frame(width: 30, height: 14).offset(x: 5, y: 6)
        }
        .overlay(alignment: .topLeading) {
            Text("4/5").font(.system(size: 6.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(palette.onAccent).frame(width: 24, height: 10).offset(x: 27, y: 24)
        }
        .scaleEffect(1.15).frame(width: 65, height: 46)
    }
}

private struct PaperAshMiniScene: View {
    let scheme: ColorScheme

    var body: some View {
        let palette = DayBreakPalette(scheme, appearance: .init(theme: .paperAsh))
        ZStack(alignment: .topLeading) {
            palette.canvas
            RoundedRectangle(cornerRadius: 3)
                .fill(palette.panel)
                .overlay { RoundedRectangle(cornerRadius: 3).strokeBorder(palette.rule, lineWidth: 0.5) }
                .frame(width: 30, height: 14).offset(x: 5, y: 6)
            Capsule().fill(palette.accent).frame(width: 24, height: 10).offset(x: 27, y: 24)
        }
        .frame(width: 56, height: 40)
    }
}

private struct PaperAshModeThumbnail: View {
    let mode: Thermocline.Mode

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Thermocline.Radius.sm, style: .continuous)
        ZStack {
            PaperAshMiniScene(scheme: mode == .light ? .light : .dark)
            if mode == .system {
                PaperAshMiniScene(scheme: .light).clipShape(PaperAshSplit())
            }
        }
        .clipShape(shape)
        .overlay { shape.strokeBorder(.secondary.opacity(0.4), lineWidth: 1) }
    }
}

private struct PaperAshSplit: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: rect.origin)
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

import SwiftUI

struct SettingsPresentation: View {
    @ObservedObject var model: PhoneModel

    var body: some View {
        SettingsPage(model: model).dayBreakAppearance(model.appearance)
    }
}

private struct SettingsPage: View {
    @ObservedObject var model: PhoneModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dayBreakPalette) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var busy = false
    @State private var showErase = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    appearance
                    prompts
                    privacy
                }
                .foregroundStyle(palette.ink)
                .padding(.vertical, 20).dayBreakPhoneGutter()
            }
            .background(palette.canvas.ignoresSafeArea())
            .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(palette.canvas, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog("Erase the iPhone log?", isPresented: $showErase, titleVisibility: .visible) {
                Button("Erase iPhone log", role: .destructive) { model.eraseDiary() }
            } message: { Text("Deletes ratings and score entries here, not your Watch log or anything in Apple Health.") }
        }
    }

    private var appearance: some View {
        NavigationLink { AppearancePage(model: model) } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Appearance").font(.body.weight(.semibold)).foregroundStyle(palette.ink)
                    Text(model.appearance.summary).font(.subheadline).foregroundStyle(palette.muted)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    .foregroundStyle(palette.muted).accessibilityHidden(true)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .frame(minHeight: 44).contentShape(Rectangle())
            .dayBreakPanel(palette)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Appearance")
        .accessibilityValue(model.appearance.summary)
        .accessibilityIdentifier("appearance-settings")
    }

    private var prompts: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Prompt source").font(palette.sectionFont).accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(PromptMode.allCases) { mode in
                    if mode != PromptMode.allCases.first { DayBreakRule(palette: palette).padding(.horizontal, 14) }
                    Button {
                        busy = true
                        Task { await model.changePromptMode(to: mode); busy = false }
                    } label: {
                        HStack(spacing: 12) {
                            Text(mode.title).foregroundStyle(palette.ink)
                            Spacer(minLength: 6)
                            if model.mode == mode {
                                Image(systemName: "checkmark").font(.body.weight(.semibold))
                                    .foregroundStyle(palette.accent).accessibilityHidden(true)
                            }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .frame(minHeight: 48).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).disabled(busy)
                    .accessibilityAddTraits(model.mode == mode ? .isSelected : [])
                }
            }
            .dayBreakPanel(palette)
            Text("Sleep data mode waits for a recent Watch recording. It doesn’t detect waking in real time. Apple alert mode needs a separate iPhone Shortcut.")
                .font(.footnote).foregroundStyle(palette.muted)
            Button("Test Watch notification routing") { Task { await model.sendTestReminder() } }
                .buttonStyle(DayBreakActionStyle(palette: palette, prominence: .secondary))
            if !model.promptStatus.isEmpty { Text(model.promptStatus).font(.footnote).foregroundStyle(palette.muted) }
        }
    }

    private var privacy: some View {
        VStack(alignment: .leading, spacing: 12) {
            DayBreakRule(palette: palette)
            Text("Privacy").font(palette.sectionFont).accessibilityAddTraits(.isHeader)
            Text("No account, server or iCloud storage. Ratings go from your Watch to its paired iPhone. Sleep permission is read-only. Selected screenshots are read on device; DayBreak doesn’t keep the image.")
                .font(.subheadline).foregroundStyle(palette.muted)
            Button("Erase iPhone log", role: .destructive) { showErase = true }
                .foregroundStyle(palette.destructive).frame(minHeight: 44)
        }
    }
}

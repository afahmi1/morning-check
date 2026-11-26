import SwiftUI

struct SettingsPage: View {
    @ObservedObject var model: PhoneModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var busy = false
    @State private var showErase = false

    private var palette: DayBreakPalette { DayBreakPalette(scheme) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
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
        .tint(palette.accent)
    }

    private var prompts: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Prompt source").font(.dayBreakSection).accessibilityAddTraits(.isHeader)
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
            Text("Privacy").font(.dayBreakSection).accessibilityAddTraits(.isHeader)
            Text("No account, server or iCloud storage. Ratings go from your Watch to its paired iPhone. Sleep permission is read-only. Selected screenshots are read on device; DayBreak doesn’t keep the image.")
                .font(.subheadline).foregroundStyle(palette.muted)
            Button("Erase iPhone log", role: .destructive) { showErase = true }
                .foregroundStyle(palette.destructive).frame(minHeight: 44)
        }
    }
}

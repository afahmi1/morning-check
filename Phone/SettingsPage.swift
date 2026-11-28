import MorningCheckCore
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
                    scores
                    stages
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
            } message: { Text("Deletes ratings, scores and sleep stages here, not your Watch log or anything in Apple Health.") }
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
                    .accessibilityIdentifier("prompt-mode-\(mode.rawValue)")
                }
            }
            .dayBreakPanel(palette)
            Text("Watch sleep is a timing cue, not live wake detection. The iPhone alert needs a Shortcuts automation. Using both still sends at most one check-in per day.")
                .font(.footnote).foregroundStyle(palette.muted)
            Button("Test Watch notification routing") { Task { await model.sendTestReminder() } }
                .buttonStyle(DayBreakActionStyle(palette: palette, prominence: .secondary))
            if !model.promptStatus.isEmpty { Text(model.promptStatus).font(.footnote).foregroundStyle(palette.muted) }
            if model.mode != .off { recentPromptChecks }
        }
    }

    private var recentPromptChecks: some View {
        VStack(alignment: .leading, spacing: 8) {
            DayBreakRule(palette: palette)
            Text("Last prompt checks").font(.subheadline.weight(.semibold)).accessibilityAddTraits(.isHeader)
            if model.promptChecksUnavailable {
                Text("Saved checks couldn’t be read or written. DayBreak will retry.")
                    .font(.footnote).foregroundStyle(palette.muted)
            }
            ForEach(PromptSource.allCases.filter { model.mode.accepts($0) }) { source in
                VStack(alignment: .leading, spacing: 3) {
                    Text(source == .watchSleep ? "Watch sleep" : "iPhone alert").font(.footnote.weight(.semibold))
                    if let check = model.promptChecks[source] {
                        Text(check.outcome.description)
                        Text(check.checkedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                            .monospacedDigit()
                    } else if !model.promptChecksUnavailable {
                        Text("No signal recorded yet.")
                    }
                }
                .font(.footnote).foregroundStyle(palette.muted)
            }
        }
    }

    private var scores: some View {
        VStack(alignment: .leading, spacing: 8) {
            DayBreakRule(palette: palette)
            Toggle("Save alert scores automatically", isOn: Binding(get: { model.automaticAlertScores }, set: {
                model.changeAutomaticAlertScores(to: $0)
            }))
            .font(.body.weight(.semibold)).frame(minHeight: 44)
            .accessibilityIdentifier("automatic-alert-scores-setting")
            Text("Requires the iPhone Shortcuts bridge with Notification Body, Date, Title and App. Matching scores save without typing or confirmation, stay hidden until you rate, and are labeled as alert copies—not independently verified Health readings. Missing or unsupported alerts leave a gap.")
                .font(.footnote).foregroundStyle(palette.muted)
            if model.automaticAlertScores {
                Text(model.scoreImportMessage).font(.footnote).foregroundStyle(palette.muted)
                    .accessibilityIdentifier("automatic-score-import-status")
                if let time = model.lastScoreImportCheck {
                    Text(time, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .font(.footnote.monospacedDigit()).foregroundStyle(palette.muted)
                }
            }
        }
    }

    private var stages: some View {
        VStack(alignment: .leading, spacing: 8) {
            DayBreakRule(palette: palette)
            Toggle("Log sleep stages", isOn: Binding(get: { model.wakeStagesEnabled }, set: { enabled in
                Task { await model.changeWakeStageLogging(to: enabled) }
            }))
            .font(.body.weight(.semibold)).frame(minHeight: 44)
            .disabled(model.stageAccessInProgress)
            .accessibilityIdentifier("log-wake-stage-setting")
            Text("Read Apple Watch sleep stages for your rated mornings. This doesn’t turn on reminders. Turning it off keeps stages you’ve already logged.")
                .font(.footnote).foregroundStyle(palette.muted)
            if let message = model.stageAccessMessage {
                Text(message).font(.footnote).foregroundStyle(palette.muted)
            }
        }
    }

    private var privacy: some View {
        let stackFooter = typeSize >= .xxxLarge
        let footerLayout = stackFooter
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(spacing: 8))
        return VStack(alignment: .leading, spacing: 12) {
            DayBreakRule(palette: palette)
            Text("Privacy").font(palette.sectionFont).accessibilityAddTraits(.isHeader)
            Text("No account, server or iCloud storage. Ratings go from your Watch to its paired iPhone. Sleep permission is read-only. Selected screenshots are read on device; DayBreak doesn’t keep the image.")
                .font(.subheadline).foregroundStyle(palette.muted)
            footerLayout {
                Button("Erase iPhone log", role: .destructive) { showErase = true }
                    .foregroundStyle(palette.destructive).frame(minHeight: 44)
                versionFooter.frame(maxWidth: .infinity, alignment: stackFooter ? .leading : .trailing)
            }
        }
    }

    @ViewBuilder
    private var versionFooter: some View {
        if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
           let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String {
            Text("Version \(version) · Build \(build)")
                .font(.caption.monospacedDigit()).foregroundStyle(palette.muted)
                .accessibilityLabel("DayBreak version \(version), build \(build)")
                .accessibilityIdentifier("daybreak-version")
        }
    }
}

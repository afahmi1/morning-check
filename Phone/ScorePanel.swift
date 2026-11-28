import MorningCheckCore
import PhotosUI
import SwiftUI

struct ScorePanel: View {
    @ObservedObject var model: PhoneModel
    let day: String
    var active = true
    @Environment(\.dayBreakPalette) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var typed = ""
    @State private var proposed: Score?
    @State private var selected: PhotosPickerItem?
    @State private var feedback = ""
    @State private var scanning = false
    @FocusState private var typing: Bool

    private var actionLayout: AnyLayout {
        typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
    }

    var body: some View {
        let row = model.disk.diary[day]
        if row?.rating != nil {
            VStack(alignment: .leading, spacing: 12) {
                Text("Apple Sleep Score").font(palette.sectionFont).accessibilityAddTraits(.isHeader)
                if let score = row?.score {
                    Text("\(score.value) / 100").font(palette.numberFont)
                        .accessibilityLabel("\(score.value) of 100")
                        .accessibilityIdentifier("confirmed-apple-score")
                    Text(score.source.label).font(.footnote).foregroundStyle(palette.muted)
                    Button("Remove score", role: .destructive) { model.clearScore(day: day) }
                        .font(.subheadline.weight(.medium)).foregroundStyle(palette.destructive)
                        .frame(minHeight: 44, alignment: .leading)
                } else {
                    Text(model.automaticAlertScores
                         ? "Waiting for a matching Health alert. A supported score saves automatically, without typing or confirmation."
                         : "Apple Health doesn’t share the exact score with DayBreak. Enter the score for \(day), or read it from a screenshot.")
                        .font(.subheadline).foregroundStyle(palette.muted)
                    if !model.automaticAlertScores {
                    if let candidate = proposed ?? row?.candidate {
                        suggestion(candidate)
                    }
                    actionLayout {
                        TextField("Score (0–100)", text: $typed,
                                  prompt: Text("Score (0–100)").foregroundStyle(palette.muted))
                            .keyboardType(.numberPad).monospacedDigit()
                            .focused($typing).accessibilityIdentifier("apple-score-field")
                            .padding(.horizontal, 12).padding(.vertical, 8).frame(minHeight: 44)
                            .background(palette.field, in: RoundedRectangle(cornerRadius: palette.fieldRadius, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: palette.fieldRadius, style: .continuous)
                                    .strokeBorder(typing ? palette.accent : palette.outline, lineWidth: typing ? 2 : 1)
                                    .allowsHitTesting(false)
                            }
                        Button("Save score") {
                            guard let number = ScoreText.manual(typed), let score = Score(number, source: .manual) else { return }
                            confirm(score)
                        }
                        .buttonStyle(DayBreakActionStyle(palette: palette))
                        .disabled(ScoreText.manual(typed) == nil)
                    }
                    PhotosPicker(selection: $selected, matching: .images) {
                        Label(scanning ? "Reading image…" : "Read screenshot", systemImage: "text.viewfinder")
                    }
                    .buttonStyle(DayBreakActionStyle(palette: palette, prominence: .secondary))
                    .disabled(scanning)
                    }
                    if !feedback.isEmpty { Text(feedback).font(.footnote).foregroundStyle(palette.muted) }
                }
            }
            .foregroundStyle(palette.ink)
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .dayBreakPanel(palette)
            .onChange(of: active) { _, isActive in if !isActive { typing = false } }
            .onChange(of: selected) { _, item in
                guard let item else { return }
                proposed = nil; feedback = ""; scanning = true
                Task {
                    defer { scanning = false; selected = nil }
                    guard let data = try? await item.loadTransferable(type: Data.self),
                          let number = await ScoreOCR.read(data) else {
                        feedback = "No clear Sleep Score found. Use a cropped English-language card or type the number."
                        return
                    }
                    proposed = Score(number, source: .screenshot)
                }
            }
        }
    }

    private func suggestion(_ candidate: Score) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Detected \(candidate.value) / 100", systemImage: "checkmark.magnifyingglass")
                .font(palette.choiceFont).foregroundStyle(palette.accent)
            Text(candidate.source == .notification
                 ? "Read from an iPhone alert, not Apple Health. Confirm the number and wake date in Health."
                 : "Check the number and wake date against Apple Health before saving.")
                .font(.footnote).foregroundStyle(palette.muted)
            actionLayout {
                Button("Confirm \(candidate.value)") { confirm(candidate) }
                    .buttonStyle(DayBreakActionStyle(palette: palette))
                Button("Discard") { proposed = nil; model.clearScore(day: day) }
                    .buttonStyle(DayBreakActionStyle(palette: palette, prominence: .secondary))
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.selection, in: RoundedRectangle(cornerRadius: palette.fieldRadius, style: .continuous))
    }

    private func confirm(_ score: Score) {
        if model.confirmScore(score, day: day) { typed = ""; proposed = nil; feedback = ""; typing = false }
    }
}

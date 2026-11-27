import MorningCheckCore
import SwiftUI

struct WakeStagePanel: View {
    @ObservedObject var model: PhoneModel
    let day: String
    @Environment(\.dayBreakPalette) private var palette

    var body: some View {
        if let morning = model.disk.diary[day], let rating = morning.rating {
            VStack(alignment: .leading, spacing: 8) {
                Text("Last recorded sleep stage").font(palette.sectionFont).accessibilityAddTraits(.isHeader)
                if let wake = morning.wakeStage, wake.matches(rating) {
                    Text(wake.stage.label).font(palette.numberSectionFont).foregroundStyle(palette.accent)
                        .accessibilityIdentifier("logged-wake-stage")
                    Text("Watch stage ended at \(Text(wake.endedAt, style: .time))")
                        .font(.footnote).foregroundStyle(palette.muted)
                        .environment(\.timeZone, TimeZone(identifier: rating.timeZone) ?? .current)
                }
                Text("The last stage Apple Watch recorded before your check-in. It’s an estimate, not the exact moment you woke.")
                    .font(.subheadline).foregroundStyle(palette.muted)
                if model.wakeStagesEnabled {
                    let state = model.stageReads[day]
                    if let message = message(for: state, alreadyLogged: morning.wakeStage != nil) {
                        Text(message).font(.footnote).foregroundStyle(palette.muted)
                    }
                    Button(state == .reading ? "Reading Health…" : "Refresh from Health") {
                        Task { await model.refreshWakeStage(on: day) }
                    }
                    .buttonStyle(DayBreakActionStyle(palette: palette, prominence: .secondary))
                    .disabled(state == .reading)
                } else {
                    Button("Enable sleep stage logging") {
                        Task {
                            await model.changeWakeStageLogging(to: true)
                            await model.refreshWakeStage(on: day)
                        }
                    }
                    .buttonStyle(DayBreakActionStyle(palette: palette, prominence: .secondary))
                    .disabled(model.stageAccessInProgress)
                    if let message = model.stageAccessMessage {
                        Text(message).font(.footnote).foregroundStyle(palette.muted)
                    }
                }
            }
            .foregroundStyle(palette.ink)
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .dayBreakPanel(palette)
        }
    }

    private func message(for state: StageReadState?, alreadyLogged: Bool) -> String? {
        switch state {
        case .reading: nil
        case .missing:
            alreadyLogged ? "No new matching stage. The earlier reading is still logged."
                          : "No matching stage yet. Try after your Watch syncs, or check DayBreak’s Sleep access in Health."
        case .unavailable(.healthLocked): "Unlock your iPhone to read sleep stages from Health."
        case .unavailable(.healthUnavailable): "Health data is unavailable on this device."
        case .unavailable: "Couldn’t read sleep stages. Check DayBreak’s Sleep access in Health."
        case .saveFailed: "Couldn’t save the stage locally. Try again."
        case nil: alreadyLogged ? nil : "Waiting for a matching stage from Health."
        }
    }
}

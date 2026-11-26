import MorningCheckCore
import SwiftUI

@main
@MainActor
struct MorningCheckWatchApp: App {
    @StateObject private var model = WatchModel.shared

    init() {
        PromptStyle.register()
        WatchModel.shared.start()
    }

    var body: some Scene {
        WindowGroup { WatchCheckIn(model: model) }
    }
}

private struct WatchCheckIn: View {
    @ObservedObject var model: WatchModel
    @Environment(\.scenePhase) private var phase
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showErase = false

    private let palette = DayBreakPalette(.dark)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    DayBreakBrand(iconSize: 17).font(.footnote.weight(.semibold)).foregroundStyle(palette.muted)
                    if let rating = model.today {
                        saved(rating)
                    } else {
                        choices
                    }
                    if !model.disk.diary.rows.isEmpty {
                        DayBreakRule(palette: palette)
                        Button("Erase Watch log", role: .destructive) { showErase = true }
                            .font(.footnote).foregroundStyle(palette.destructive)
                            .frame(minHeight: 44, alignment: .leading)
                    }
                    if let error = model.error {
                        Label(error, systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(palette.destructive)
                    }
                }
                .foregroundStyle(palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4).padding(.bottom, 6)
            }
            .containerBackground(palette.canvas, for: .navigation)
            .tint(palette.accent)
            .confirmationDialog("Erase Watch log?", isPresented: $showErase, titleVisibility: .visible) {
                Button("Erase Watch log", role: .destructive) { model.eraseLocal() }
            } message: { Text("This does not erase a rating already received by your iPhone.") }
            .onChange(of: phase, initial: true) { _, new in if new == .active { model.sendPending() } }
        }
    }

    private var choices: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("How rested?").font(.dayBreakWristTitle).accessibilityAddTraits(.isHeader)
            Text("Before Apple’s score.").font(.caption2).foregroundStyle(palette.muted)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 68 : 44), spacing: 4)], spacing: 4) {
                ForEach(Restedness.allCases, id: \.rawValue) { value in
                    Button { model.record(value) } label: {
                        Text("\(value.rawValue)").font(.headline.monospacedDigit().weight(.semibold))
                            .foregroundStyle(palette.accent)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .dayBreakPanel(palette, radius: 10)
                            .contentShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(value.rawValue) of 5, \(value.label)")
                    .accessibilityIdentifier("watch-rating-\(value.rawValue)")
                }
            }
            .frame(maxWidth: 184, alignment: .leading)
            Text("1 Not at all / 5 Very well").font(.caption2).foregroundStyle(palette.muted)
        }
    }

    private func saved(_ rating: Rating) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Rating saved").font(.dayBreakWristTitle).accessibilityAddTraits(.isHeader)
            Text("\(rating.value.rawValue) / 5").font(.dayBreakDisplay.monospacedDigit())
                .foregroundStyle(palette.accent).accessibilityLabel("\(rating.value.rawValue) of 5")
            Text(rating.value.label).font(.footnote).foregroundStyle(palette.muted)
            if model.disk.acknowledged.contains(rating.id) {
                Label("Received by iPhone", systemImage: "checkmark.circle").font(.footnote).foregroundStyle(palette.steady)
            } else {
                Text("Saved on Watch. Waiting for iPhone.").font(.footnote).foregroundStyle(palette.muted)
                Button("Retry sync") { model.sendPending() }
                    .buttonStyle(DayBreakActionStyle(palette: palette, prominence: .secondary))
            }
        }
    }
}

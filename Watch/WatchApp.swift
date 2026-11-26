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
    @State private var showErase = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 9) {
                    if let rating = model.today {
                        DayBreakBrand(iconSize: 18)
                            .font(.caption2.monospaced().weight(.semibold)).foregroundStyle(.yellow)
                        Text("\(rating.value.rawValue) / 5").font(.system(.largeTitle, design: .rounded, weight: .bold))
                        Text(rating.value.label).font(.headline)
                        if model.disk.acknowledged.contains(rating.id) {
                            Label("Received by iPhone", systemImage: "checkmark.circle").font(.footnote)
                        } else {
                            Text("Saved on Watch. Waiting for iPhone.").font(.footnote).foregroundStyle(.secondary)
                            Button("Retry sync") { model.sendPending() }.font(.footnote)
                        }
                    } else {
                        Text("How rested do you feel?").font(.system(.headline, design: .rounded, weight: .bold))
                        Text("Rate before seeing Sleep Score.").font(.caption2).foregroundStyle(.secondary)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                            ForEach(Restedness.allCases, id: \.rawValue) { value in
                                Button { model.record(value) } label: {
                                    Text("\(value.rawValue)").font(.title3.monospacedDigit().bold()).foregroundStyle(.yellow)
                                        .frame(maxWidth: .infinity, minHeight: 43)
                                        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(value.rawValue): \(value.label)")
                                .accessibilityIdentifier("watch-rating-\(value.rawValue)")
                            }
                        }
                        Text("1 Not at all   ·   5 Very well").font(.caption2).foregroundStyle(.secondary)
                    }
                    if !model.disk.diary.rows.isEmpty {
                        Button("Erase Watch log", role: .destructive) { showErase = true }.font(.footnote)
                    }
                    if let error = model.error { Text(error).font(.footnote).foregroundStyle(.red) }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
            }
            .containerBackground(Color(red: 0.10, green: 0.13, blue: 0.19).gradient, for: .navigation)
            .confirmationDialog("Erase Watch log?", isPresented: $showErase, titleVisibility: .visible) {
                Button("Erase Watch log", role: .destructive) { model.eraseLocal() }
            } message: { Text("This does not erase a rating already received by your iPhone.") }
            .onChange(of: phase, initial: true) { _, new in if new == .active { model.sendPending() } }
        }
    }
}

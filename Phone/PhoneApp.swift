import Charts
import MorningCheckCore
import PhotosUI
import SwiftUI

@main
@MainActor
struct MorningCheckApp: App {
    @UIApplicationDelegateAdaptor(LaunchDelegate.self) private var delegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = PhoneModel.shared

    var body: some Scene {
        WindowGroup {
            MorningHome(model: model)
                .onChange(of: scenePhase, initial: true) { _, phase in
                    if phase == .active { Task { await model.evaluateSleep() } }
                }
        }
    }
}

@MainActor
final class LaunchDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        PhoneModel.shared.start()
        return true
    }
}

private let ink = Color(red: 0.13, green: 0.40, blue: 0.59)

private struct MorningHome: View {
    @ObservedObject var model: PhoneModel
    @Environment(\.scenePhase) private var phase
    @State private var tab = 0
    @State private var settings = false
    @State private var today = WakeDay.key(.now)

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { morning }
                .tabItem { Label("Check-in", systemImage: "sun.horizon") }.tag(0)
            NavigationStack {
                ComparePage(model: model)
                    .navigationTitle("Compare")
                    .toolbar { settingsButton }
            }
            .tabItem { Label("Compare", systemImage: "chart.dots.scatter") }.tag(1)
        }
        .tint(ink)
        .sheet(isPresented: $settings) { SettingsPage(model: model) }
        .onChange(of: model.showCheckIn) { _, _ in tab = 0 }
        .onChange(of: phase) { _, state in if state == .active { today = WakeDay.key(.now) } }
    }

    private var settingsButton: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button { settings = true } label: { Image(systemName: "gearshape").accessibilityLabel("Settings") }
        }
    }

    private var morning: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Label("MORNING CHECK", systemImage: "sun.horizon.fill")
                        .font(.caption.monospaced().weight(.semibold)).foregroundStyle(ink)
                    Spacer()
                    Text(today).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                if let row = model.disk.diary[today], let rating = row.rating {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Rating saved").font(.title.bold())
                        Text("\(rating.value.rawValue) / 5").font(.system(.largeTitle, design: .rounded, weight: .bold))
                        Text(rating.value.label).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
                        .background(ink.opacity(0.10), in: RoundedRectangle(cornerRadius: 22))
                    ScorePanel(model: model, day: today).id(today)
                } else {
                    Text("How rested do you feel?").font(.system(.largeTitle, design: .rounded, weight: .bold))
                    Text("Rate how you felt on waking, before opening Apple’s Sleep Score.").foregroundStyle(.secondary)
                    VStack(spacing: 8) {
                        ForEach(Restedness.allCases, id: \.rawValue) { value in
                            Button { _ = model.recordPhoneRating(value) } label: {
                                HStack(spacing: 14) {
                                    Text("\(value.rawValue)").font(.title3.monospacedDigit().bold()).foregroundStyle(ink)
                                        .frame(width: 38, height: 38).background(ink.opacity(0.12), in: Circle())
                                    Text(value.label).font(.body.weight(.medium)).foregroundStyle(.primary)
                                    Spacer()
                                }.padding(.vertical, 5).padding(.horizontal, 12)
                                    .background(.background, in: RoundedRectangle(cornerRadius: 14))
                            }
                            .buttonStyle(.plain).accessibilityIdentifier("phone-rating-\(value.rawValue)")
                        }
                    }
                }
                if let error = model.storageError { Text(error).foregroundStyle(.red).font(.footnote) }
                Text("First report of the day is kept. You can also rate from Morning Check on your Watch.")
                    .font(.footnote).foregroundStyle(.secondary)
            }.padding(20)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Check-in")
        .toolbar { settingsButton }
    }
}

private struct ScorePanel: View {
    @ObservedObject var model: PhoneModel
    let day: String
    @State private var typed = ""
    @State private var proposed: Score?
    @State private var selected: PhotosPickerItem?
    @State private var feedback = ""
    @State private var scanning = false
    @FocusState private var typing: Bool

    var body: some View {
        let row = model.disk.diary[day]
        if row?.rating != nil {
            VStack(alignment: .leading, spacing: 14) {
                Text("Apple Sleep Score").font(.title2.bold())
                if let score = row?.score {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(score.value) / 100").font(.title.monospacedDigit().bold())
                        Spacer()
                        Button("Remove score", role: .destructive) { model.clearScore(day: day) }.font(.footnote)
                    }
                    Text(score.source.label).font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text("Enter the exact value shown in Health for \(day), or pick a screenshot of its Sleep Score detail card.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if let candidate = proposed ?? row?.candidate {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Detected \(candidate.value) / 100").font(.headline.monospacedDigit())
                            Text("Check the number and date against Apple Health before saving.").font(.footnote)
                            HStack {
                                Button("Confirm \(candidate.value)") { confirm(candidate) }.buttonStyle(.borderedProminent)
                                Button("Discard") { proposed = nil; model.clearScore(day: day) }.buttonStyle(.bordered)
                            }
                        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(ink.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    }
                    HStack {
                        TextField("Score (0–100)", text: $typed).keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder).focused($typing).accessibilityIdentifier("apple-score-field")
                        Button("Save score") {
                            guard let number = ScoreText.manual(typed), let score = Score(number, source: .manual) else { return }
                            confirm(score)
                        }.buttonStyle(.borderedProminent).disabled(ScoreText.manual(typed) == nil)
                    }
                    PhotosPicker(selection: $selected, matching: .images) {
                        Label(scanning ? "Reading image…" : "Read screenshot", systemImage: "text.viewfinder")
                    }.buttonStyle(.bordered).disabled(scanning)
                    if !feedback.isEmpty { Text(feedback).font(.footnote).foregroundStyle(.secondary) }
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
                .background(.background, in: RoundedRectangle(cornerRadius: 22))
                .onChange(of: selected) { _, item in
                    guard let item else { return }
                    proposed = nil; feedback = ""; scanning = true
                    Task {
                        defer { scanning = false; selected = nil }
                        guard let data = try? await item.loadTransferable(type: Data.self),
                              let number = await ScoreOCR.read(data) else {
                            feedback = "No clear Sleep Score found. Use a cropped English-language card or type it manually."
                            return
                        }
                        proposed = Score(number, source: .screenshot)
                    }
                }
        }
    }

    private func confirm(_ score: Score) {
        if model.confirmScore(score, day: day) { typed = ""; proposed = nil; feedback = ""; typing = false }
    }
}

private struct ComparePage: View {
    @ObservedObject var model: PhoneModel

    private struct Dot: Identifiable {
        let apple: Int
        let rested: Int
        var id: String { "\(apple)-\(rested)" }
    }

    var body: some View {
        let rows = model.disk.diary.rows.filter { $0.rating != nil }
        let summary = Comparison(rows: model.disk.diary.rows)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Does your score match how you feel?").font(.title2.bold())
                    Text("\(summary.pairs.count) paired mornings · \(summary.noScore) ratings without a score")
                        .font(.subheadline.monospacedDigit()).accessibilityIdentifier("pair-count")
                    if let first = rows.last?.id, let last = rows.first?.id {
                        Text(first == last ? first : "\(first) to \(last)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    if summary.pairs.isEmpty {
                        Text("Log your rating, then add Apple’s score to see the comparison here.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        scatter(summary.pairs)
                        if let rho = summary.spearman {
                            Text("Rank correlation: \(rho.formatted(.number.precision(.fractionLength(2))))")
                                .font(.subheadline.monospacedDigit().weight(.semibold))
                            Text("Positive means higher Apple scores tended to go with higher ratings. This describes your paired mornings, not a cause or a diagnosis.")
                                .font(.footnote).foregroundStyle(.secondary)
                        } else {
                            Text("Rank correlation needs at least five pairs and variation in both measures.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        if summary.highScore > 0 {
                            Text("\(summary.highButNotRested) of \(summary.highScore) high-score mornings felt only slightly rested or worse.")
                                .font(.subheadline.weight(.medium))
                            Text("High score = 81–100. Low restedness = 1–2.").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.background, in: RoundedRectangle(cornerRadius: 22))
                if !rows.isEmpty {
                    Text("Morning history").font(.title3.bold())
                    ForEach(rows) { row in
                        NavigationLink {
                            ScrollView { ScorePanel(model: model, day: row.id).padding(20) }
                                .background(Color(uiColor: .systemGroupedBackground)).navigationTitle(row.id)
                        } label: {
                            HStack {
                                Text(row.id).monospacedDigit().foregroundStyle(.primary)
                                Spacer()
                                if let rating = row.rating { Text("\(rating.value.rawValue)/5") }
                                Text(row.score.map { "\($0.value)/100" } ?? "Add score").foregroundStyle(.secondary)
                                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
                            }.padding(14).background(.background, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
            }.padding(20)
        }.background(Color(uiColor: .systemGroupedBackground))
    }

    private func scatter(_ pairs: [Pair]) -> some View {
        let grouped = Dictionary(grouping: pairs) { "\($0.score.value)-\($0.rating.rawValue)" }
        let dots = grouped.values.compactMap { group -> Dot? in
            guard let p = group.first else { return nil }
            return Dot(apple: p.score.value, rested: p.rating.rawValue)
        }.sorted { $0.id < $1.id }
        return Chart(dots) { dot in
            PointMark(x: .value("Apple Sleep Score", dot.apple), y: .value("Restedness", dot.rested))
                .symbolSize(45 + Double(min(10, grouped[dot.id]?.count ?? 1)) * 12).foregroundStyle(ink)
                .accessibilityLabel("Sleep Score \(dot.apple), restedness \(dot.rested) of 5")
                .accessibilityValue("\(grouped[dot.id]?.count ?? 0) mornings")
        }
        .chartXScale(domain: -2...102).chartYScale(domain: 0.7...5.3)
        .chartXAxis { AxisMarks(values: [0, 25, 50, 75, 100]) }
        .chartYAxis { AxisMarks(values: [1, 2, 3, 4, 5]) }
        .chartXAxisLabel("Apple Sleep Score")
        .chartYAxisLabel("Restedness")
        .frame(height: 180)
    }
}

private struct SettingsPage: View {
    @ObservedObject var model: PhoneModel
    @Environment(\.dismiss) private var dismiss
    @State private var busy = false
    @State private var showErase = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Prompt source") {
                    ForEach(PromptMode.allCases) { mode in
                        Button {
                            busy = true
                            Task { await model.changePromptMode(to: mode); busy = false }
                        } label: {
                            HStack {
                                Text(mode.title).foregroundStyle(.primary)
                                Spacer()
                                if model.mode == mode { Image(systemName: "checkmark").accessibilityLabel("Selected") }
                            }
                        }.disabled(busy)
                    }
                    Text("Sleep data mode waits for a recent Watch recording and is not a real-time wake detector. Apple alert mode needs a separate iPhone Shortcut.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Test Watch notification routing") { Task { await model.sendTestReminder() } }
                    if !model.promptStatus.isEmpty { Text(model.promptStatus).font(.footnote) }
                }
                Section("Privacy") {
                    Text("No account, server or iCloud storage. Ratings go from your Watch to its paired iPhone. Sleep permission is read-only. Selected screenshots are read on device; the app doesn’t keep the image.")
                    Button("Erase iPhone log", role: .destructive) { showErase = true }
                }
            }.navigationTitle("Settings")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .confirmationDialog("Erase the iPhone log?", isPresented: $showErase, titleVisibility: .visible) {
                    Button("Erase iPhone log", role: .destructive) { model.eraseDiary() }
                } message: { Text("Deletes ratings and score entries here, not your Watch log or anything in Apple Health.") }
        }
    }
}

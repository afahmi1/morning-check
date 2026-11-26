import MorningCheckCore
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

private struct MorningHome: View {
    private enum Workspace: String, CaseIterable, Identifiable {
        case checkIn, compare
        var id: String { rawValue }
        var title: String { self == .checkIn ? "Check-in" : "Compare" }
    }

    @ObservedObject var model: PhoneModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var phase
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var page: Workspace = .checkIn
    @State private var historyPath: [String] = []
    @State private var settings = false
    @State private var now = Date.now

    private var day: String { WakeDay.key(now) }
    private var palette: DayBreakPalette { DayBreakPalette(scheme) }

    var body: some View {
        NavigationStack(path: $historyPath) {
            VStack(spacing: 0) {
                header
                DayBreakRule(palette: palette)
                // Keep the score draft and scroll position when switching workspaces.
                ZStack {
                    checkIn
                        .opacity(page == .checkIn ? 1 : 0)
                        .allowsHitTesting(page == .checkIn)
                        .accessibilityHidden(page != .checkIn)
                    ComparePage(model: model)
                        .opacity(page == .compare ? 1 : 0)
                        .allowsHitTesting(page == .compare)
                        .accessibilityHidden(page != .compare)
                }
            }
            .background(palette.canvas.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: String.self) { day in
                ScrollView {
                    ScorePanel(model: model, day: day).padding(.vertical, 20).dayBreakPhoneGutter()
                }
                .scrollDismissesKeyboard(.interactively)
                .background(palette.canvas.ignoresSafeArea())
                .navigationTitle(day).navigationBarTitleDisplayMode(.inline)
                .toolbar(.visible, for: .navigationBar)
                .toolbarBackground(palette.canvas, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
            }
        }
        .tint(palette.accent)
        .sheet(isPresented: $settings) { SettingsPage(model: model) }
        .onChange(of: model.showCheckIn) { _, _ in
            historyPath.removeAll()
            settings = false
            now = .now
            page = .checkIn
        }
        .onChange(of: phase) { _, state in if state == .active { now = .now } }
    }

    private var header: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 3)) : AnyLayout(HStackLayout(spacing: 3))
        return VStack(spacing: 8) {
            HStack(spacing: 10) {
                DayBreakBrand(iconSize: 32).font(.dayBreakSection).foregroundStyle(palette.ink)
                Spacer(minLength: 0)
                Button { settings = true } label: {
                    Image(systemName: "gearshape").font(.system(size: 19, weight: .medium))
                        .foregroundStyle(palette.ink).frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityLabel("Settings")
            }
            layout {
                ForEach(Workspace.allCases) { workspace in
                    let selected = workspace == page
                    Button { page = workspace } label: {
                        Text(workspace.title).font(.subheadline.weight(.semibold))
                            .foregroundStyle(selected ? palette.accent : palette.muted)
                            .padding(.horizontal, 10).padding(.vertical, 8)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(selected ? palette.selection : .clear, in: RoundedRectangle(cornerRadius: 9))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityIdentifier("workspace-\(workspace.rawValue)")
                }
            }
            .padding(3).dayBreakPanel(palette)
        }
        .padding(.bottom, 12).dayBreakPhoneGutter()
        .background(palette.canvas)
    }

    private var checkIn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 7) {
                        Circle().fill(palette.accent).frame(width: 7, height: 7).accessibilityHidden(true)
                        Text(now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                            .font(.subheadline.weight(.medium)).foregroundStyle(palette.muted)
                    }
                    if let rating = model.disk.diary[day]?.rating {
                        Text("Rating saved").font(.dayBreakDisplay).accessibilityAddTraits(.isHeader)
                        Text("\(rating.value.rawValue) / 5").font(.dayBreakSection.monospacedDigit())
                            .foregroundStyle(palette.accent).accessibilityLabel("\(rating.value.rawValue) of 5")
                        Text(rating.value.label).foregroundStyle(palette.muted)
                    } else {
                        Text("How rested do you feel?").font(.dayBreakDisplay).accessibilityAddTraits(.isHeader)
                        Text("Rate how you felt on waking, before opening Apple’s Sleep Score.")
                            .foregroundStyle(palette.muted)
                    }
                }
                if model.disk.diary[day]?.rating != nil {
                    ScorePanel(model: model, day: day, active: page == .checkIn).id(day)
                } else {
                    ratings
                }
                if let error = model.storageError {
                    Label(error, systemImage: "exclamationmark.circle")
                        .foregroundStyle(palette.destructive).font(.footnote)
                }
                Label("The first check-in is kept. You can also rate from your Watch.", systemImage: "applewatch")
                    .font(.footnote).foregroundStyle(palette.muted)
            }
            .foregroundStyle(palette.ink)
            .padding(.vertical, 20).dayBreakPhoneGutter()
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var ratings: some View {
        VStack(spacing: 0) {
            ForEach(Restedness.allCases, id: \.rawValue) { value in
                if value != .notAtAll { DayBreakRule(palette: palette).padding(.horizontal, 14) }
                Button { _ = model.recordPhoneRating(value) } label: {
                    HStack(spacing: 12) {
                        Text("\(value.rawValue)").font(.headline.monospacedDigit())
                            .foregroundStyle(palette.accent)
                            .frame(minWidth: 26, alignment: .leading)
                        Text(value.label).font(.body.weight(.medium)).foregroundStyle(palette.ink)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 9).padding(.horizontal, 14)
                    .frame(minHeight: 52).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityLabel("\(value.rawValue) of 5, \(value.label)")
                .accessibilityIdentifier("phone-rating-\(value.rawValue)")
            }
        }
        .dayBreakPanel(palette)
    }
}

extension View {
    func dayBreakPhoneGutter() -> some View {
        frame(maxWidth: 540, alignment: .leading).padding(.horizontal, 20).frame(maxWidth: .infinity)
    }
}

import Charts
import MorningCheckCore
import SwiftUI

struct ComparePage: View {
    @ObservedObject var model: PhoneModel
    @Environment(\.dayBreakPalette) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize

    private struct Dot: Identifiable {
        let apple: Int
        let rested: Int
        let count: Int
        var id: String { "\(apple)-\(rested)" }
    }

    var body: some View {
        let all = model.disk.diary.rows
        let rows = all.filter { $0.rating != nil }
        let summary = Comparison(rows: all)
        let stages = WakeStageComparison(rows: rows)
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Compare your mornings").font(palette.displayFont).accessibilityAddTraits(.isHeader)
                    Text("Compare how rested you felt with Apple’s Sleep Score and your last recorded sleep stage.")
                        .foregroundStyle(palette.muted)
                }
                coverage(summary, rows: rows)
                if summary.pairs.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("No Sleep Scores paired yet", systemImage: "chart.dots.scatter").font(.headline)
                        Text("Record your restedness on waking, then add Apple’s Sleep Score for the same date.")
                            .font(.subheadline).foregroundStyle(palette.muted)
                    }
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading).dayBreakPanel(palette)
                } else {
                    results(summary)
                }
                if !rows.isEmpty {
                    stageResults(stages)
                    history(rows)
                }
            }
            .foregroundStyle(palette.ink)
            .padding(.vertical, 20).dayBreakPhoneGutter()
        }
        .accessibilityIdentifier("compare-page")
    }

    private func coverage(_ summary: Comparison, rows: [Morning]) -> some View {
        let count = summary.pairs.count
        let paired = count == 1 ? "morning with a score" : "mornings with a score"
        let missing = summary.noScore == 1 ? "rating without a score" : "ratings without a score"
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
        return VStack(alignment: .leading, spacing: 8) {
            DayBreakRule(palette: palette)
            layout {
                metric(count, paired)
                    .accessibilityElement(children: .ignore).accessibilityLabel("\(count) \(paired)")
                    .accessibilityIdentifier("pair-count")
                metric(summary.noScore, missing)
                    .accessibilityElement(children: .ignore).accessibilityLabel("\(summary.noScore) \(missing)")
            }
            .padding(.vertical, 5)
            if let first = rows.last?.id, let last = rows.first?.id {
                Text(first == last ? first : "\(first) to \(last)")
                    .font(.footnote.monospacedDigit()).foregroundStyle(palette.muted)
            }
            DayBreakRule(palette: palette)
        }
    }

    private func metric(_ number: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(number, format: .number).font(palette.numberFont)
            Text(label).font(.subheadline).foregroundStyle(palette.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func results(_ summary: Comparison) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Restedness and Sleep Score").font(palette.sectionFont).accessibilityAddTraits(.isHeader)
                scatter(summary.pairs)
                if let rho = summary.spearman {
                    Text("Rank correlation: \(rho.formatted(.number.precision(.fractionLength(2))))")
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                    Text("Positive means higher Apple scores tended to go with higher ratings. This describes your paired mornings, not a cause or a diagnosis.")
                        .font(.footnote).foregroundStyle(palette.muted)
                } else {
                    Text("Rank correlation needs at least five pairs and variation in both measures.")
                        .font(.footnote).foregroundStyle(palette.muted)
                }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading).dayBreakPanel(palette)
            if summary.highScore > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    Label {
                        Text("High score, low rest").foregroundStyle(palette.ink)
                    } icon: {
                        Image(systemName: "circle.lefthalf.filled").foregroundStyle(palette.caution)
                    }
                    .font(.subheadline.weight(.semibold))
                    Text("\(summary.highButNotRested) of \(summary.highScore) high-score mornings felt only slightly rested or worse.")
                        .font(.subheadline.weight(.medium))
                    Text("High score: 81–100. Low restedness: 1–2.").font(.footnote).foregroundStyle(palette.muted)
                }
                .padding(.vertical, 6).padding(.leading, 12).frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .leading) { Rectangle().fill(palette.caution).frame(width: 2).accessibilityHidden(true) }
                .accessibilityIdentifier("mismatch-summary")
            }
        }
    }

    private func scatter(_ pairs: [Pair]) -> some View {
        let groups = Dictionary(grouping: pairs) { "\($0.score.value)-\($0.rating.rawValue)" }
        let dots = groups.values.compactMap { group in
            group.first.map { Dot(apple: $0.score.value, rested: $0.rating.rawValue, count: group.count) }
        }.sorted { ($0.apple, $0.rested) < ($1.apple, $1.rested) }
        return Chart(dots) { dot in
            PointMark(x: .value("Apple Sleep Score", dot.apple), y: .value("Restedness", dot.rested))
                .symbolSize(45 + Double(min(10, dot.count) * 12)).foregroundStyle(palette.accent)
                .accessibilityLabel("Sleep Score \(dot.apple), restedness \(dot.rested) of 5")
                .accessibilityValue(dot.count == 1 ? "1 morning" : "\(dot.count) mornings")
        }
        .chartXScale(domain: -2...102, range: .plotDimension(startPadding: 8, endPadding: 16)).chartYScale(domain: 0.7...5.3)
        .chartXAxis {
            AxisMarks(values: typeSize.isAccessibilitySize ? [0, 50, 100] : [0, 25, 50, 75, 100]) { value in
                AxisGridLine().foregroundStyle(palette.rule)
                AxisValueLabel(anchor: .top, collisionResolution: .disabled) {
                    if let v = value.as(Int.self) {
                        Text("\(v)").fixedSize().font(palette.axisFont).foregroundStyle(palette.muted)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: palette.theme == .paperAsh ? .automatic : .leading, values: [1, 2, 3, 4, 5]) {
                AxisGridLine().foregroundStyle(palette.rule)
                AxisValueLabel().font(palette.axisFont).foregroundStyle(palette.muted)
            }
        }
        .chartXAxisLabel { Text("Apple Sleep Score").foregroundStyle(palette.muted) }
        .chartYAxisLabel { Text("Restedness").foregroundStyle(palette.muted) }
        .frame(height: typeSize.isAccessibilitySize ? 270 : 188)
    }

    private func stageResults(_ summary: WakeStageComparison) -> some View {
        let format = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...1))
        return VStack(alignment: .leading, spacing: 10) {
            Text("Restedness by last sleep stage").font(palette.sectionFont).accessibilityAddTraits(.isHeader)
            Text("\(summary.matched) with a stage · \(summary.missing) missing")
                .font(.subheadline.monospacedDigit()).foregroundStyle(palette.muted)
                .accessibilityIdentifier("wake-stage-coverage")
            if summary.groups.isEmpty {
                Text(model.wakeStagesEnabled
                     ? "No matching Apple Watch stages yet. Check Sleep access in Health and try again after your Watch syncs."
                     : "Enable sleep stage logging to pair Apple Watch sleep stages with your check-ins.")
                    .font(.footnote).foregroundStyle(palette.muted)
            } else {
                ForEach(summary.groups) { group in
                    DayBreakRule(palette: palette)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.stage.label).font(palette.choiceFont).foregroundStyle(palette.accent)
                        Text("Median restedness: \(group.medianRestedness.formatted(format)) / 5 (\(group.count))")
                            .font(.subheadline.monospacedDigit())
                        if let score = group.medianScore {
                            Text("Median Sleep Score: \(score.formatted(format)) / 100 (\(group.scoreCount))")
                                .font(.footnote.monospacedDigit()).foregroundStyle(palette.muted)
                        } else {
                            Text("No confirmed Sleep Scores").font(.footnote).foregroundStyle(palette.muted)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("wake-stage-group-\(group.stage.rawValue)")
                }
                Text("Counts are mornings with that measure. Small groups can vary a lot; this doesn’t tell you what caused a rating.")
                    .font(.footnote).foregroundStyle(palette.muted)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).dayBreakPanel(palette)
    }

    private func history(_ rows: [Morning]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Morning history").font(palette.sectionFont).accessibilityAddTraits(.isHeader)
            LazyVStack(spacing: 0) {
                DayBreakRule(palette: palette)
                ForEach(rows) { row in
                    NavigationLink(value: row.id) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(row.id).font(.body.monospacedDigit().weight(.semibold)).foregroundStyle(palette.ink)
                                if let rating = row.rating {
                                    Text("Restedness \(rating.value.rawValue) / 5").font(.footnote).foregroundStyle(palette.muted)
                                    if let wake = row.wakeStage, wake.matches(rating) {
                                        Text("Last stage: \(wake.stage.label)").font(.footnote).foregroundStyle(palette.muted)
                                    }
                                }
                            }
                            Spacer(minLength: 4)
                            Text(row.score.map { "\($0.value) / 100" } ?? "Add score")
                                .font(.subheadline.monospacedDigit()).foregroundStyle(row.score == nil ? palette.accent : palette.ink)
                                .multilineTextAlignment(.trailing)
                            Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                                .foregroundStyle(palette.muted).accessibilityHidden(true)
                        }
                        .padding(.vertical, 10).frame(minHeight: 52).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).accessibilityIdentifier("morning-history-\(row.id)")
                    DayBreakRule(palette: palette)
                }
            }
        }
    }
}

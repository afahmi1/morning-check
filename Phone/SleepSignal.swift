import Foundation
import HealthKit
import MorningCheckCore
import UIKit

@MainActor
final class SleepSignal {
    enum Reading {
        case session(Date)
        case notReady(PromptOutcome)
    }

    enum StageReading {
        case result(WakeStage?)
        case unavailable(PromptOutcome)
    }

    private let health = HKHealthStore()
    private let type = HKCategoryType(.sleepAnalysis)
    private var observer: HKObserverQuery?

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func authorize() async throws {
        try await health.requestAuthorization(toShare: [], read: [type])
    }

    func start(_ delivery: @escaping @MainActor (PromptOutcome?) async -> Void) {
        guard isAvailable, observer == nil else { return }
        let query = HKObserverQuery(sampleType: type, predicate: nil) { _, complete, error in
            let failure = error.map(Self.readFailure)
            Task { @MainActor in
                defer { complete() }
                await delivery(failure)
            }
        }
        observer = query
        health.execute(query)
    }

    func enableDelivery() async throws {
        try await health.enableBackgroundDelivery(for: type, frequency: .immediate)
    }

    func disableDelivery() async throws {
        guard isAvailable else { return }
        try await health.disableBackgroundDelivery(for: type)
    }

    func stop() {
        if let observer { health.stop(observer); self.observer = nil }
    }

    func readRecentNight(now: Date) async -> Reading {
        if let failure = readAvailability() { return .notReady(failure) }
        do {
            let intervals = try await asleepIntervals(through: now, completedOnly: true)
            guard let end = SleepWindow.qualifyingEnd(in: intervals, now: now) else { return .notReady(.sleepNotReady) }
            return .session(end)
        } catch { return .notReady(Self.readFailure(error)) }
    }

    func readWakeStage(for rating: Rating) async -> StageReading {
        if let failure = readAvailability() { return .unavailable(failure) }
        guard rating.isConsistent, rating.reportedAt <= .now else { return .result(nil) }
        do {
            // Include intervals that overlap the rating so an unfinished sleep segment is not mistaken for a wake.
            let intervals = try await asleepIntervals(through: rating.reportedAt, completedOnly: false)
            return .result(SleepWindow.wakeStage(in: intervals, for: rating))
        } catch { return .unavailable(Self.readFailure(error)) }
    }

    private func readAvailability() -> PromptOutcome? {
        guard isAvailable else { return .healthUnavailable }
        guard UIApplication.shared.isProtectedDataAvailable else { return .healthLocked }
        return nil
    }

    private func asleepIntervals(through end: Date, completedOnly: Bool) async throws -> [SleepInterval] {
        let options: HKQueryOptions = completedOnly ? [.strictStartDate, .strictEndDate] : [.strictStartDate]
        let window = HKQuery.predicateForSamples(withStart: end.addingTimeInterval(-SleepWindow.lookback), end: end, options: options)
        let request = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: type, predicate: window)],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)]
        )
        let samples = try await request.result(for: health)
        return samples.compactMap { sample in
            guard sample.metadata?[HKMetadataKeyWasUserEntered] as? Bool != true else { return nil }
            let source = sample.sourceRevision
            let apple = source.source.bundleIdentifier.hasPrefix("com.apple.")
            let watch = source.productType?.hasPrefix("Watch") == true ||
                sample.device?.model?.localizedCaseInsensitiveContains("watch") == true
            guard apple && watch else { return nil }
            let stage: SleepStage?
            switch HKCategoryValueSleepAnalysis(rawValue: sample.value) {
            case .asleepCore: stage = .core
            case .asleepDeep: stage = .deep
            case .asleepREM: stage = .rem
            case .asleepUnspecified: stage = nil
            default: return nil // Awake, In Bed, and any unknown values are not asleep intervals.
            }
            return SleepInterval(start: sample.startDate, end: sample.endDate, stage: stage)
        }
    }

    nonisolated private static func readFailure(_ error: Error) -> PromptOutcome {
        (error as? HKError)?.code == .errorDatabaseInaccessible ? .healthLocked : .healthReadFailed
    }
}
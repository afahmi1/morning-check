import Foundation
import HealthKit
import MorningCheckCore
import UIKit

@MainActor
final class SleepSignal {
    private let health = HKHealthStore()
    private let type = HKCategoryType(.sleepAnalysis)
    private var observer: HKObserverQuery?

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func authorize() async throws {
        try await health.requestAuthorization(toShare: [], read: [type])
    }

    func start(_ delivery: @escaping @MainActor () async -> Void) {
        guard isAvailable, observer == nil else { return }
        let query = HKObserverQuery(sampleType: type, predicate: nil) { _, complete, error in
            guard error == nil else { complete(); return }
            Task { @MainActor in
                defer { complete() }
                await delivery()
            }
        }
        observer = query
        health.execute(query)
    }

    func enableDelivery() async throws {
        try await health.enableBackgroundDelivery(for: type, frequency: .immediate)
    }

    func stop() {
        if let observer { health.stop(observer); self.observer = nil }
        health.disableBackgroundDelivery(for: type) { _, _ in }
    }

    func recentNightEnd(now: Date) async throws -> Date? {
        guard isAvailable, UIApplication.shared.isProtectedDataAvailable else { return nil }
        let window = HKQuery.predicateForSamples(withStart: now.addingTimeInterval(-36 * 3600),
                                                  end: now, options: [.strictEndDate])
        let request = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: type, predicate: window)],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)], limit: 1200
        )
        let samples = try await request.result(for: health)
        let asleep: Set<Int> = Set(HKCategoryValueSleepAnalysis.allAsleepValues.map(\.rawValue))
        let intervals = samples.compactMap { sample -> SleepInterval? in
            guard asleep.contains(sample.value), sample.metadata?[HKMetadataKeyWasUserEntered] as? Bool != true else { return nil }
            let source = sample.sourceRevision
            let apple = source.source.bundleIdentifier.hasPrefix("com.apple.")
            let looksLikeWatch = source.productType?.hasPrefix("Watch") == true ||
                sample.device?.model?.localizedCaseInsensitiveContains("watch") == true
            guard apple && looksLikeWatch else { return nil }
            return SleepInterval(start: sample.startDate, end: sample.endDate)
        }
        return SleepWindow.qualifyingEnd(in: intervals, now: now)
    }
}

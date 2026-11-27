import Foundation

public enum PromptMode: String, CaseIterable, Identifiable, Sendable {
    case off, sleepData, appleAlert, either
    public var id: Self { self }

    public func accepts(_ source: PromptSource) -> Bool {
        switch (self, source) {
        case (.either, _), (.sleepData, .watchSleep), (.appleAlert, .appleAlert): true
        default: false
        }
    }
}

public enum PromptSource: String, CaseIterable, Identifiable, Sendable {
    case watchSleep, appleAlert
    public var id: Self { self }
}

public enum PromptOutcome: String, Codable, Equatable, Sendable {
    case off, stale, alreadyRated, alreadyQueued, logUnavailable
    case logErased, submissionUncertain
    case healthLocked, healthUnavailable, sleepNotReady, healthReadFailed
    case notificationsOff, queued, queueFailed
}

public struct PromptCheck: Codable, Equatable, Sendable {
    public let outcome: PromptOutcome
    public let checkedAt: Date
}

/// At most one technical status per source. No samples, scores or alert text.
public struct PromptChecks: Codable, Sendable {
    private var watchSleep: PromptCheck?
    private var appleAlert: PromptCheck?

    public init() {}

    public subscript(_ source: PromptSource) -> PromptCheck? {
        source == .watchSleep ? watchSleep : appleAlert
    }

    public mutating func record(_ outcome: PromptOutcome, for source: PromptSource, at time: Date) {
        let check = PromptCheck(outcome: outcome, checkedAt: time)
        switch source {
        case .watchSleep: watchSleep = check
        case .appleAlert: appleAlert = check
        }
    }

    fileprivate var isEmpty: Bool { watchSleep == nil && appleAlert == nil }

    fileprivate func overlay(_ pending: Self) -> Self {
        var next = self
        if let watchSleep = pending.watchSleep { next.watchSleep = watchSleep }
        if let appleAlert = pending.appleAlert { next.appleAlert = appleAlert }
        return next
    }
}

/// Buffer changes when the protected diagnostics file is unavailable. A failed load is not a new file.
public struct PromptCheckJournal {
    private var lastReadable = PromptChecks()
    private var pending = PromptChecks()
    private var eraseRequested = false

    public init() {}
    public var checks: PromptChecks { lastReadable.overlay(pending) }

    public mutating func record(_ outcome: PromptOutcome, for source: PromptSource, at time: Date) {
        pending.record(outcome, for: source, at: time)
    }

    public mutating func clear() {
        lastReadable = PromptChecks()
        pending = PromptChecks()
        eraseRequested = true
    }

    public mutating func sync(load: () throws -> PromptChecks?, save: (PromptChecks) throws -> Void) throws {
        lastReadable = eraseRequested ? PromptChecks() : try load() ?? PromptChecks()
        guard eraseRequested || !pending.isEmpty else { return }
        let next = checks
        try save(next)
        lastReadable = next
        pending = PromptChecks()
        eraseRequested = false
    }
}

public enum PromptPolicy {
    public static func eligibleDay(for source: PromptSource, signalAt: Date, now: Date, zone: TimeZone = .current) -> String? {
        let minAge: TimeInterval = source == .appleAlert ? -300 : 0
        guard (minAge...7200).contains(now.timeIntervalSince(signalAt)) else { return nil }
        let day = WakeDay.key(signalAt, in: zone)
        return day == WakeDay.key(now, in: zone) ? day : nil
    }

    /// Shared by both routes before and after awaiting OS state.
    public static func blocked(_ source: PromptSource, mode: PromptMode, day: String, currentDay: String,
                               alreadyRated: Bool, lastQueuedDay: String?, storageAvailable: Bool,
                               unresolvedDay: String? = nil, erasedToday: Bool = false) -> PromptOutcome? {
        guard mode.accepts(source) else { return .off }
        guard day == currentDay else { return .stale }
        guard storageAvailable else { return .logUnavailable }
        guard !alreadyRated else { return .alreadyRated }
        guard !erasedToday else { return .logErased }
        guard lastQueuedDay != day else { return .alreadyQueued }
        guard unresolvedDay != day else { return .submissionUncertain }
        return nil
    }
}

/// Persist a reservation before asking iOS. If the process dies between the two writes,
/// a restarted app can avoid a duplicate without claiming that iOS accepted the request.
@MainActor
public enum PromptTransaction {
    public static func submit(revalidate: @MainActor () -> PromptOutcome?, reserve: @MainActor () -> Bool,
                              send: @MainActor () async throws -> Void, finalize: @MainActor (Bool) -> Void) async -> PromptOutcome {
        if let reason = revalidate() { return reason }
        guard reserve() else { return .logUnavailable }
        if let reason = revalidate() { finalize(false); return reason }
        do { try await send() }
        catch { finalize(false); return .queueFailed }
        finalize(true)
        return .queued
    }
}

@MainActor
public final class PromptSubmissionQueue {
    private var active: [String: Task<PromptOutcome, Never>] = [:]

    public init() {}

    public func attempt(on day: String, revalidate: @escaping @MainActor () -> PromptOutcome?,
                        _ operation: @escaping @MainActor () async -> PromptOutcome) async -> PromptOutcome {
        while true {
            if let reason = revalidate() { return reason }
            guard let pending = active[day] else { break }
            let result = await pending.value
            // The submission and the waiter may span midnight or the signal's freshness window.
            if let reason = revalidate() { return reason }
            if result == .queued || result == .alreadyQueued { return .alreadyQueued }
        }
        // A second source waits for the first submission, then gets its own chance
        // if the first source stopped or failed before iOS accepted a request.
        let task = Task { @MainActor in
            defer { self.active.removeValue(forKey: day) }
            if let reason = revalidate() { return reason }
            return await operation()
        }
        active[day] = task
        return await task.value
    }
}

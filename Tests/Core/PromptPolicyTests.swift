import Foundation
import XCTest
@testable import MorningCheckCore

final class PromptPolicyTests: XCTestCase {
    private let zone = TimeZone(secondsFromGMT: 0)!
    private var now: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.startOfDay(for: .now).addingTimeInterval(12 * 3600)
    }

    func testStoredModesKeepTheirExistingScopes() throws {
        XCTAssertFalse(PromptMode.off.accepts(.appleAlert))
        XCTAssertFalse(PromptMode.off.accepts(.watchSleep))
        XCTAssertTrue(try XCTUnwrap(PromptMode(rawValue: "sleepData")).accepts(.watchSleep))
        XCTAssertFalse(PromptMode.sleepData.accepts(.appleAlert))
        XCTAssertTrue(try XCTUnwrap(PromptMode(rawValue: "appleAlert")).accepts(.appleAlert))
        XCTAssertFalse(PromptMode.appleAlert.accepts(.watchSleep))
        XCTAssertTrue(PromptMode.either.accepts(.appleAlert))
        XCTAssertTrue(PromptMode.either.accepts(.watchSleep))
    }

    func testLockedSleepReadDoesNotConsumeTheAlertFallback() throws {
        let time = now
        let day = try XCTUnwrap(PromptPolicy.eligibleDay(for: .appleAlert, signalAt: time, now: time, zone: zone))
        var checks = PromptChecks()
        checks.record(.healthLocked, for: .watchSleep, at: time)
        XCTAssertNil(PromptPolicy.blocked(.appleAlert, mode: .either, day: day, currentDay: day,
                                          alreadyRated: false, lastQueuedDay: nil, storageAvailable: true))
        checks.record(.queued, for: .appleAlert, at: time)
        XCTAssertEqual(checks[.watchSleep]?.outcome, .healthLocked)
        XCTAssertEqual(checks[.appleAlert]?.outcome, .queued)
        XCTAssertEqual(PromptPolicy.blocked(.watchSleep, mode: .either, day: day, currentDay: day,
                                            alreadyRated: false, lastQueuedDay: day, storageAvailable: true), .alreadyQueued)
    }

    func testSleepFirstDisallowsTheSecondAlertPromptButAllowsDifferentDay() {
        let day = WakeDay.key(now, in: zone)
        let previous = WakeDay.key(now.addingTimeInterval(-86_400), in: zone)
        XCTAssertEqual(PromptPolicy.blocked(.appleAlert, mode: .either, day: day, currentDay: day,
                                            alreadyRated: false, lastQueuedDay: day, storageAvailable: true), .alreadyQueued)
        XCTAssertNil(PromptPolicy.blocked(.appleAlert, mode: .either, day: day, currentDay: day,
                                          alreadyRated: false, lastQueuedDay: previous, storageAvailable: true))
        XCTAssertEqual(PromptPolicy.blocked(.watchSleep, mode: .either, day: previous, currentDay: day,
                                            alreadyRated: false, lastQueuedDay: nil, storageAvailable: true), .stale)
    }

    func testPromptStopsIfRatedOrSourceDisabledDuringCheck() {
        let day = WakeDay.key(now, in: zone)
        XCTAssertEqual(PromptPolicy.blocked(.appleAlert, mode: .either, day: day, currentDay: day,
                                            alreadyRated: true, lastQueuedDay: nil, storageAvailable: true), .alreadyRated)
        XCTAssertEqual(PromptPolicy.blocked(.watchSleep, mode: .appleAlert, day: day, currentDay: day,
                                            alreadyRated: false, lastQueuedDay: nil, storageAvailable: true), .off)
        XCTAssertEqual(PromptPolicy.blocked(.watchSleep, mode: .sleepData, day: day, currentDay: day,
                                            alreadyRated: false, lastQueuedDay: nil, storageAvailable: false), .logUnavailable)
    }

    func testSignalsMustBeRecentAndEndOnTheSameDay() {
        let time = now
        let day = WakeDay.key(time, in: zone)
        for source in PromptSource.allCases {
            XCTAssertEqual(PromptPolicy.eligibleDay(for: source, signalAt: time, now: time, zone: zone), day)
            XCTAssertEqual(PromptPolicy.eligibleDay(for: source, signalAt: time.addingTimeInterval(-7200), now: time, zone: zone), day)
            XCTAssertNil(PromptPolicy.eligibleDay(for: source, signalAt: time.addingTimeInterval(-7201), now: time, zone: zone))
        }
        XCTAssertNil(PromptPolicy.eligibleDay(for: .appleAlert, signalAt: time.addingTimeInterval(301), now: time, zone: zone))
        XCTAssertNil(PromptPolicy.eligibleDay(for: .watchSleep, signalAt: time.addingTimeInterval(1), now: time, zone: zone))
        let midnight = time.addingTimeInterval(-12 * 3600)
        XCTAssertNil(PromptPolicy.eligibleDay(for: .appleAlert, signalAt: midnight.addingTimeInterval(-120), now: midnight, zone: zone))
    }

    func testPromptChecksRoundTripWithoutAHistory() throws {
        let time = now
        var checks = PromptChecks()
        checks.record(.healthLocked, for: .watchSleep, at: time)
        checks.record(.queueFailed, for: .appleAlert, at: time)
        checks.record(.sleepNotReady, for: .watchSleep, at: time.addingTimeInterval(1))
        let data = try JSONEncoder().encode(checks)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: [String: Any]])
        for source in object.values { XCTAssertEqual(Set(source.keys), ["outcome", "checkedAt"]) }
        let restored = try JSONDecoder().decode(PromptChecks.self, from: data)
        XCTAssertEqual(restored[.watchSleep]?.outcome, .sleepNotReady)
        XCTAssertEqual(restored[.appleAlert]?.outcome, .queueFailed)
    }

    @MainActor
    func testOverlappingRoutesDoNotSubmitTwiceAfterAcceptance() async {
        let result = await tryOverlappingRoutes(firstOutcome: .queued)
        XCTAssertEqual(result.first, .queued)
        XCTAssertEqual(result.second, .alreadyQueued)
        XCTAssertEqual(result.secondAttempts, 0)
    }

    @MainActor
    func testOverlappingAlertRetriesIfWatchRouteStopsBeforeSubmission() async {
        for rejected in [PromptOutcome.off, .queueFailed] {
            let result = await tryOverlappingRoutes(firstOutcome: rejected)
            XCTAssertEqual(result.first, rejected)
            XCTAssertEqual(result.second, .queued)
            XCTAssertEqual(result.secondAttempts, 1)
        }
    }

    @MainActor
    func testWaitingAlertThatAgesOutIsNotSubmitted() async {
        let result = await tryOverlappingRoutes(firstOutcome: .queueFailed, expireAlert: true)
        XCTAssertEqual(result.first, .queueFailed)
        XCTAssertEqual(result.second, .stale)
        XCTAssertEqual(result.secondAttempts, 0)
    }

    @MainActor
    func testWaitingWatchSignalAgingOutAfterAcceptanceIsNotReportedAsDuplicate() async {
        let result = await tryOverlappingRoutes(firstOutcome: .queued, expireAlert: true, waitingSource: .watchSleep)
        XCTAssertEqual(result.first, .queued)
        XCTAssertEqual(result.second, .stale)
        XCTAssertEqual(result.secondAttempts, 0)
    }

    @MainActor
    func testWaitingWatchSignalAgingOutAfterFailureCannotSubmit() async {
        let result = await tryOverlappingRoutes(firstOutcome: .queueFailed, expireAlert: true, waitingSource: .watchSleep)
        XCTAssertEqual(result.first, .queueFailed)
        XCTAssertEqual(result.second, .stale)
        XCTAssertEqual(result.secondAttempts, 0)
    }

    @MainActor
    func testPendingRequestCrossingMidnightDoesNotUseYesterdaysAcceptance() async {
        let midnight = now.addingTimeInterval(-12 * 3600)
        let result = await tryOverlappingRoutes(firstOutcome: .queued, time: midnight.addingTimeInterval(-1), resumeAt: midnight)
        XCTAssertEqual(result.first, .queued)
        XCTAssertEqual(result.second, .stale)
        XCTAssertEqual(result.secondAttempts, 0)
    }

    func testFailedDiagnosticReadNeverOverwritesUnseenOutcome() throws {
        let time = now
        var stored = PromptChecks()
        stored.record(.queued, for: .appleAlert, at: time)
        var journal = PromptCheckJournal()
        journal.record(.healthLocked, for: .watchSleep, at: time)
        var writeCount = 0
        XCTAssertThrowsError(try journal.sync(load: { throw CocoaError(.fileReadNoPermission) }, save: { _ in writeCount += 1 }))
        XCTAssertEqual(writeCount, 0)
        XCTAssertEqual(journal.checks[.watchSleep]?.outcome, .healthLocked)
        XCTAssertEqual(stored[.appleAlert]?.outcome, .queued)
        try journal.sync(load: { stored }, save: { stored = $0; writeCount += 1 })
        XCTAssertEqual(writeCount, 1)
        XCTAssertEqual(stored[.watchSleep]?.outcome, .healthLocked)
        XCTAssertEqual(stored[.appleAlert]?.outcome, .queued)
    }

    func testFailedDiagnosticWriteKeepsPendingUpdatesAndCanBeErased() throws {
        let time = now
        var stored: PromptChecks?
        var journal = PromptCheckJournal()
        journal.record(.healthLocked, for: .watchSleep, at: time)
        XCTAssertThrowsError(try journal.sync(load: { stored }, save: { _ in throw CocoaError(.fileWriteNoPermission) }))
        journal.record(.queued, for: .appleAlert, at: time)
        try journal.sync(load: { stored }, save: { stored = $0 })
        XCTAssertEqual(stored?[.watchSleep]?.outcome, .healthLocked)
        XCTAssertEqual(stored?[.appleAlert]?.outcome, .queued)
        journal.clear()
        XCTAssertThrowsError(try journal.sync(load: { XCTFail("Explicit erase should not need to read old checks"); return stored },
                                              save: { _ in throw CocoaError(.fileWriteNoPermission) }))
        XCTAssertNil(journal.checks[.watchSleep])
        try journal.sync(load: { stored }, save: { stored = $0 })
        XCTAssertNil(stored?[.watchSleep])
        XCTAssertNil(stored?[.appleAlert])
    }

    @MainActor
    func testAcceptanceWithFailedFinalWriteDoesNotPermitResubmissionAfterRestart() async {
        let day = WakeDay.key(now, in: zone)
        var persistedPending: String?
        var submitted = 0
        let outcome = await PromptTransaction.submit(revalidate: { nil }, reserve: {
            persistedPending = day
            return true
        }, send: {
            XCTAssertEqual(persistedPending, day)
            submitted += 1
        }, finalize: { accepted in
            XCTAssertTrue(accepted)
            // Simulate the atomic write failing: a restarted process sees only the reservation.
        })
        XCTAssertEqual(outcome, .queued)
        XCTAssertEqual(submitted, 1)
        for source in PromptSource.allCases {
            XCTAssertEqual(PromptPolicy.blocked(source, mode: .either, day: day, currentDay: day,
                                                alreadyRated: false, lastQueuedDay: nil, storageAvailable: true,
                                                unresolvedDay: persistedPending), .submissionUncertain)
            let nextDay = WakeDay.key(now.addingTimeInterval(86_400), in: zone)
            XCTAssertNil(PromptPolicy.blocked(source, mode: .either, day: nextDay, currentDay: nextDay,
                                              alreadyRated: false, lastQueuedDay: nil, storageAvailable: true,
                                              unresolvedDay: persistedPending))
        }
    }

    @MainActor
    func testReservationFailureCannotReachIOSAndExpirationReleasesReservation() async {
        let inaccessible = await PromptTransaction.submit(revalidate: { nil }, reserve: { false }, send: {
            XCTFail("Must not call iOS without a durable reservation")
        }, finalize: { _ in XCTFail("No reservation to finalize") })
        XCTAssertEqual(inaccessible, .logUnavailable)

        var reserved = false
        var expired = false
        let stale = await PromptTransaction.submit(revalidate: { expired ? .stale : nil }, reserve: {
            reserved = true
            expired = true
            return true
        }, send: { XCTFail("Must revalidate after reserving") }, finalize: { accepted in
            XCTAssertFalse(accepted)
            reserved = false
        })
        XCTAssertEqual(stale, .stale)
        XCTAssertFalse(reserved)
    }

    @MainActor
    func testIOSRejectionReleasesReservationAndEraseIsNotAnAcceptance() async {
        var reserved = false
        let rejected = await PromptTransaction.submit(revalidate: { nil }, reserve: {
            reserved = true
            return true
        }, send: { throw CocoaError(.fileWriteUnknown) }, finalize: { accepted in
            XCTAssertFalse(accepted)
            reserved = false
        })
        XCTAssertEqual(rejected, .queueFailed)
        XCTAssertFalse(reserved)
        let day = WakeDay.key(now, in: zone)
        XCTAssertEqual(PromptPolicy.blocked(.watchSleep, mode: .either, day: day, currentDay: day,
                                            alreadyRated: false, lastQueuedDay: nil, storageAvailable: true,
                                            erasedToday: true), .logErased)
    }

    @MainActor
    private func tryOverlappingRoutes(firstOutcome: PromptOutcome, expireAlert: Bool = false,
                                      waitingSource: PromptSource = .appleAlert, time: Date? = nil, resumeAt: Date? = nil) async
        -> (first: PromptOutcome, second: PromptOutcome, secondAttempts: Int) {
        let queue = PromptSubmissionQueue()
        let time = time ?? now
        let day = WakeDay.key(time, in: zone)
        let signalTime = resumeAt == nil ? time.addingTimeInterval(-7200) : time
        var submissionTime = time
        let firstEntered = AsyncStream<Void>.makeStream()
        let secondEntered = AsyncStream<Void>.makeStream()
        let releaseFirst = AsyncStream<Void>.makeStream()
        var firstReady = firstEntered.stream.makeAsyncIterator()
        var secondReady = secondEntered.stream.makeAsyncIterator()
        var secondAttempts = 0
        let first = Task { @MainActor in
            await queue.attempt(on: day, revalidate: { nil }) {
                firstEntered.continuation.finish()
                for await _ in releaseFirst.stream {}
                return firstOutcome
            }
        }
        _ = await firstReady.next()
        let second = Task { @MainActor in
            secondEntered.continuation.finish()
            return await queue.attempt(on: day, revalidate: {
                PromptPolicy.eligibleDay(for: waitingSource, signalAt: signalTime, now: submissionTime, zone: self.zone) == day ? nil : .stale
            }) {
                secondAttempts += 1
                return .queued
            }
        }
        _ = await secondReady.next()
        if expireAlert { submissionTime = time.addingTimeInterval(1) }
        if let resumeAt { submissionTime = resumeAt }
        releaseFirst.continuation.finish()
        let firstResult = await first.value
        let secondResult = await second.value
        return (firstResult, secondResult, secondAttempts)
    }
}

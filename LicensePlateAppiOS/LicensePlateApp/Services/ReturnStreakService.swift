//
//  ReturnStreakService.swift
//  LicensePlateApp
//
//  Daily plate-find streak per user. All day-boundary math lives here.
//
//  Calendar semantics (Phase 1):
//  - Uses injectable Calendar (default Calendar.current): device locale + timezone at evaluation time.
//  - Day boundary: calendar.startOfDay(for: now()).
//  - lastQualifyingDay is stored as an absolute Date (start-of-day instant when qualified).
//  - Comparisons use calendar.isDate(_:inSameDayAs:).
//  - Active streak for reads: lastQualifyingDay must be today or yesterday; otherwise currentState reports 0
//    (stored count is left intact until the next qualifying find restarts at 1).
//  - DST / travel: boundaries follow the device calendar; timezone changes may shift perceived days.
//  - Offline: UserDefaults only; idempotent per user per calendar day.
//  - Clock manipulation: local-trust only (no server authority in Phase 1).
//

import Foundation
import Combine

struct ReturnStreakState: Equatable {
    let currentStreak: Int
    let lastQualifyingDay: Date?
}

enum ReturnStreakRecordOutcome: Equatable {
    case disabled
    case noOp(alreadyQualifiedToday: Bool)
    case continued(previousStreak: Int, currentStreak: Int)
    case started(currentStreak: Int)
    case brokenThenStarted(previousStreak: Int)
}

@MainActor
final class ReturnStreakService: ObservableObject {

    static let shared = ReturnStreakService(remoteConfig: RemoteConfigService.shared)

    private enum LegacyDefaultsKey {
        static let currentStreak = "returnStreak.currentStreak"
        static let lastReturnDay = "returnStreak.lastReturnDay"
    }

    private let remoteConfig: RemoteConfigValueProviding
    private let defaults: UserDefaults
    private let calendar: Calendar
    private let now: () -> Date
    private let xpLedger: XpLedgerRepositoryProtocol
    private let catalogProvider: ProgressionCatalogProviding

    private(set) var activeUserId: String?
    private(set) var lastRecordOutcome: ReturnStreakRecordOutcome?

    init(
        remoteConfig: RemoteConfigValueProviding,
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init,
        xpLedger: XpLedgerRepositoryProtocol = XpLedgerRepository.shared,
        catalogProvider: ProgressionCatalogProviding = ProgressionCatalogProvider.shared
    ) {
        self.remoteConfig = remoteConfig
        self.defaults = defaults
        self.calendar = calendar
        self.now = now
        self.xpLedger = xpLedger
        self.catalogProvider = catalogProvider
    }

    func setActiveUserId(_ userId: String?) {
        activeUserId = userId
        if let userId, !userId.isEmpty {
            migrateLegacyDeviceStateIfNeeded(for: userId)
        }
    }

    /// Hard sign-out: remove streak keys for the prior user (and legacy device keys).
    func clearLocalState(forUserId userId: String?) {
        if let userId, !userId.isEmpty {
            defaults.removeObject(forKey: streakKey(userId: userId))
            defaults.removeObject(forKey: lastDayKey(userId: userId))
        }
        defaults.removeObject(forKey: LegacyDefaultsKey.currentStreak)
        defaults.removeObject(forKey: LegacyDefaultsKey.lastReturnDay)
        lastRecordOutcome = nil
        activeUserId = nil
    }

    func consumeLastRecordOutcome() -> ReturnStreakRecordOutcome? {
        defer { lastRecordOutcome = nil }
        return lastRecordOutcome
    }

    func currentState(for userId: String? = nil) -> ReturnStreakState {
        guard let userId = resolvedUserId(userId) else {
            return ReturnStreakState(currentStreak: 0, lastQualifyingDay: nil)
        }
        migrateLegacyDeviceStateIfNeeded(for: userId)
        let lastQualifyingDay = defaults.object(forKey: lastDayKey(userId: userId)) as? Date
        let storedStreak = defaults.integer(forKey: streakKey(userId: userId))
        return ReturnStreakState(
            currentStreak: effectiveStreak(storedStreak: storedStreak, lastQualifyingDay: lastQualifyingDay),
            lastQualifyingDay: lastQualifyingDay
        )
    }

    var isEnabled: Bool {
        remoteConfig.bool(for: .returnStreakEnabled)
    }

    var minDisplayStreak: Int {
        max(1, remoteConfig.int(for: .returnStreakMinDisplay))
    }

    var celebrationEnabled: Bool {
        remoteConfig.bool(for: .returnStreakCelebrationEnabled)
    }

    var celebrationMinStreak: Int {
        max(1, remoteConfig.int(for: .returnStreakCelebrationMinStreak))
    }

    /// Records a qualifying plate find for the active user when the event belongs to them.
    @discardableResult
    func handleCommittedActivityEvent(_ event: TripActivityEvent) -> ReturnStreakRecordOutcome {
        guard let userId = activeUserId, !userId.isEmpty else { return .disabled }
        guard event.kind == .regionFound else { return .noOp(alreadyQualifiedToday: false) }
        let participantId = event.payload?[TripActivityEventPayloadKey.participantId]
            ?? event.actorId
            ?? ""
        guard participantId == userId else { return .noOp(alreadyQualifiedToday: false) }
        return recordQualifyingFindIfNeeded(userId: userId)
    }

    @discardableResult
    func recordQualifyingFindIfNeeded(userId: String) -> ReturnStreakRecordOutcome {
        guard remoteConfig.bool(for: .returnStreakEnabled) else {
            lastRecordOutcome = .disabled
            return .disabled
        }

        migrateLegacyDeviceStateIfNeeded(for: userId)

        let today = calendar.startOfDay(for: now())
        let streakKey = streakKey(userId: userId)
        let lastDayKey = lastDayKey(userId: userId)

        if let lastDay = defaults.object(forKey: lastDayKey) as? Date,
           calendar.isDate(lastDay, inSameDayAs: today) {
            let outcome = ReturnStreakRecordOutcome.noOp(alreadyQualifiedToday: true)
            lastRecordOutcome = outcome
            return outcome
        }

        let previousStreak = defaults.integer(forKey: streakKey)
        let outcome: ReturnStreakRecordOutcome

        if defaults.object(forKey: lastDayKey) as? Date == nil {
            defaults.set(1, forKey: streakKey)
            defaults.set(today, forKey: lastDayKey)
            AnalyticsService.shared.log(.returnStreakQualified(currentStreak: 1, reason: "first"))
            outcome = .started(currentStreak: 1)
        } else if let lastDay = defaults.object(forKey: lastDayKey) as? Date,
                  let previousDay = calendar.date(byAdding: .day, value: -1, to: today),
                  calendar.isDate(lastDay, inSameDayAs: previousDay) {
            let nextStreak = max(1, previousStreak + 1)
            defaults.set(nextStreak, forKey: streakKey)
            defaults.set(today, forKey: lastDayKey)
            AnalyticsService.shared.log(.returnStreakQualified(currentStreak: nextStreak, reason: "continued"))
            outcome = .continued(previousStreak: previousStreak, currentStreak: nextStreak)
        } else {
            if previousStreak > 0 {
                AnalyticsService.shared.log(.returnStreakBroken(previousStreak: previousStreak))
            }
            defaults.set(1, forKey: streakKey)
            defaults.set(today, forKey: lastDayKey)
            AnalyticsService.shared.log(.returnStreakQualified(currentStreak: 1, reason: "restarted_after_gap"))
            outcome = previousStreak > 0 ? .brokenThenStarted(previousStreak: previousStreak) : .started(currentStreak: 1)
        }

        lastRecordOutcome = outcome
        objectWillChange.send()
        grantStreakXpIfNeeded(userId: userId, currentStreak: currentStreak(from: outcome), qualifyingDay: today)
        Task {
            await ReturnStreakReminderService.shared.refreshScheduleIfNeeded(userId: userId)
        }
        return outcome
    }

    func hasQualifiedToday(userId: String? = nil) -> Bool {
        guard let userId = resolvedUserId(userId),
              let lastDay = defaults.object(forKey: lastDayKey(userId: userId)) as? Date else {
            return false
        }
        return calendar.isDate(lastDay, inSameDayAs: calendar.startOfDay(for: now()))
    }

    // MARK: - Private

    /// Live streak for UI/reminders: only today or yesterday keeps the stored count active.
    private func effectiveStreak(storedStreak: Int, lastQualifyingDay: Date?) -> Int {
        guard storedStreak > 0, let lastQualifyingDay else { return 0 }
        let today = calendar.startOfDay(for: now())
        if calendar.isDate(lastQualifyingDay, inSameDayAs: today) {
            return storedStreak
        }
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
              calendar.isDate(lastQualifyingDay, inSameDayAs: yesterday) else {
            return 0
        }
        return storedStreak
    }

    private func resolvedUserId(_ userId: String?) -> String? {
        if let userId, !userId.isEmpty { return userId }
        return activeUserId
    }

    private func streakKey(userId: String) -> String {
        "returnStreak.\(userId).currentStreak"
    }

    private func lastDayKey(userId: String) -> String {
        "returnStreak.\(userId).lastQualifyingDay"
    }

    private func grantStreakXpIfNeeded(userId: String, currentStreak: Int, qualifyingDay: Date) {
        guard currentStreak > 0 else { return }
        guard let group = catalogProvider.current.xpToastGroup(id: "return_streak"),
              let xpReward = group.xpReward,
              xpReward > 0 else { return }

        let minStreak = group.minStreakForXpReward ?? 1
        guard currentStreak >= minStreak else { return }

        let dayKey = calendarDayKey(for: qualifyingDay)
        let uniquenessKey = XpLedgerKeyBuilder.uniquenessKey(
            userId: userId,
            sessionId: XpLedgerGlobalScope.sessionId,
            gameInstanceId: XpLedgerGlobalScope.gameInstanceId,
            itemId: dayKey,
            xpCategory: .returnStreakDaily
        ).storageString

        if let existing = try? xpLedger.ledgerEvents(forUniquenessKey: uniquenessKey), !existing.isEmpty {
            Task {
                await ReturnStreakDailyXpClaimService.shared.claimIfNeeded(
                    userId: userId,
                    dayKey: dayKey,
                    currentStreak: currentStreak
                )
            }
            return
        }

        let event = XpLedgerEvent(
            userId: userId,
            sessionId: XpLedgerGlobalScope.sessionId,
            gameInstanceId: XpLedgerGlobalScope.gameInstanceId,
            sourceEventId: "return_streak|\(dayKey)",
            sourceEventType: "return_streak",
            itemId: dayKey,
            grantKind: .milestoneUnlock,
            status: .final,
            xpDelta: xpReward,
            reasonCode: .returnStreakDaily,
            xpUniquenessKey: uniquenessKey,
            metadata: [XpLedgerMetadataKey.returnStreakDayCount: "\(currentStreak)"]
        )
        try? xpLedger.append(event)
        Task {
            await ReturnStreakDailyXpClaimService.shared.claimIfNeeded(
                userId: userId,
                dayKey: dayKey,
                currentStreak: currentStreak
            )
        }
    }

    private func currentStreak(from outcome: ReturnStreakRecordOutcome) -> Int {
        switch outcome {
        case .started(let currentStreak), .continued(_, let currentStreak):
            return currentStreak
        case .brokenThenStarted:
            return 1
        case .disabled, .noOp:
            return 0
        }
    }

    private func calendarDayKey(for day: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: day)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let dayOfMonth = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, dayOfMonth)
    }

    private func migrateLegacyDeviceStateIfNeeded(for userId: String) {
        let userStreakKey = streakKey(userId: userId)
        let userLastDayKey = lastDayKey(userId: userId)

        if defaults.object(forKey: userLastDayKey) != nil { return }

        let legacyStreak = defaults.integer(forKey: LegacyDefaultsKey.currentStreak)
        guard legacyStreak > 0,
              let legacyLastDay = defaults.object(forKey: LegacyDefaultsKey.lastReturnDay) as? Date else {
            return
        }

        defaults.set(legacyStreak, forKey: userStreakKey)
        defaults.set(legacyLastDay, forKey: userLastDayKey)
        defaults.removeObject(forKey: LegacyDefaultsKey.currentStreak)
        defaults.removeObject(forKey: LegacyDefaultsKey.lastReturnDay)
    }
}

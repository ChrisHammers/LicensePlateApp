//
//  LocalUserDataPurgeService.swift
//  LicensePlateApp
//
//  Hard sign-out: freeze cloud I/O, wipe local SwiftData + user-scoped caches,
//  reset in-memory services. Does not cancel remote trips or delete cloud accounts.
//

import Foundation
import SwiftData

extension Notification.Name {
    /// Posted just before a hard local wipe so UI can unbind from the outgoing user.
    static let accountWillHardSignOut = Notification.Name("LocalUserDataPurgeService.accountWillHardSignOut")
    /// Posted after a hard local wipe so UI coordinators can clear navigation / reload lists.
    static let accountDidHardSignOut = Notification.Name("LocalUserDataPurgeService.accountDidHardSignOut")
}

@MainActor
final class LocalUserDataPurgeService {

    static let shared = LocalUserDataPurgeService()

    private static let pendingAutoRecapDefaultsKey = "tripEnd.pendingAutoRecapSessionIds"
    private static let returnStreakReminderPendingOpenKey = "returnStreakReminderPendingOpen"

    private init() {}

    /// Ordered purge for hard sign-out. Leaves sync processing suspended; caller resumes after guest rebirth.
    func purgeAllLocalUserData(oldUserId: String) throws {
        freezeIO()
        try wipeSwiftData()
        clearUserScopedUserDefaults(oldUserId: oldUserId)
        resetInMemoryServices()
    }

    // MARK: - Freeze

    private func freezeIO() {
        SyncCoordinator.shared.suspendProcessingForPurge()

        TripInviteRepository.shared.stopListening()
        FriendshipRepository.shared.stopListening()
        InviteRepository.shared.stopListening()
        FamilyRepository.shared.stopListening()
        UserProgressionRepository.shared.stopListening()
        XpGrantRemoteRepository.shared.stopListening()
        UserAchievementRemoteRepository.shared.stopListening()
        UserProfileListenCoordinator.shared.stopAll()
        TripCanonicalRemoteSyncService.shared.removeAllIncrementalListeners()
        PublicLifetimeStatsRepository.shared.stopAllListeners()
        SocialInboxBadgeService.shared.stopObserving()
        NotificationRoutingService.shared.stopObserving()

        TripRouteTrackingService.shared.stopForAccountPurge()
        ReminderNotificationService.shared.cancelAllReminders(reason: "account_purge")
        ReturnStreakReminderService.shared.cancelReminder(reason: "account_purge")
    }

    // MARK: - Disk

    private func wipeSwiftData() throws {
        // Sync outbound first — never upload after this.
        try SyncQueueRepository.shared.deleteAllLocal()
        try PendingTripLeaveRepository.shared.deleteAllLocal()

        // Gameplay tree (local only; no remote cancel).
        try TripActivityEventRepository.shared.deleteAllLocal()
        try DiscoveryResolutionRepository.shared.deleteAllLocal()
        try XpLedgerRepository.shared.deleteAllLocal()
        try GameInstanceRepository.shared.deleteAllLocal()
        try TripRoutePointRepository.shared.deleteAllLocal()
        try TripSessionRepository.shared.deleteAllLocal()

        // Social + progression caches.
        try TripInviteRepository.shared.deleteAllLocal()
        try FriendshipRepository.shared.deleteAllLocal()
        try InviteRepository.shared.deleteAllLocal()
        try FamilyRepository.shared.deleteAllLocal()
        try UserAchievementRepository.shared.deleteAllLocal()
        try UserLifetimeStatsRepository.shared.deleteAllLocal()
        try PublicLifetimeStatsRepository.shared.deleteAllLocalCache()

        // Users last (self + peer hydrations).
        try UserRepository.shared.deleteAllLocalUsers()
    }

    private func clearUserScopedUserDefaults(oldUserId: String) {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Self.pendingAutoRecapDefaultsKey)
        defaults.removeObject(forKey: Self.returnStreakReminderPendingOpenKey)
        ReturnStreakService.shared.clearLocalState(forUserId: oldUserId)
    }

    // MARK: - Memory

    private func resetInMemoryServices() {
        UserProgressionService.shared.resetForSignOut()
        ProgressionXpDriftAfterSyncReporter.shared.resetForSignOut()
        XpGrantReconcileService.shared.resetForSignOut()
        AchievementUnlockCelebrationService.shared.resetForSignOut()
        AchievementUnlockSyncService.shared.resetForSignOut()
        ReturnStreakDailyXpClaimService.shared.resetForSignOut()
        ChildRestrictedDataRecoveryService.shared.resetForSignOut()
        XpGainToastService.shared.resetForSignOut()

        EntitlementService.shared.resetForAccountPurge()
        LifetimeStatsCoordinator.shared.resetForAccountPurge()
        NotificationPrefsStore.shared.resetToDefaults()
        AppPrefsStore.shared.resetToDefaults()
        TripParticipantPrefsStore.shared.resetForSignOut()
        DeepLinkHandler.shared.clearDestination()
        ReturnStreakService.shared.setActiveUserId(nil)
    }
}

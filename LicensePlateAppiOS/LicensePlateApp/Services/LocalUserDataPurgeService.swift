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

    /// §3.1.1 item 7 (2026-08-28): teardown for a DETACHED identity — the account behind
    /// the session is gone but the PLAYER keeps their device. Two halves, both required:
    /// stop every uid-keyed cloud channel (they can only bounce off rules or resurrect
    /// server state the deletion just removed), and wipe the SOCIAL projections that
    /// would otherwise keep rendering a family the server dissolved (owner device pass:
    /// a removed-and-deleted child's app showed "part of the team" from purely local
    /// rows, launch after launch). Gameplay rows are deliberately KEPT — FR-28h carries
    /// local history across the consent boundary, resolved by the retired uid on
    /// `AppUser.id`. Best-effort on the disk wipes: a failed cache delete must not stop
    /// the detach that is protecting the session.
    func purgeSocialStateForDetachedIdentity() {
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

        try? TripInviteRepository.shared.deleteAllLocal()
        try? FriendshipRepository.shared.deleteAllLocal()
        try? InviteRepository.shared.deleteAllLocal()
        try? FamilyRepository.shared.deleteAllLocal()
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
        // §3.1.1 item 15: the purge deletes the local achievement records, so leaving the
        // already-celebrated marks behind would silence an achievement the player re-earns.
        RewardDeliveryOutbox.shared.reset(userId: oldUserId)
    }

    // MARK: - Memory

    private func resetInMemoryServices() {
        UserProgressionService.shared.resetForSignOut()
        ProgressionXpDriftAfterSyncReporter.shared.resetForSignOut()
        XpGrantReconcileService.shared.resetForSignOut()
        AchievementUnlockCelebrationService.shared.resetForSignOut()
        // §3.1.1 item 15 (2026-09-19): a purge, unlike an identity change, also deletes the local
        // achievement rows and the uid's outbox marks — so the in-process "already shown" ledger
        // has to go with them, or a re-earned id stays muted until the app is killed. This is the
        // ONLY caller; `resetForSignOut` deliberately leaves the ledger alone.
        AchievementUnlockCelebrationService.shared.resetProcessPresentationsForAccountPurge()
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

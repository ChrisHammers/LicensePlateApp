//
//  AnalyticsService.swift
//  LicensePlateApp
//
//  Created for Friends & Family MVP
//  Step 10: AnalyticsLogging protocol, screen_view, user properties.
//

import Foundation
import FirebaseAnalytics
import Firebase

// MARK: - AnalyticsLogging Protocol

/// Protocol for analytics logging. Use for DI so ViewModels/Services can be tested with a spy.
@MainActor
protocol AnalyticsLogging: AnyObject {
    func log(_ event: AnalyticsService.Event)
    func log(_ name: String, parameters: [String: Any])
    func setUserProperty(_ value: String?, forName name: String)
}

// MARK: - AnalyticsService

@MainActor
class AnalyticsService: AnalyticsLogging {
    static let shared = AnalyticsService()
    
    private init() {}
    
    // MARK: - Event Constants
    
    enum Event {
        // Navigation / Entry
        case friendsScreenOpened
        case familyScreenOpened
        case friendsFamilySignUpGateShown(feature: String)
        case addFriendCTATapped
        case inviteViaQROpened
        case inviteViaCodeOpened
        case deepLinkOpened(type: String, params: [String: String])
        
        // Search
        case userSearchPerformed(queryType: String)
        case userSearchResultSelected
        
        // Friends
        case friendRequestSent
        case friendRequestReceived
        case friendRequestAccepted
        case friendRequestDeclined
        case friendRemoved
        case friendCapReached
        
        // Family
        case familyCreateCTATapped
        case familyJoinCTATapped
        case familyCreated
        case familyCreateFailed(error: String)
        case familyJoinCodeRedeemed
        case familyJoinFailed(error: String)
        case familyInviteSent
        case familyInviteUserAccepted
        case familyInviteUserDeclined
        case familyJoinRequestCreated
        case familyJoinRequestApproved
        case familyJoinRequestDeclined
        case familyMemberRemoved
        case familyRoleChanged
        case familyNameChanged
        case familyMarkedInactiveCreatorLeftOrDeleted
        
        // Codes
        case shareCodeGenerated(type: String)
        case shareCodeUsed(type: String)
        case shareCodeExpired
        case shareCodeRevoked
        
        // Auto rejection / Edge cases
        case inviteAutoRejectedUserAlreadyInFamily
        case inviteAutoRejectedNotSearchable
        case inviteFailedRateLimited
        case inviteFailedPermissionDenied
        
        // Avatar & Badge (MVP Identity)
        case avatarAssignedRandom
        case avatarPickerOpened(source: String)
        case avatarSelected(avatarId: String)
        case avatarSaved(avatarId: String, source: String)
        case avatarLockedTapped(avatarId: String, unlockSource: String)
        case avatarUpgradePrompt
        case avatarUpgradeClicked
        case badgeProgress(badgeId: String, progress: Int)
        case badgeUnlocked(badgeId: String)
        case badgeEquipped(badgeId: String)
        case founderEntitlementGranted
        case founderEntitlementGrantSkipped(reason: String)

        // Trip invites (Step 04)
        case tripInvitesScreenOpened
        case tripInviteAccepted
        case tripInviteDeclined
        case tripInviteCanceled
        /// Step 08 — server send succeeded (no PII: trip id + name length only).
        case tripInviteSent(tripSessionId: String, tripNameLength: Int)
        case tripInviteSendFailed(tripSessionId: String, error: String)
        case tripInviteReceivedViewed(inviteId: String?)
        case tripParticipantsViewed(tripSessionId: String)

        // Trip invite with context (Step 10.5)
        case tripInviteAcceptedWithContext(inviteTripId: String?, inviteGameCount: Int?, participantCountAfterJoin: Int?)
        case tripInviteDeclinedWithContext(inviteTripId: String?, inviteGameCount: Int?)
        case participantJoinedTrip(tripId: String, participantCountAfterJoin: Int, teamCountAfterJoin: Int?)
        case participantLeftTrip(tripId: String)
        /// Step 14 — non-owner initiated voluntary leave (local + queued sync).
        case tripParticipantLeaveInitiated(tripSessionId: String, offline: Bool)
        /// Step 14 — `participant_left` accepted by `appendTripActivityEvent`.
        case tripParticipantLeaveServerCompleted(tripSessionId: String)
        /// Step 14 — Firestore `members` snapshot no longer includes this user; local roster aligned.
        case tripParticipantLeaveReconciled(tripSessionId: String)
        case participantRemovedFromTrip(tripId: String, actorParticipantId: String?)

        // Combined games (Step 06)
        case combinedTripSetupOpened
        case tripSetupOpened
        case gameSetupOpened
        case gameSetupAddGameOpened(tripSessionId: String)
        case combinedTripCreated(
            gameTypes: [String],
            tripSessionId: String? = nil,
            participantCount: Int? = nil,
            gameCount: Int? = nil,
            gameModes: [String]? = nil,
            hasTeams: Bool? = nil
        )

        // Combined games extended (Step 10.5)
        case combinedGameRemovedBeforeStart(gameInstanceId: String, combinedGameCount: Int)
        case combinedGameReordered(combinedGameCount: Int, combinedGameTypes: [String])
        case combinedGameDefaultRetained(combinedPrimaryGameType: String)
        case combinedGameConfigChanged(gameInstanceId: String, settingKey: String, oldValue: String, newValue: String)
        case combinedTripStartedWithGameCount(tripId: String, combinedGameCount: Int, combinedGameTypes: [String])

        // Travel Log (Step 07)
        case travelLogOpened
        case tripSummaryViewed(sessionId: String)
        case tripSummaryAutoPresentedAfterEnd(sessionId: String, source: String)
        case tripEndedRemoteToastShown(sessionId: String)

        // Summary / Travel log extended (Step 10.5)
        case tripSummaryViewedGameSection(sessionId: String)
        case tripSummaryViewedParticipantSection(sessionId: String)
        case tripSummaryViewedMapRecap(sessionId: String)
        /// Travel log recap XP ledger section shown (Step XP 03).
        case tripSummaryViewedXpRecap(sessionId: String)
        /// Step 11 — Travel log summary includes at least one competitive game (rankings section).
        case tripSummaryCompetitiveRankingsPresented(tripSessionId: String)
        /// Step 11 — In-game competitive standings first shown (multiplayer).
        case competitiveInGameStandingsPresented(tripSessionId: String, gameInstanceId: String)
        /// Step 12 — Trip dashboard trip-wide competitive leaderboard first shown (multiplayer).
        case tripDashboardCompetitiveLeaderboardPresented(tripSessionId: String)

        case travelLogFiltered(filterKey: String, filterValue: String)
        case travelLogSorted(sortKey: String)

        /// Profile lifetime stats — emitted from `LifetimeStatsCoordinator` only (no PII).
        case lifetimeStatsRecomputeStarted
        case lifetimeStatsRecomputeSucceeded(completedTripCount: Int, familyOnlyTripCount: Int)
        case lifetimeStatsRecomputeFailed(error: String)
        /// User tapped retry on profile stats error row (`LifetimeStatsProfileViewModel` only).
        case lifetimeStatsProfileRetryTapped
        /// Firestore listener applied a `public_lifetime_stats` document (length only, no uid).
        case publicLifetimeStatsListenerUpdated(userIdLength: Int)
        /// Shown when UI displays the pending-server-sync state (surface key, no PII).
        case lifetimeStatsPendingSyncShown(surface: String)
        /// Local `LifetimeStatsRecomputeEngine` path ran for offline / explicit retry.
        case lifetimeStatsFallbackRecomputeUsed(reason: String)

        // Step 16 — `user_progression` (emitted from `UserProgressionService` only)
        case progressionSnapshotApplied(totalXp: Int, acceptedRegionFindCount: Int, competitiveFirstPlaceFinishes: Int)
        case progressionMilestoneEverCompetitiveFirstPlace
        case progressionXpAwarded(delta: Int, reason: String)
        case progressionRewardsPresentationOverrideApplied(visualBandSize: Int, xpPerRankLevel: Int)
        case progressionRewardsConfigFallback(reason: String)
        case progressionCatalogPresentationOverrideApplied(achievementsEnabled: Bool, rankProgressionEnabled: Bool)
        case progressionCatalogConfigFallback(reason: String)
        case achievementUnlocked(achievementId: String, category: String, rarity: String)
        case rankUpCelebrated(level: Int, totalXp: Int)
        case achievementCelebrationDismissed(eventId: String, kind: String)
        case achievementUnlockSyncSucceeded(recordedCount: Int, alreadySyncedCount: Int, rejectedCount: Int)
        case achievementUnlockSyncFailed(candidateCount: Int, errorSummary: String)
        case xpGrantAwarded(tripId: String, gameInstanceId: String, targetId: String, participantId: String)
        case xpGrantSkippedAlreadyGranted(tripId: String, gameInstanceId: String, targetId: String, participantId: String)
        case xpGainToastPresented(lineCount: Int, totalXp: Int, coalesced: Bool, sourceMix: String, groupIds: String)
        case xpGainToastDismissed(reason: String)

        // Lifecycle (Step 10.5)
        case tripSessionCreated(tripId: String, tripStatus: String, tripParticipantCount: Int?, tripActiveGameCount: Int?, tripSource: String?)
        case tripSessionStarted(tripId: String, tripActiveGameCount: Int?)
        case tripSessionEnded(tripId: String)
        /// GPS Step 6 — route capture lifecycle. Session id only; never coordinates or point counts.
        case routeTrackingStarted(tripId: String)
        case routeTrackingStopped(tripId: String)
        /// Step 6.9.3 — Game progress reset (discoveries cleared for one game); not a trip reset.
        case gameInstanceReset(tripSessionId: String, gameInstanceId: String)
        /// One game removed from a multi-game trip (local instance + its events).
        case gameInstanceDeleted(tripSessionId: String, gameInstanceId: String, gameType: String, remainingGameCount: Int)
        /// Trip cancelled from active list or settings (soft delete UX).
        case tripSessionCancelled(tripId: String)
        /// Reserved for future hard tombstone delete; not emitted on cancel today.
        case tripSessionDeleted(tripId: String)
        case gameInstanceCreated(gameInstanceId: String, gameType: String, gameMode: String, tripId: String, gameOrderInTrip: Int?)
        case gameInstanceStarted(gameInstanceId: String, gameType: String, gameLifecycleState: String, configLockReason: String, tripSessionId: String)
        case gameInstanceEnded(gameInstanceId: String, gameType: String, tripSessionId: String)
        case gameInstanceCompleted(gameInstanceId: String, gameType: String, tripSessionId: String)
        case gameConfigLocked(gameInstanceId: String, configLockReason: String)
        case gameConfigLockBlockedEdit(gameInstanceId: String, configLockReason: String)

        // Config edit (Step 10.5)
        case gameConfigViewed(gameInstanceId: String, configLocked: Bool, configLockReason: String)
        case gameConfigChanged(gameInstanceId: String, settingKey: String, oldValue: String, newValue: String, changeSurface: String?)
        case gameConfigChangeFailed(gameInstanceId: String, settingKey: String, error: String)
        case gameConfigUnlockAttempted(gameInstanceId: String, configLockReason: String)
        case gameConfigEventOverrideApplied(gameInstanceId: String, lockReason: String, editPolicy: String)

        // Error / mismatch (Step 10.5)
        case gameConfigPayloadDecodeFailed(gameInstanceId: String?, error: String)
        case creditResolutionFailed(discoveryId: String, error: String)
        case summaryProjectionMismatch(sessionId: String, error: String)
        case unsupportedGamePayloadVersion(payloadType: String, payloadVersion: String)
        case analyticsPropertyBuildFailed(eventName: String, error: String)

        // Risk advisory (Step 11)
        case riskAdvisoryDetected(flags: [String], tripId: String)

        // Discovery outcome (Step 03 — rules engine)
        case discoveryOutcomeRecorded(tripId: String, gameInstanceId: String, targetId: String, outcome: String, participantId: String?)
        case discoveryRejectedDuplicate(tripId: String, gameInstanceId: String, targetId: String, participantId: String?, mode: String)
        case discoveryRejectedInvalidParticipant(tripId: String, gameInstanceId: String, targetId: String, participantId: String?, tripParticipantCount: Int, gameMode: String)
        case discoveryRemovalConfirmed(tripId: String, gameInstanceId: String, targetId: String, participantId: String?) // almost a duplicate of Unfind, but based on the cooldown service, which I basically disabled.
        case discoveryRetapBlockedByCooldown(tripId: String, gameInstanceId: String, targetId: String)
        case discoveryUnfind(tripId: String, gameInstanceId: String, targetId: String, participantId: String?)

        // Step 13 — Cloud gameplay resolver / sync
        case gameplayEventServerAccepted(tripSessionId: String, gameInstanceId: String, eventKind: String)
        case gameplayEventServerSuperseded(tripSessionId: String, gameInstanceId: String, serverRejectionEventId: String, reason: String)
        case gameplayEventServerRejected(tripSessionId: String, eventKind: String, errorCode: Int, errorDomain: String)
        /// Client-side `appendTripActivityEvent` did not complete within the coordinator timeout (transient; queue will retry).
        case gameplayEventAppendTimedOut(tripSessionId: String, gameInstanceId: String, eventKind: String, attemptCount: Int, timeoutSeconds: Int)

        // Persistence (Step 05)
        case persistenceSaveFailed(context: String, error: String)
        case persistenceRetryTapped(context: String)

        // Notifications & eligibility (Step 08)
        case notificationEligibilityChecked(kind: String, eligible: Bool)
        case notificationDeliveredTripInvite
        case notificationDeliveredFriendInvite
        case notificationDeliveredFamilyInvite
        case notificationDeliveryFailed(error: String)

        // Step 18 — launch operations, growth, and monetization
        case remoteConfigFetchSucceeded
        case remoteConfigFetchFailed(error: String)
        case crashReportingConfigured
        case crashReportingNonFatalRecorded(context: String)
        case adEligibilityEvaluated(surface: String, eligible: Bool, reason: String)
        case adImpression(surface: String)
        case adLoadFailed(surface: String, error: String)
        case reviewPromptEligible(completedTripCount: Int)
        case reviewPromptPresented(sessionId: String)
        case reviewPromptSuppressed(reason: String, completedTripCount: Int)
        case reminderScheduled(sessionId: String, hours: Int)
        case reminderCancelled(sessionId: String, reason: String)
        case returnStreakUpdated(currentStreak: Int, reason: String)
        case returnStreakReset(reason: String)
        case returnStreakQualified(currentStreak: Int, reason: String)
        case returnStreakBroken(previousStreak: Int)
        case returnStreakDisplayed(currentStreak: Int, surface: String)
        case returnStreakExplanationOpened(currentStreak: Int)
        case returnStreakCelebrationShown(currentStreak: Int)
        case returnStreakReminderScheduled(hour: Int)
        case returnStreakReminderOpened(currentStreak: Int)
        case fcmTokenRegistered

        // First-session quick solo onboarding funnel
        case onboardingStarted(flowVariant: String, offline: Bool)
        case onboardingStepViewed(stepId: String, stepIndex: Int, flowVariant: String)
        case onboardingAbandoned(lastStepId: String, flowVariant: String, elapsedMs: Int)
        case onboardingCompleted(flowVariant: String, elapsedMs: Int, offline: Bool)
        case quickSoloTripStarted(tripSessionId: String, gameInstanceId: String, offline: Bool, elapsedMs: Int)
        case firstFindCompleted(tripSessionId: String, gameInstanceId: String, targetId: String, elapsedMs: Int, inputMethod: String)
        case deferredSetupPromptShown(pendingSteps: String)
        case deferredSetupStepOpened(stepId: String, source: String)
        case deferredSetupStepCompleted(stepId: String)
        case deferredSetupStepTouched(stepId: String, source: String)

        /// Auth profile restore could not read Firestore (no PII).
        /// `outcome`: `keep_local` (had SwiftData row) or `abort_no_create` (did not invent guest profile).
        case authProfileHydrateFailed(outcome: String)

        // Screen view (Step 10)
        case screenView(screenName: String, screenClass: String?)

        // Paywall & RevenueCat (Step 09)
        case paywallViewed(source: String?)
        case paywallDismissed
        case tripLimitHit(source: String, activeTripCount: Int, activeTripLimit: Int, tier: String)
        case savedTripLimitHit(source: String, savedTripCount: Int, savedTripLimit: Int, tier: String)
        case purchaseStarted(packageId: String)
        case purchaseCompleted(packageId: String)
        case purchaseFailed(packageId: String?, error: String)
        case restoreStarted
        case restoreCompleted
        case restoreFailed(error: String)

        var name: String {
            switch self {
            case .friendsScreenOpened: return "friends_screen_opened"
            case .familyScreenOpened: return "family_screen_opened"
            case .friendsFamilySignUpGateShown: return "friends_family_sign_up_gate_shown"
            case .addFriendCTATapped: return "add_friend_cta_tapped"
            case .inviteViaQROpened: return "invite_via_qr_opened"
            case .inviteViaCodeOpened: return "invite_via_code_opened"
            case .deepLinkOpened: return "deep_link_opened"
            case .userSearchPerformed: return "user_search_performed"
            case .userSearchResultSelected: return "user_search_result_selected"
            case .friendRequestSent: return "friend_request_sent"
            case .friendRequestReceived: return "friend_request_received"
            case .friendRequestAccepted: return "friend_request_accepted"
            case .friendRequestDeclined: return "friend_request_declined"
            case .friendRemoved: return "friend_removed"
            case .friendCapReached: return "friend_cap_reached"
            case .familyCreateCTATapped: return "family_create_cta_tapped"
            case .familyJoinCTATapped: return "family_join_cta_tapped"
            case .familyCreated: return "family_created"
            case .familyCreateFailed: return "family_create_failed"
            case .familyJoinCodeRedeemed: return "family_join_code_redeemed"
            case .familyJoinFailed: return "family_join_failed"
            case .familyInviteSent: return "family_invite_sent"
            case .familyInviteUserAccepted: return "family_invite_user_accepted"
            case .familyInviteUserDeclined: return "family_invite_user_declined"
            case .familyJoinRequestCreated: return "family_join_request_created"
            case .familyJoinRequestApproved: return "family_join_request_approved"
            case .familyJoinRequestDeclined: return "family_join_request_declined"
            case .familyMemberRemoved: return "family_member_removed"
            case .familyRoleChanged: return "family_role_changed"
            case .familyNameChanged: return "family_name_changed"
            case .familyMarkedInactiveCreatorLeftOrDeleted: return "family_marked_inactive_creator_left_or_deleted"
            case .shareCodeGenerated: return "share_code_generated"
            case .shareCodeUsed: return "share_code_used"
            case .shareCodeExpired: return "share_code_expired"
            case .shareCodeRevoked: return "share_code_revoked"
            case .inviteAutoRejectedUserAlreadyInFamily: return "invite_auto_rejected_user_already_in_family"
            case .inviteAutoRejectedNotSearchable: return "invite_auto_rejected_not_searchable"
            case .inviteFailedRateLimited: return "invite_failed_rate_limited"
            case .inviteFailedPermissionDenied: return "invite_failed_permission_denied"
            case .avatarAssignedRandom: return "avatar_assigned_random"
            case .avatarPickerOpened: return "avatar_picker_opened"
            case .avatarSelected: return "avatar_selected"
            case .avatarSaved: return "avatar_saved"
            case .avatarLockedTapped: return "avatar_locked_tapped"
            case .avatarUpgradePrompt: return "avatar_upgrade_prompt"
            case .avatarUpgradeClicked: return "avatar_upgrade_clicked"
            case .badgeProgress: return "badge_progress"
            case .badgeUnlocked: return "badge_unlocked"
            case .badgeEquipped: return "badge_equipped"
            case .founderEntitlementGranted: return "founder_entitlement_granted"
            case .founderEntitlementGrantSkipped: return "founder_entitlement_grant_skipped"
            case .tripInvitesScreenOpened: return "trip_invites_screen_opened"
            case .tripInviteAccepted: return "trip_invite_accepted"
            case .tripInviteDeclined: return "trip_invite_declined"
            case .tripInviteCanceled: return "trip_invite_canceled"
            case .tripInviteSent: return "trip_invite_sent"
            case .tripInviteSendFailed: return "trip_invite_send_failed"
            case .tripInviteReceivedViewed: return "trip_invite_received_viewed"
            case .tripParticipantsViewed: return "trip_participants_viewed"
            case .tripInviteAcceptedWithContext: return "trip_invite_accepted"
            case .tripInviteDeclinedWithContext: return "trip_invite_declined"
            case .participantJoinedTrip: return "participant_joined_trip"
            case .participantLeftTrip: return "participant_left_trip"
            case .tripParticipantLeaveInitiated: return "trip_participant_leave_initiated"
            case .tripParticipantLeaveServerCompleted: return "trip_participant_leave_server_completed"
            case .tripParticipantLeaveReconciled: return "trip_participant_leave_reconciled"
            case .participantRemovedFromTrip: return "participant_removed_from_trip"
            case .combinedTripSetupOpened: return "combined_trip_setup_opened"
            case .tripSetupOpened: return "trip_setup_opened"
            case .gameSetupOpened: return "game_setup_opened"
            case .gameSetupAddGameOpened: return "game_setup_add_game_opened"
            case .combinedTripCreated: return "combined_trip_created"
            case .combinedGameRemovedBeforeStart: return "combined_game_removed_before_start"
            case .combinedGameReordered: return "combined_game_reordered"
            case .combinedGameDefaultRetained: return "combined_game_default_retained"
            case .combinedGameConfigChanged: return "combined_game_config_changed"
            case .combinedTripStartedWithGameCount: return "combined_trip_started_with_game_count"
            case .travelLogOpened: return "travel_log_opened"
            case .tripSummaryViewed: return "trip_summary_viewed"
            case .tripSummaryAutoPresentedAfterEnd: return "trip_summary_auto_presented_after_end"
            case .tripEndedRemoteToastShown: return "trip_ended_remote_toast_shown"
            case .tripSummaryViewedGameSection: return "trip_summary_viewed_game_section"
            case .tripSummaryViewedParticipantSection: return "trip_summary_viewed_participant_section"
            case .tripSummaryViewedMapRecap: return "trip_summary_viewed_map_recap"
            case .tripSummaryViewedXpRecap: return "trip_summary_viewed_xp_recap"
            case .tripSummaryCompetitiveRankingsPresented: return "trip_summary_competitive_rankings_presented"
            case .competitiveInGameStandingsPresented: return "competitive_in_game_standings_presented"
            case .tripDashboardCompetitiveLeaderboardPresented: return "trip_dashboard_competitive_leaderboard_presented"
            case .travelLogFiltered: return "travel_log_filtered"
            case .travelLogSorted: return "travel_log_sorted"
            case .lifetimeStatsRecomputeStarted: return "lifetime_stats_recompute_started"
            case .lifetimeStatsRecomputeSucceeded: return "lifetime_stats_recompute_succeeded"
            case .lifetimeStatsRecomputeFailed: return "lifetime_stats_recompute_failed"
            case .lifetimeStatsProfileRetryTapped: return "lifetime_stats_profile_retry_tapped"
            case .publicLifetimeStatsListenerUpdated: return "public_lifetime_stats_listener_updated"
            case .lifetimeStatsPendingSyncShown: return "lifetime_stats_pending_sync_shown"
            case .lifetimeStatsFallbackRecomputeUsed: return "lifetime_stats_fallback_recompute_used"
            case .progressionSnapshotApplied: return "progression_snapshot_applied"
            case .progressionMilestoneEverCompetitiveFirstPlace: return "progression_milestone_ever_competitive_first_place"
            case .progressionXpAwarded: return "progression_xp_awarded"
            case .progressionRewardsPresentationOverrideApplied: return "progression_rewards_presentation_override_applied"
            case .progressionRewardsConfigFallback: return "progression_rewards_config_fallback"
            case .progressionCatalogPresentationOverrideApplied: return "progression_catalog_presentation_override_applied"
            case .progressionCatalogConfigFallback: return "progression_catalog_config_fallback"
            case .achievementUnlocked: return "achievement_unlocked"
            case .rankUpCelebrated: return "rank_up"
            case .achievementCelebrationDismissed: return "achievement_celebration_dismissed"
            case .achievementUnlockSyncSucceeded: return "achievement_unlock_sync_succeeded"
            case .achievementUnlockSyncFailed: return "achievement_unlock_sync_failed"
            case .xpGrantAwarded: return "xp_grant_awarded"
            case .xpGrantSkippedAlreadyGranted: return "xp_grant_skipped_already_granted"
            case .xpGainToastPresented: return "xp_gain_toast_presented"
            case .xpGainToastDismissed: return "xp_gain_toast_dismissed"
            case .tripSessionCreated: return "trip_session_created"
            case .tripSessionStarted: return "trip_session_started"
            case .tripSessionEnded: return "trip_session_ended"
            case .routeTrackingStarted: return "route_tracking_started"
            case .routeTrackingStopped: return "route_tracking_stopped"
            case .gameInstanceReset: return "game_instance_reset"
            case .gameInstanceDeleted: return "game_instance_deleted"
            case .tripSessionCancelled: return "trip_session_cancelled"
            case .tripSessionDeleted: return "trip_session_deleted"
            case .gameInstanceCreated: return "game_instance_created"
            case .gameInstanceStarted: return "game_instance_started"
            case .gameInstanceEnded: return "game_instance_ended"
            case .gameInstanceCompleted: return "game_instance_completed"
            case .gameConfigLocked: return "game_config_locked"
            case .gameConfigLockBlockedEdit: return "game_config_lock_blocked_edit"
            case .gameConfigViewed: return "game_config_viewed"
            case .gameConfigChanged: return "game_config_changed"
            case .gameConfigChangeFailed: return "game_config_change_failed"
            case .gameConfigUnlockAttempted: return "game_config_unlock_attempted"
            case .gameConfigEventOverrideApplied: return "game_config_event_override_applied"
            case .gameConfigPayloadDecodeFailed: return "game_config_payload_decode_failed"
            case .creditResolutionFailed: return "credit_resolution_failed"
            case .summaryProjectionMismatch: return "summary_projection_mismatch"
            case .unsupportedGamePayloadVersion: return "unsupported_game_payload_version"
            case .analyticsPropertyBuildFailed: return "analytics_property_build_failed"
            case .notificationEligibilityChecked: return "notification_eligibility_checked"
            case .notificationDeliveredTripInvite: return "notification_delivered_trip_invite"
            case .notificationDeliveredFriendInvite: return "notification_delivered_friend_invite"
            case .notificationDeliveredFamilyInvite: return "notification_delivered_family_invite"
            case .notificationDeliveryFailed: return "notification_delivery_failed"
            case .remoteConfigFetchSucceeded: return "remote_config_fetch_succeeded"
            case .remoteConfigFetchFailed: return "remote_config_fetch_failed"
            case .crashReportingConfigured: return "crash_reporting_configured"
            case .crashReportingNonFatalRecorded: return "crash_reporting_non_fatal_recorded"
            case .adEligibilityEvaluated: return "ad_eligibility_evaluated"
            case .adImpression: return "ad_impression"
            case .adLoadFailed: return "ad_load_failed"
            case .reviewPromptEligible: return "review_prompt_eligible"
            case .reviewPromptPresented: return "review_prompt_presented"
            case .reviewPromptSuppressed: return "review_prompt_suppressed"
            case .reminderScheduled: return "reminder_scheduled"
            case .reminderCancelled: return "reminder_cancelled"
            case .returnStreakUpdated: return "return_streak_updated"
            case .returnStreakReset: return "return_streak_reset"
            case .returnStreakQualified: return "return_streak_qualified"
            case .returnStreakBroken: return "return_streak_broken"
            case .returnStreakDisplayed: return "return_streak_displayed"
            case .returnStreakExplanationOpened: return "return_streak_explanation_opened"
            case .returnStreakCelebrationShown: return "return_streak_celebration_shown"
            case .returnStreakReminderScheduled: return "return_streak_reminder_scheduled"
            case .returnStreakReminderOpened: return "return_streak_reminder_opened"
            case .fcmTokenRegistered: return "fcm_token_registered"
            case .onboardingStarted: return "onboarding_started"
            case .onboardingStepViewed: return "onboarding_step_viewed"
            case .onboardingAbandoned: return "onboarding_abandoned"
            case .onboardingCompleted: return "onboarding_completed"
            case .quickSoloTripStarted: return "quick_solo_trip_started"
            case .firstFindCompleted: return "first_find_completed"
            case .deferredSetupPromptShown: return "deferred_setup_prompt_shown"
            case .deferredSetupStepOpened: return "deferred_setup_step_opened"
            case .deferredSetupStepCompleted: return "deferred_setup_step_completed"
            case .deferredSetupStepTouched: return "deferred_setup_step_touched"
            case .authProfileHydrateFailed: return "auth_profile_hydrate_failed"
            case .screenView: return "screen_view"
            case .paywallViewed: return "paywall_viewed"
            case .paywallDismissed: return "paywall_dismissed"
            case .tripLimitHit: return "trip_limit_hit"
            case .savedTripLimitHit: return "saved_trip_limit_hit"
            case .purchaseStarted: return "purchase_started"
            case .purchaseCompleted: return "purchase_completed"
            case .purchaseFailed: return "purchase_failed"
            case .restoreStarted: return "restore_started"
            case .restoreCompleted: return "restore_completed"
            case .restoreFailed: return "restore_failed"
            case .riskAdvisoryDetected: return "risk_advisory_detected"
            case .discoveryOutcomeRecorded: return "discovery_outcome_recorded"
            case .discoveryRejectedDuplicate: return "discovery_rejected_duplicate"
            case .discoveryRejectedInvalidParticipant: return "discovery_rejected_invalid_participant"
            case .discoveryRemovalConfirmed: return "discovery_removal_confirmed"
            case .discoveryRetapBlockedByCooldown: return "discovery_retap_blocked_by_cooldown"
            case .discoveryUnfind: return "discovery_unfind"
            case .gameplayEventServerAccepted: return "gameplay_event_server_accepted"
            case .gameplayEventServerSuperseded: return "gameplay_event_server_superseded"
            case .gameplayEventServerRejected: return "gameplay_event_server_rejected"
            case .gameplayEventAppendTimedOut: return "gameplay_event_append_timed_out"
            case .persistenceSaveFailed: return "persistence_save_failed"
            case .persistenceRetryTapped: return "persistence_retry_tapped"
            }
        }
        
        var parameters: [String: Any]? {
            switch self {
            case .deepLinkOpened(let type, let params):
                var paramsDict: [String: Any] = ["type": type]
                for (key, value) in params {
                    paramsDict[key] = value
                }
                return paramsDict
            case .userSearchPerformed(let queryType):
                return ["query_type": queryType]
            case .friendsFamilySignUpGateShown(let feature):
                return ["feature": feature]
            case .shareCodeGenerated(let type), .shareCodeUsed(let type):
                return ["type": type]
            case .familyCreateFailed(let error):
                return ["error": error]
            case .familyJoinFailed(let error):
                return ["error": error]
            case .avatarPickerOpened(let source):
                return ["source": source]
            case .avatarSelected(let avatarId):
                return ["avatar_id": avatarId]
            case .avatarSaved(let avatarId, let source):
                return ["avatar_id": avatarId, "source": source]
            case .avatarLockedTapped(let avatarId, let unlockSource):
                return ["avatar_id": avatarId, "unlock_source": unlockSource]
            case .badgeProgress(let badgeId, let progress):
                return ["badge_id": badgeId, "progress": progress]
            case .badgeUnlocked(let badgeId), .badgeEquipped(let badgeId):
                return ["badge_id": badgeId]
            case .founderEntitlementGranted:
                return nil
            case .founderEntitlementGrantSkipped(let reason):
                return ["reason": reason]
            case .tripInvitesScreenOpened, .tripInviteAccepted, .tripInviteDeclined, .tripInviteCanceled:
                return nil
            case .tripInviteSent(let tripSessionId, let tripNameLength):
                return [
                    "invite_trip_id": tripSessionId,
                    "trip_name_length": tripNameLength,
                ]
            case .tripInviteSendFailed(let tripSessionId, let error):
                return [
                    "invite_trip_id": tripSessionId,
                    "error": error,
                ]
            case .tripInviteReceivedViewed(let inviteId):
                if let inviteId {
                    return ["invite_id": inviteId]
                }
                return nil
            case .tripParticipantsViewed(let tripSessionId):
                return ["trip_session_id": tripSessionId]
            case .tripInviteAcceptedWithContext(let inviteTripId, let inviteGameCount, let participantCountAfterJoin):
                var p: [String: Any] = [:]
                if let id = inviteTripId { p["invite_trip_id"] = id }
                if let c = inviteGameCount { p["invite_game_count"] = c }
                if let c = participantCountAfterJoin { p["participant_count_after_join"] = c }
                return p.isEmpty ? nil : p
            case .tripInviteDeclinedWithContext(let inviteTripId, let inviteGameCount):
                var p: [String: Any] = [:]
                if let id = inviteTripId { p["invite_trip_id"] = id }
                if let c = inviteGameCount { p["invite_game_count"] = c }
                return p.isEmpty ? nil : p
            case .participantJoinedTrip(let tripId, let participantCountAfterJoin, let teamCountAfterJoin):
                var p: [String: Any] = ["trip_session_id": tripId, "participant_count_after_join": participantCountAfterJoin]
                if let c = teamCountAfterJoin { p["team_count_after_join"] = c }
                return p
            case .participantLeftTrip(let tripId):
                return ["trip_session_id": tripId]
            case .tripParticipantLeaveInitiated(let tripSessionId, let offline):
                return ["trip_session_id": tripSessionId, "offline": offline]
            case .tripParticipantLeaveServerCompleted(let tripSessionId):
                return ["trip_session_id": tripSessionId]
            case .tripParticipantLeaveReconciled(let tripSessionId):
                return ["trip_session_id": tripSessionId]
            case .participantRemovedFromTrip(let tripId, let actorParticipantId):
                var p: [String: Any] = ["trip_session_id": tripId]
                if let id = actorParticipantId { p["actor_participant_id"] = id }
                return p
            case .combinedTripSetupOpened, .tripSetupOpened, .gameSetupOpened:
                return nil
            case .gameSetupAddGameOpened(let tripSessionId):
                return ["trip_session_id": tripSessionId]
            case .combinedTripCreated(let gameTypes, let tripSessionId, let participantCount, let gameCount, let gameModes, let hasTeams):
                var p: [String: Any] = ["game_types": gameTypes.joined(separator: ",")]
                if let id = tripSessionId { p["trip_session_id"] = id }
                if let count = participantCount { p["participant_count"] = count }
                if let count = gameCount { p["game_count"] = count }
                if let modes = gameModes, !modes.isEmpty { p["game_modes"] = modes.joined(separator: ",") }
                if let teams = hasTeams { p["has_teams"] = teams }
                return p
            case .combinedGameRemovedBeforeStart(let gameInstanceId, let combinedGameCount):
                return ["game_instance_id": gameInstanceId, "combined_game_count": combinedGameCount]
            case .combinedGameReordered(let combinedGameCount, let combinedGameTypes):
                return ["combined_game_count": combinedGameCount, "combined_game_types": combinedGameTypes.joined(separator: ",")]
            case .combinedGameDefaultRetained(let combinedPrimaryGameType):
                return ["combined_primary_game_type": combinedPrimaryGameType]
            case .combinedGameConfigChanged(let gameInstanceId, let settingKey, let oldValue, let newValue):
                return ["game_instance_id": gameInstanceId, "setting_key": settingKey, "old_value": oldValue, "new_value": newValue]
            case .combinedTripStartedWithGameCount(let tripId, let combinedGameCount, let combinedGameTypes):
                return ["trip_session_id": tripId, "combined_game_count": combinedGameCount, "combined_game_types": combinedGameTypes.joined(separator: ",")]
            case .tripSummaryViewed(let sessionId):
                return ["session_id": sessionId]
            case .tripSummaryAutoPresentedAfterEnd(let sessionId, let source):
                return ["session_id": sessionId, "source": source]
            case .tripEndedRemoteToastShown(let sessionId):
                return ["session_id": sessionId]
            case .tripSummaryViewedGameSection(let sessionId), .tripSummaryViewedParticipantSection(let sessionId), .tripSummaryViewedMapRecap(let sessionId), .tripSummaryViewedXpRecap(let sessionId):
                return ["session_id": sessionId]
            case .tripSummaryCompetitiveRankingsPresented(let tripSessionId):
                return ["trip_session_id": tripSessionId]
            case .competitiveInGameStandingsPresented(let tripSessionId, let gameInstanceId):
                return ["trip_session_id": tripSessionId, "game_instance_id": gameInstanceId]
            case .tripDashboardCompetitiveLeaderboardPresented(let tripSessionId):
                return ["trip_session_id": tripSessionId]
            case .travelLogFiltered(let filterKey, let filterValue):
                return ["filter_key": filterKey, "filter_value": filterValue]
            case .travelLogSorted(let sortKey):
                return ["sort_key": sortKey]
            case .lifetimeStatsRecomputeStarted:
                return nil
            case .lifetimeStatsRecomputeSucceeded(let completedTripCount, let familyOnlyTripCount):
                return [
                    "completed_trip_count": completedTripCount,
                    "family_only_trip_count": familyOnlyTripCount
                ]
            case .lifetimeStatsRecomputeFailed(let error):
                return ["error_type": error]
            case .lifetimeStatsProfileRetryTapped:
                return nil
            case .publicLifetimeStatsListenerUpdated(let userIdLength):
                return ["user_id_length": userIdLength]
            case .lifetimeStatsPendingSyncShown(let surface):
                return ["surface": surface]
            case .lifetimeStatsFallbackRecomputeUsed(let reason):
                return ["reason": reason]
            case .progressionSnapshotApplied(let totalXp, let acceptedRegionFindCount, let competitiveFirstPlaceFinishes):
                return [
                    "total_xp": totalXp,
                    "accepted_region_find_count": acceptedRegionFindCount,
                    "competitive_first_place_finishes": competitiveFirstPlaceFinishes
                ]
            case .progressionMilestoneEverCompetitiveFirstPlace:
                return nil
            case .progressionXpAwarded(let delta, let reason):
                return ["delta": delta, "reason": reason]
            case .progressionRewardsPresentationOverrideApplied(let visualBandSize, let xpPerRankLevel):
                return ["visual_band_size": visualBandSize, "xp_per_rank_level": xpPerRankLevel]
            case .progressionRewardsConfigFallback(let reason):
                return ["reason": reason]
            case .progressionCatalogPresentationOverrideApplied(let achievementsEnabled, let rankProgressionEnabled):
                return [
                    "achievements_enabled": achievementsEnabled,
                    "rank_progression_enabled": rankProgressionEnabled
                ]
            case .progressionCatalogConfigFallback(let reason):
                return ["reason": reason]
            case .achievementUnlocked(let achievementId, let category, let rarity):
                return [
                    "achievement_id": achievementId,
                    "category": category,
                    "rarity": rarity
                ]
            case .rankUpCelebrated(let level, let totalXp):
                return [
                    "rank_level": level,
                    "total_xp": totalXp
                ]
            case .achievementCelebrationDismissed(let eventId, let kind):
                return [
                    "event_id": eventId,
                    "kind": kind
                ]
            case .achievementUnlockSyncSucceeded(let recordedCount, let alreadySyncedCount, let rejectedCount):
                return [
                    "recorded_count": recordedCount,
                    "already_synced_count": alreadySyncedCount,
                    "rejected_count": rejectedCount
                ]
            case .achievementUnlockSyncFailed(let candidateCount, let errorSummary):
                return [
                    "candidate_count": candidateCount,
                    "error_summary": errorSummary
                ]
            case .xpGrantAwarded(let tripId, let gameInstanceId, let targetId, let participantId):
                return [
                    "trip_session_id": tripId,
                    "game_instance_id": gameInstanceId,
                    "target_id": targetId,
                    "participant_id": participantId
                ]
            case .xpGrantSkippedAlreadyGranted(let tripId, let gameInstanceId, let targetId, let participantId):
                return [
                    "trip_session_id": tripId,
                    "game_instance_id": gameInstanceId,
                    "target_id": targetId,
                    "participant_id": participantId
                ]
            case .xpGainToastPresented(let lineCount, let totalXp, let coalesced, let sourceMix, let groupIds):
                return [
                    "line_count": lineCount,
                    "total_xp": totalXp,
                    "coalesced": coalesced,
                    "source_mix": sourceMix,
                    "group_ids": groupIds
                ]
            case .xpGainToastDismissed(let reason):
                return ["reason": reason]
            case .travelLogOpened:
                return nil
            case .tripSessionCreated(let tripId, let tripStatus, let tripParticipantCount, let tripActiveGameCount, let tripSource):
                var p: [String: Any] = ["trip_session_id": tripId, "trip_status": tripStatus]
                if let c = tripParticipantCount { p["trip_participant_count"] = c }
                if let c = tripActiveGameCount { p["trip_active_game_count"] = c }
                if let s = tripSource { p["trip_source"] = s }
                return p
            case .tripSessionStarted(let tripId, let tripActiveGameCount):
                var p: [String: Any] = ["trip_session_id": tripId]
                if let c = tripActiveGameCount { p["trip_active_game_count"] = c }
                return p
            case .tripSessionEnded(let tripId):
                return ["trip_session_id": tripId]
            case .routeTrackingStarted(let tripId):
                return ["trip_session_id": tripId]
            case .routeTrackingStopped(let tripId):
                return ["trip_session_id": tripId]
            case .gameInstanceReset(let tripSessionId, let gameInstanceId):
                return ["trip_session_id": tripSessionId, "game_instance_id": gameInstanceId]
            case .gameInstanceDeleted(let tripSessionId, let gameInstanceId, let gameType, let remainingGameCount):
                return [
                    "trip_session_id": tripSessionId,
                    "game_instance_id": gameInstanceId,
                    "game_type": gameType,
                    "remaining_game_count": remainingGameCount
                ]
            case .tripSessionCancelled(let tripId), .tripSessionDeleted(let tripId):
                return ["trip_session_id": tripId]
            case .gameInstanceCreated(let gameInstanceId, let gameType, let gameMode, let tripId, let gameOrderInTrip):
                var p: [String: Any] = ["game_instance_id": gameInstanceId, "game_type": gameType, "game_mode": gameMode, "trip_session_id": tripId]
                if let o = gameOrderInTrip { p["game_order_in_trip"] = o }
                return p
            case .gameInstanceStarted(let gameInstanceId, let gameType, let gameLifecycleState, let configLockReason, let tripSessionId):
                return ["game_instance_id": gameInstanceId, "game_type": gameType, "game_lifecycle_state": gameLifecycleState, "config_lock_reason": configLockReason, "trip_session_id": tripSessionId]
            case .gameInstanceEnded(let gameInstanceId, let gameType, let tripSessionId):
                return ["game_instance_id": gameInstanceId, "game_type": gameType, "trip_session_id": tripSessionId]
            case .gameInstanceCompleted(let gameInstanceId, let gameType, let tripSessionId):
                return ["game_instance_id": gameInstanceId, "game_type": gameType, "trip_session_id": tripSessionId]
            case .gameConfigLocked(let gameInstanceId, let configLockReason), .gameConfigLockBlockedEdit(let gameInstanceId, let configLockReason):
                return ["game_instance_id": gameInstanceId, "config_lock_reason": configLockReason]
            case .gameConfigViewed(let gameInstanceId, let configLocked, let configLockReason):
                return ["game_instance_id": gameInstanceId, "config_locked": configLocked, "config_lock_reason": configLockReason]
            case .gameConfigChanged(let gameInstanceId, let settingKey, let oldValue, let newValue, let changeSurface):
                var p: [String: Any] = ["game_instance_id": gameInstanceId, "setting_key": settingKey, "old_value": oldValue, "new_value": newValue]
                if let s = changeSurface { p["change_surface"] = s }
                return p
            case .gameConfigChangeFailed(let gameInstanceId, let settingKey, let error):
                return ["game_instance_id": gameInstanceId, "setting_key": settingKey, "error": error]
            case .gameConfigUnlockAttempted(let gameInstanceId, let configLockReason):
                return ["game_instance_id": gameInstanceId, "config_lock_reason": configLockReason]
            case .gameConfigEventOverrideApplied(let gameInstanceId, let lockReason, let editPolicy):
                return ["game_instance_id": gameInstanceId, "lock_reason": lockReason, "edit_policy": editPolicy]
            case .gameConfigPayloadDecodeFailed(let gameInstanceId, let error):
                var p: [String: Any] = ["error": error]
                if let id = gameInstanceId { p["game_instance_id"] = id }
                return p
            case .creditResolutionFailed(let discoveryId, let error):
                return ["discovery_id": discoveryId, "error": error]
            case .summaryProjectionMismatch(let sessionId, let error):
                return ["session_id": sessionId, "error": error]
            case .unsupportedGamePayloadVersion(let payloadType, let payloadVersion):
                return ["game_payload_type": payloadType, "game_payload_version": payloadVersion]
            case .analyticsPropertyBuildFailed(let eventName, let error):
                return ["event_name": eventName, "error": error]
            case .riskAdvisoryDetected(let flags, let tripId):
                return ["risk_flags": flags.joined(separator: ","), "trip_session_id": tripId]
            case .discoveryOutcomeRecorded(let tripId, let gameInstanceId, let targetId, let outcome, let participantId):
                var p: [String: Any] = ["trip_session_id": tripId, "game_instance_id": gameInstanceId, "target_id": targetId, "outcome": outcome]
                if let id = participantId { p["participant_id"] = id }
                return p
            case .discoveryRejectedDuplicate(let tripId, let gameInstanceId, let targetId, let participantId, let mode):
                var p: [String: Any] = ["trip_session_id": tripId, "game_instance_id": gameInstanceId, "target_id": targetId, "mode": mode]
                if let id = participantId { p["participant_id"] = id }
                return p
            case .discoveryRejectedInvalidParticipant(let tripId, let gameInstanceId, let targetId, let participantId, let tripParticipantCount, let gameMode):
                var p: [String: Any] = [
                    "trip_session_id": tripId,
                    "game_instance_id": gameInstanceId,
                    "target_id": targetId,
                    "trip_participant_count": tripParticipantCount,
                    "game_mode": gameMode
                ]
                if let id = participantId { p["participant_id"] = id }
                return p
            case .discoveryRemovalConfirmed(let tripId, let gameInstanceId, let targetId, let participantId):
                var p: [String: Any] = ["trip_session_id": tripId, "game_instance_id": gameInstanceId, "target_id": targetId]
                if let id = participantId { p["participant_id"] = id }
                return p
            case .discoveryRetapBlockedByCooldown(let tripId, let gameInstanceId, let targetId):
                return ["trip_session_id": tripId, "game_instance_id": gameInstanceId, "target_id": targetId]
            case .discoveryUnfind(let tripId, let gameInstanceId, let targetId, let participantId):
                var p: [String: Any] = ["trip_session_id": tripId, "game_instance_id": gameInstanceId, "target_id": targetId]
                if let id = participantId { p["participant_id"] = id }
                return p
            case .gameplayEventServerAccepted(let tripSessionId, let gameInstanceId, let eventKind):
                return [
                    "trip_session_id": tripSessionId,
                    "game_instance_id": gameInstanceId,
                    "event_kind": eventKind
                ]
            case .gameplayEventServerSuperseded(let tripSessionId, let gameInstanceId, let serverRejectionEventId, let reason):
                return [
                    "trip_session_id": tripSessionId,
                    "game_instance_id": gameInstanceId,
                    "server_rejection_event_id": serverRejectionEventId,
                    "reason": reason
                ]
            case .gameplayEventServerRejected(let tripSessionId, let eventKind, let errorCode, let errorDomain):
                return [
                    "trip_session_id": tripSessionId,
                    "event_kind": eventKind,
                    "error_code": errorCode,
                    "error_domain": errorDomain
                ]
            case .gameplayEventAppendTimedOut(let tripSessionId, let gameInstanceId, let eventKind, let attemptCount, let timeoutSeconds):
                return [
                    "trip_session_id": tripSessionId,
                    "game_instance_id": gameInstanceId,
                    "event_kind": eventKind,
                    "attempt_count": attemptCount,
                    "timeout_seconds": timeoutSeconds
                ]
            case .persistenceSaveFailed(let context, let error):
                return ["context": context, "error": error]
            case .persistenceRetryTapped(let context):
                return ["context": context]
            case .notificationEligibilityChecked(let kind, let eligible):
                return ["kind": kind, "eligible": eligible]
            case .notificationDeliveredTripInvite,
                 .notificationDeliveredFriendInvite,
                 .notificationDeliveredFamilyInvite:
                return nil
            case .notificationDeliveryFailed(let error):
                return ["error": error]
            case .remoteConfigFetchSucceeded:
                return nil
            case .remoteConfigFetchFailed(let error):
                return ["error": error]
            case .crashReportingConfigured:
                return nil
            case .crashReportingNonFatalRecorded(let context):
                return ["context": context]
            case .adEligibilityEvaluated(let surface, let eligible, let reason):
                return ["surface": surface, "eligible": eligible, "reason": reason]
            case .adImpression(let surface):
                return ["surface": surface]
            case .adLoadFailed(let surface, let error):
                return ["surface": surface, "error": error]
            case .reviewPromptEligible(let completedTripCount):
                return ["completed_trip_count": completedTripCount]
            case .reviewPromptPresented(let sessionId):
                return ["session_id": sessionId]
            case .reviewPromptSuppressed(let reason, let completedTripCount):
                return ["reason": reason, "completed_trip_count": completedTripCount]
            case .reminderScheduled(let sessionId, let hours):
                return ["session_id": sessionId, "hours": hours]
            case .reminderCancelled(let sessionId, let reason):
                return ["session_id": sessionId, "reason": reason]
            case .returnStreakUpdated(let currentStreak, let reason):
                return ["current_streak": currentStreak, "reason": reason]
            case .returnStreakReset(let reason):
                return ["reason": reason]
            case .returnStreakQualified(let currentStreak, let reason):
                return ["current_streak": currentStreak, "reason": reason]
            case .returnStreakBroken(let previousStreak):
                return ["previous_streak": previousStreak]
            case .returnStreakDisplayed(let currentStreak, let surface):
                return ["current_streak": currentStreak, "surface": surface]
            case .returnStreakExplanationOpened(let currentStreak):
                return ["current_streak": currentStreak]
            case .returnStreakCelebrationShown(let currentStreak):
                return ["current_streak": currentStreak]
            case .returnStreakReminderScheduled(let hour):
                return ["hour": hour]
            case .returnStreakReminderOpened(let currentStreak):
                return ["current_streak": currentStreak]
            case .fcmTokenRegistered:
                return nil
            case .onboardingStarted(let flowVariant, let offline):
                return ["flow_variant": flowVariant, "offline": offline]
            case .onboardingStepViewed(let stepId, let stepIndex, let flowVariant):
                return ["step_id": stepId, "step_index": stepIndex, "flow_variant": flowVariant]
            case .onboardingAbandoned(let lastStepId, let flowVariant, let elapsedMs):
                return ["last_step_id": lastStepId, "flow_variant": flowVariant, "elapsed_ms": elapsedMs]
            case .onboardingCompleted(let flowVariant, let elapsedMs, let offline):
                return ["flow_variant": flowVariant, "elapsed_ms": elapsedMs, "offline": offline]
            case .quickSoloTripStarted(let tripSessionId, let gameInstanceId, let offline, let elapsedMs):
                return [
                    "trip_session_id": tripSessionId,
                    "game_instance_id": gameInstanceId,
                    "offline": offline,
                    "elapsed_ms": elapsedMs
                ]
            case .firstFindCompleted(let tripSessionId, let gameInstanceId, let targetId, let elapsedMs, let inputMethod):
                return [
                    "trip_session_id": tripSessionId,
                    "game_instance_id": gameInstanceId,
                    "target_id": targetId,
                    "elapsed_ms": elapsedMs,
                    "input_method": inputMethod
                ]
            case .deferredSetupPromptShown(let pendingSteps):
                return ["pending_steps": pendingSteps]
            case .deferredSetupStepOpened(let stepId, let source):
                return ["step_id": stepId, "source": source]
            case .deferredSetupStepCompleted(let stepId):
                return ["step_id": stepId]
            case .deferredSetupStepTouched(let stepId, let source):
                return ["step_id": stepId, "source": source]
            case .authProfileHydrateFailed(let outcome):
                return ["outcome": outcome]
            case .screenView(let screenName, let screenClass):
                var p: [String: Any] = ["screen_name": screenName]
                if let screenClass = screenClass { p["screen_class"] = screenClass }
                return p
            case .paywallViewed(let source):
                if let source = source { return ["source": source] }
                return nil
            case .paywallDismissed:
                return nil
            case .tripLimitHit(let source, let activeTripCount, let activeTripLimit, let tier):
                return [
                    "source": source,
                    "active_trip_count": activeTripCount,
                    "active_trip_limit": activeTripLimit,
                    "tier": tier
                ]
            case .savedTripLimitHit(let source, let savedTripCount, let savedTripLimit, let tier):
                return [
                    "source": source,
                    "saved_trip_count": savedTripCount,
                    "saved_trip_limit": savedTripLimit,
                    "tier": tier
                ]
            case .purchaseStarted(let packageId):
                return ["package_id": packageId]
            case .purchaseCompleted(let packageId):
                return ["package_id": packageId]
            case .purchaseFailed(let packageId, let error):
                var p: [String: Any] = ["error": error]
                if let id = packageId { p["package_id"] = id }
                return p
            case .restoreStarted:
                return nil
            case .restoreCompleted:
                return nil
            case .restoreFailed(let error):
                return ["error": error]
            default:
                return nil
            }
        }
    }
    
    // MARK: - Logging
    
    /// Log an analytics event
    func log(_ event: Event) {
        let parameters = event.parameters ?? [:]
        Analytics.logEvent(event.name, parameters: parameters)
        #if DEBUG
        Self.debugPrintEvent(event.name, parameters: parameters)
        #endif
    }

    /// Log with custom parameters
    func log(_ eventName: String, parameters: [String: Any] = [:]) {
        Analytics.logEvent(eventName, parameters: parameters)
        #if DEBUG
        Self.debugPrintEvent(eventName, parameters: parameters)
        #endif
    }

    #if DEBUG
    private static func debugPrintEvent(_ name: String, parameters: [String: Any]) {
        let paramStr = parameters.isEmpty ? "" : " " + parameters.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
        print("[Analytics] \(name)\(paramStr)")
    }
    #endif

    // MARK: - Screen view & user properties (Step 10)

    /// Log a screen view for key screens. Use snake_case screen names (e.g. "travel_log", "pending_trips").
    func logScreenView(screenName: String, screenClass: String? = nil) {
        log(.screenView(screenName: screenName, screenClass: screenClass))
    }

    /// Set a Firebase user property for segmentation. Names should be snake_case (e.g. "trip_mode", "has_family").
    func setUserProperty(_ value: String?, forName name: String) {
        Analytics.setUserProperty(value, forName: name)
        #if DEBUG
        print("[Analytics] set_user_property: name=\(name), value=\(value ?? "nil")")
        #endif
    }
}


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

        // Trip invites (Step 04)
        case tripInvitesScreenOpened
        case tripInviteAccepted
        case tripInviteDeclined
        case tripInviteCanceled

        // Trip invite with context (Step 10.5)
        case tripInviteAcceptedWithContext(inviteTripId: String?, inviteGameCount: Int?, participantCountAfterJoin: Int?)
        case tripInviteDeclinedWithContext(inviteTripId: String?, inviteGameCount: Int?)
        case participantJoinedTrip(tripId: String, participantCountAfterJoin: Int, teamCountAfterJoin: Int?)
        case participantLeftTrip(tripId: String)
        case participantRemovedFromTrip(tripId: String, actorParticipantId: String?)

        // Combined games (Step 06)
        case combinedTripSetupOpened
        case combinedTripCreated(gameTypes: [String])

        // Combined games extended (Step 10.5)
        case combinedGameRemovedBeforeStart(gameInstanceId: String, combinedGameCount: Int)
        case combinedGameReordered(combinedGameCount: Int, combinedGameTypes: [String])
        case combinedGameDefaultRetained(combinedPrimaryGameType: String)
        case combinedGameConfigChanged(gameInstanceId: String, settingKey: String, oldValue: String, newValue: String)
        case combinedTripStartedWithGameCount(tripId: String, combinedGameCount: Int, combinedGameTypes: [String])

        // Travel Log (Step 07)
        case travelLogOpened
        case tripSummaryViewed(sessionId: String)

        // Summary / Travel log extended (Step 10.5)
        case tripSummaryViewedGameSection(sessionId: String)
        case tripSummaryViewedParticipantSection(sessionId: String)
        case tripSummaryViewedMapRecap(sessionId: String)
        case travelLogFiltered(filterKey: String, filterValue: String)
        case travelLogSorted(sortKey: String)

        // Lifecycle (Step 10.5)
        case tripSessionCreated(tripId: String, tripStatus: String, tripParticipantCount: Int?, tripActiveGameCount: Int?, tripSource: String?)
        case tripSessionStarted(tripId: String, tripActiveGameCount: Int?)
        case tripSessionEnded(tripId: String)
        case tripSessionCompleted(tripId: String)
        case gameInstanceCreated(gameInstanceId: String, gameType: String, gameMode: String, tripId: String, gameOrderInTrip: Int?)
        case gameInstanceStarted(gameInstanceId: String, gameType: String, gameLifecycleState: String, configLockReason: String)
        case gameInstanceEnded(gameInstanceId: String, gameType: String)
        case gameInstanceCompleted(gameInstanceId: String, gameType: String)
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
        case legacyTripAdapterUsed(legacyTripId: String, sessionId: String?)
        case legacyTripAdapterFailed(error: String)
        case unsupportedGamePayloadVersion(payloadType: String, payloadVersion: String)
        case analyticsPropertyBuildFailed(eventName: String, error: String)

        // Risk advisory (Step 11)
        case riskAdvisoryDetected(flags: [String], tripId: String)

        // Notifications & eligibility (Step 08)
        case notificationEligibilityChecked(kind: String, eligible: Bool)
        case notificationDeliveredTripInvite
        case notificationDeliveryFailed(error: String)

        // Screen view (Step 10)
        case screenView(screenName: String, screenClass: String?)

        // Paywall & RevenueCat (Step 09)
        case paywallViewed(source: String?)
        case paywallDismissed
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
            case .tripInvitesScreenOpened: return "trip_invites_screen_opened"
            case .tripInviteAccepted: return "trip_invite_accepted"
            case .tripInviteDeclined: return "trip_invite_declined"
            case .tripInviteCanceled: return "trip_invite_canceled"
            case .tripInviteAcceptedWithContext: return "trip_invite_accepted"
            case .tripInviteDeclinedWithContext: return "trip_invite_declined"
            case .participantJoinedTrip: return "participant_joined_trip"
            case .participantLeftTrip: return "participant_left_trip"
            case .participantRemovedFromTrip: return "participant_removed_from_trip"
            case .combinedTripSetupOpened: return "combined_trip_setup_opened"
            case .combinedTripCreated: return "combined_trip_created"
            case .combinedGameRemovedBeforeStart: return "combined_game_removed_before_start"
            case .combinedGameReordered: return "combined_game_reordered"
            case .combinedGameDefaultRetained: return "combined_game_default_retained"
            case .combinedGameConfigChanged: return "combined_game_config_changed"
            case .combinedTripStartedWithGameCount: return "combined_trip_started_with_game_count"
            case .travelLogOpened: return "travel_log_opened"
            case .tripSummaryViewed: return "trip_summary_viewed"
            case .tripSummaryViewedGameSection: return "trip_summary_viewed_game_section"
            case .tripSummaryViewedParticipantSection: return "trip_summary_viewed_participant_section"
            case .tripSummaryViewedMapRecap: return "trip_summary_viewed_map_recap"
            case .travelLogFiltered: return "travel_log_filtered"
            case .travelLogSorted: return "travel_log_sorted"
            case .tripSessionCreated: return "trip_session_created"
            case .tripSessionStarted: return "trip_session_started"
            case .tripSessionEnded: return "trip_session_ended"
            case .tripSessionCompleted: return "trip_session_completed"
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
            case .legacyTripAdapterUsed: return "legacy_trip_adapter_used"
            case .legacyTripAdapterFailed: return "legacy_trip_adapter_failed"
            case .unsupportedGamePayloadVersion: return "unsupported_game_payload_version"
            case .analyticsPropertyBuildFailed: return "analytics_property_build_failed"
            case .notificationEligibilityChecked: return "notification_eligibility_checked"
            case .notificationDeliveredTripInvite: return "notification_delivered_trip_invite"
            case .notificationDeliveryFailed: return "notification_delivery_failed"
            case .screenView: return "screen_view"
            case .paywallViewed: return "paywall_viewed"
            case .paywallDismissed: return "paywall_dismissed"
            case .purchaseStarted: return "purchase_started"
            case .purchaseCompleted: return "purchase_completed"
            case .purchaseFailed: return "purchase_failed"
            case .restoreStarted: return "restore_started"
            case .restoreCompleted: return "restore_completed"
            case .restoreFailed: return "restore_failed"
            case .riskAdvisoryDetected: return "risk_advisory_detected"
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
            case .tripInvitesScreenOpened, .tripInviteAccepted, .tripInviteDeclined, .tripInviteCanceled:
                return nil
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
                var p: [String: Any] = ["trip_id": tripId, "participant_count_after_join": participantCountAfterJoin]
                if let c = teamCountAfterJoin { p["team_count_after_join"] = c }
                return p
            case .participantLeftTrip(let tripId):
                return ["trip_id": tripId]
            case .participantRemovedFromTrip(let tripId, let actorParticipantId):
                var p: [String: Any] = ["trip_id": tripId]
                if let id = actorParticipantId { p["actor_participant_id"] = id }
                return p
            case .combinedTripSetupOpened:
                return nil
            case .combinedTripCreated(let gameTypes):
                return ["game_types": gameTypes.joined(separator: ",")]
            case .combinedGameRemovedBeforeStart(let gameInstanceId, let combinedGameCount):
                return ["game_instance_id": gameInstanceId, "combined_game_count": combinedGameCount]
            case .combinedGameReordered(let combinedGameCount, let combinedGameTypes):
                return ["combined_game_count": combinedGameCount, "combined_game_types": combinedGameTypes.joined(separator: ",")]
            case .combinedGameDefaultRetained(let combinedPrimaryGameType):
                return ["combined_primary_game_type": combinedPrimaryGameType]
            case .combinedGameConfigChanged(let gameInstanceId, let settingKey, let oldValue, let newValue):
                return ["game_instance_id": gameInstanceId, "setting_key": settingKey, "old_value": oldValue, "new_value": newValue]
            case .combinedTripStartedWithGameCount(let tripId, let combinedGameCount, let combinedGameTypes):
                return ["trip_id": tripId, "combined_game_count": combinedGameCount, "combined_game_types": combinedGameTypes.joined(separator: ",")]
            case .tripSummaryViewed(let sessionId):
                return ["session_id": sessionId]
            case .tripSummaryViewedGameSection(let sessionId), .tripSummaryViewedParticipantSection(let sessionId), .tripSummaryViewedMapRecap(let sessionId):
                return ["session_id": sessionId]
            case .travelLogFiltered(let filterKey, let filterValue):
                return ["filter_key": filterKey, "filter_value": filterValue]
            case .travelLogSorted(let sortKey):
                return ["sort_key": sortKey]
            case .travelLogOpened:
                return nil
            case .tripSessionCreated(let tripId, let tripStatus, let tripParticipantCount, let tripActiveGameCount, let tripSource):
                var p: [String: Any] = ["trip_id": tripId, "trip_status": tripStatus]
                if let c = tripParticipantCount { p["trip_participant_count"] = c }
                if let c = tripActiveGameCount { p["trip_active_game_count"] = c }
                if let s = tripSource { p["trip_source"] = s }
                return p
            case .tripSessionStarted(let tripId, let tripActiveGameCount):
                var p: [String: Any] = ["trip_id": tripId]
                if let c = tripActiveGameCount { p["trip_active_game_count"] = c }
                return p
            case .tripSessionEnded(let tripId), .tripSessionCompleted(let tripId):
                return ["trip_id": tripId]
            case .gameInstanceCreated(let gameInstanceId, let gameType, let gameMode, let tripId, let gameOrderInTrip):
                var p: [String: Any] = ["game_instance_id": gameInstanceId, "game_type": gameType, "game_mode": gameMode, "trip_id": tripId]
                if let o = gameOrderInTrip { p["game_order_in_trip"] = o }
                return p
            case .gameInstanceStarted(let gameInstanceId, let gameType, let gameLifecycleState, let configLockReason):
                return ["game_instance_id": gameInstanceId, "game_type": gameType, "game_lifecycle_state": gameLifecycleState, "config_lock_reason": configLockReason]
            case .gameInstanceEnded(let gameInstanceId, let gameType), .gameInstanceCompleted(let gameInstanceId, let gameType):
                return ["game_instance_id": gameInstanceId, "game_type": gameType]
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
            case .legacyTripAdapterUsed(let legacyTripId, let sessionId):
                var p: [String: Any] = ["legacy_trip_id": legacyTripId]
                if let id = sessionId { p["session_id"] = id }
                return p
            case .legacyTripAdapterFailed(let error):
                return ["error": error]
            case .unsupportedGamePayloadVersion(let payloadType, let payloadVersion):
                return ["game_payload_type": payloadType, "game_payload_version": payloadVersion]
            case .analyticsPropertyBuildFailed(let eventName, let error):
                return ["event_name": eventName, "error": error]
            case .riskAdvisoryDetected(let flags, let tripId):
                return ["risk_flags": flags.joined(separator: ","), "trip_id": tripId]
            case .notificationEligibilityChecked(let kind, let eligible):
                return ["kind": kind, "eligible": eligible]
            case .notificationDeliveredTripInvite:
                return nil
            case .notificationDeliveryFailed(let error):
                return ["error": error]
            case .screenView(let screenName, let screenClass):
                var p: [String: Any] = ["screen_name": screenName]
                if let screenClass = screenClass { p["screen_class"] = screenClass }
                return p
            case .paywallViewed(let source):
                if let source = source { return ["source": source] }
                return nil
            case .paywallDismissed:
                return nil
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
    }
    
    /// Log with custom parameters
    func log(_ eventName: String, parameters: [String: Any] = [:]) {
        Analytics.logEvent(eventName, parameters: parameters)
    }

    // MARK: - Screen view & user properties (Step 10)

    /// Log a screen view for key screens. Use snake_case screen names (e.g. "travel_log", "pending_trips").
    func logScreenView(screenName: String, screenClass: String? = nil) {
        log(.screenView(screenName: screenName, screenClass: screenClass))
    }

    /// Set a Firebase user property for segmentation. Names should be snake_case (e.g. "trip_mode", "has_family").
    func setUserProperty(_ value: String?, forName name: String) {
        Analytics.setUserProperty(value, forName: name)
    }
}


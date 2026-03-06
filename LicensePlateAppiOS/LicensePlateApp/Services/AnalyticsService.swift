//
//  AnalyticsService.swift
//  LicensePlateApp
//
//  Created for Friends & Family MVP
//

import Foundation
import FirebaseAnalytics
import Firebase

@MainActor
class AnalyticsService {
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
                return ["queryType": queryType]
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
}


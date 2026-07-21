//
//  AuthProfileSyncPolicy.swift
//  LicensePlateApp
//
//  Pure rules for auth session restore: hydrate-before-login-track (A),
//  login-timestamp-only cloud writes (B), and create-only-when-absent (D).
//  Contact null-safety (C) lives in ContactSearchNormalization.privateContactMergeFields.
//

import Foundation

enum AuthProfileSyncPolicy {

    /// Result of reading `users/{uid}` (distinct from thrown transport errors).
    enum DocumentLoadStatus: Equatable {
        case found
        case notFound
        case failed
    }

    /// Next step after Auth resolves a UID. Encodes hydrate-before-track ordering.
    enum BootstrapAction: Equatable {
        /// Local row exists; apply cloud profile, then login-track.
        case applyCloudThenTrackLogin
        /// No local row; insert cloud profile, then login-track.
        case insertCloudThenTrackLogin
        /// No local row and cloud doc confirmed absent; create local + save, then login-track.
        case createLocalThenTrackLogin
        /// Local row exists but cloud read failed; keep local, then login-track (timestamps only).
        case keepLocalThenTrackLogin
        /// No local row and cloud read failed; do not invent a guest profile or full-save.
        case abortWithoutCreate
    }

    /// Fields allowed on the login-tracking Firestore write (B). Identity/contact must never appear here.
    static let loginTimestampFieldKeys: Set<String> = [
        "lastDateLoggedIn",
        "lastUpdated",
    ]

    static func bootstrapAction(
        hasLocalUser: Bool,
        load: DocumentLoadStatus
    ) -> BootstrapAction {
        if hasLocalUser {
            switch load {
            case .found:
                return .applyCloudThenTrackLogin
            case .notFound, .failed:
                // Missing cloud doc with a local row: keep local (do not recreate).
                // Failed read: keep local; never overwrite cloud with a guessed guest profile.
                return .keepLocalThenTrackLogin
            }
        } else {
            switch load {
            case .found:
                return .insertCloudThenTrackLogin
            case .notFound:
                return .createLocalThenTrackLogin
            case .failed:
                return .abortWithoutCreate
            }
        }
    }

    /// Applies cloud identity onto local SwiftData (session restore / hydrate).
    static func applyCloudProfile(
        _ cloud: AppUser,
        to local: AppUser,
        isAnonymous: Bool,
        syncedAt: Date = .now
    ) {
        local.userName = cloud.userName
        local.firstName = cloud.firstName
        local.lastName = cloud.lastName
        if !isAnonymous {
            local.email = cloud.email
        }
        local.phoneNumber = cloud.phoneNumber
        local.userImageURL = cloud.userImageURL
        local.linkedPlatforms = cloud.linkedPlatforms
        local.avatarId = cloud.avatarId
        local.equippedBadgeId = cloud.equippedBadgeId
        local.wasEverInFamily = cloud.wasEverInFamily
        local.activeFamilyId = cloud.activeFamilyId
        local.friendCount = cloud.friendCount
        local.isRetiredGeneral = cloud.isRetiredGeneral
        local.isUsernameManuallyChanged = cloud.isUsernameManuallyChanged
        local.isEmailPublic = cloud.isEmailPublic
        local.isPhonePublic = cloud.isPhonePublic
        local.lastSyncedToFirebase = syncedAt
        local.needsSync = false
    }
}

//
//  SchemaVersions.swift
//  LicensePlateApp
//
//  Pre-release: V1 baseline frozen; V2 adds AppUser.equippedLicenseCosmeticId.
//

import Foundation
import SwiftData

// MARK: - Schema Version 1 (Frozen pre-release baseline)

enum SchemaVersion1: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(1, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [
            SchemaVersion1.AppUser.self,
            Friendship.self,
            Invite.self,
            Family.self,
            FamilyMember.self,
            PendingJoinRequest.self,
            ShareCode.self,
            TripSessionEntity.self,
            GameInstanceEntity.self,
            GameScoreSnapshotEntity.self,
            TripInvite.self,
            TripActivityEventEntity.self,
            SyncQueueItemEntity.self,
            RemoteSyncMetadataEntity.self,
            PendingTripLeaveEntity.self,
            UserLifetimeStatsEntity.self,
            PublicLifetimeStatsCacheEntity.self,
            XpLedgerEventEntity.self,
            DiscoveryResolutionEntity.self,
            UserAchievementEntity.self,
            TripRoutePointEntity.self
        ]
    }

    /// Frozen V1 user row (no `equippedLicenseCosmeticId`). Keeps the V1 fingerprint stable.
    @Model
    final class AppUser {
        @Attribute(.unique) var id: String
        var userName: String
        var firstName: String?
        var lastName: String?
        var email: String?
        var phoneNumber: String?
        var createdAt: Date
        var lastUpdated: Date
        var userImageURL: String?
        var deviceIdentifier: String?
        var isUsernameManuallyChanged: Bool = false
        var isEmailPublic: Bool = false
        var isPhonePublic: Bool = false
        var avatarId: String?
        var equippedBadgeId: String?
        var wasEverInFamily: Bool = false
        var isRetiredGeneral: Bool = false
        var activeFamilyId: String?
        var friendCount: Int = 0
        var linkedPlatforms: [LinkedPlatform]
        var firebaseUID: String?
        var lastSyncedToFirebase: Date?
        var needsSync: Bool = false
        var localIDBeforeFirebase: String?
        var lastDateLoggedIn: Date?
        var lastLoginLocation: [LoginLocation]

        init(
            id: String = UUID().uuidString,
            userName: String = "User",
            firstName: String? = nil,
            lastName: String? = nil,
            email: String? = nil,
            phoneNumber: String? = nil,
            createdAt: Date = .now,
            lastUpdated: Date = .now,
            userImageURL: String? = nil,
            deviceIdentifier: String? = nil,
            isUsernameManuallyChanged: Bool = false,
            isEmailPublic: Bool = false,
            isPhonePublic: Bool = false,
            avatarId: String? = nil,
            equippedBadgeId: String? = nil,
            wasEverInFamily: Bool = false,
            isRetiredGeneral: Bool = false,
            activeFamilyId: String? = nil,
            friendCount: Int = 0,
            linkedPlatforms: [LinkedPlatform] = [],
            firebaseUID: String? = nil,
            lastSyncedToFirebase: Date? = nil,
            needsSync: Bool = false,
            localIDBeforeFirebase: String? = nil,
            lastDateLoggedIn: Date? = nil,
            lastLoginLocation: [LoginLocation] = []
        ) {
            self.id = id
            self.userName = userName
            self.firstName = firstName
            self.lastName = lastName
            self.email = email
            self.phoneNumber = phoneNumber
            self.createdAt = createdAt
            self.lastUpdated = lastUpdated
            self.userImageURL = userImageURL
            self.deviceIdentifier = deviceIdentifier
            self.isUsernameManuallyChanged = isUsernameManuallyChanged
            self.isEmailPublic = isEmailPublic
            self.isPhonePublic = isPhonePublic
            self.avatarId = avatarId
            self.equippedBadgeId = equippedBadgeId
            self.wasEverInFamily = wasEverInFamily
            self.isRetiredGeneral = isRetiredGeneral
            self.activeFamilyId = activeFamilyId
            self.friendCount = friendCount
            self.linkedPlatforms = linkedPlatforms
            self.firebaseUID = firebaseUID
            self.lastSyncedToFirebase = lastSyncedToFirebase
            self.needsSync = needsSync
            self.localIDBeforeFirebase = localIDBeforeFirebase
            self.lastDateLoggedIn = lastDateLoggedIn
            self.lastLoginLocation = lastLoginLocation
        }
    }
}

// MARK: - Schema Version 2 (equippedLicenseCosmeticId on AppUser)

enum SchemaVersion2: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(2, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [
            AppUser.self,
            Friendship.self,
            Invite.self,
            Family.self,
            FamilyMember.self,
            PendingJoinRequest.self,
            ShareCode.self,
            TripSessionEntity.self,
            GameInstanceEntity.self,
            GameScoreSnapshotEntity.self,
            TripInvite.self,
            TripActivityEventEntity.self,
            SyncQueueItemEntity.self,
            RemoteSyncMetadataEntity.self,
            PendingTripLeaveEntity.self,
            UserLifetimeStatsEntity.self,
            PublicLifetimeStatsCacheEntity.self,
            XpLedgerEventEntity.self,
            DiscoveryResolutionEntity.self,
            UserAchievementEntity.self,
            TripRoutePointEntity.self
        ]
    }
}

// MARK: - Migration Plan

enum AppMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaVersion1.self, SchemaVersion2.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: SchemaVersion1.self, toVersion: SchemaVersion2.self)
        ]
    }
}

// MARK: - Current Schema

typealias CurrentSchema = SchemaVersion2

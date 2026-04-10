//
//  SchemaVersions.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//

import Foundation
import SwiftData

// MARK: - Schema-version markers
// Exist solely so each version has a distinct model set, avoiding "Duplicate version checksums detected".
// Do not use in app logic.
@Model
final class SchemaVersion3Marker {
    var createdAt: Date = Date()
    init() {}
}

@Model
final class SchemaVersion4Marker {
    var createdAt: Date = Date()
    init() {}
}

@Model
final class SchemaVersion5Marker {
    var createdAt: Date = Date()
    init() {}
}

@Model
final class SchemaVersion6Marker {
    var createdAt: Date = Date()
    init() {}
}

@Model
final class SchemaVersion7Marker {
    var createdAt: Date = Date()
    init() {}
}

@Model
final class SchemaVersion8Marker {
    var createdAt: Date = Date()
    init() {}
}

@Model
final class SchemaVersion9Marker {
    var createdAt: Date = Date()
    init() {}
}

@Model
final class SchemaVersion10Marker {
    var createdAt: Date = Date()
    init() {}
}

@Model
final class SchemaVersion11Marker {
    var createdAt: Date = Date()
    init() {}
}

@Model
final class SchemaVersion12Marker {
    var createdAt: Date = Date()
    init() {}
}

@Model
final class SchemaVersion13Marker {
    var createdAt: Date = Date()
    init() {}
}

@Model
final class SchemaVersion14Marker {
    var createdAt: Date = Date()
    init() {}
}

@Model
final class SchemaVersion15Marker {
    var createdAt: Date = Date()
    init() {}
}

@Model
final class SchemaVersion16Marker {
    var createdAt: Date = Date()
    init() {}
}

@Model
final class SchemaVersion17Marker {
    var createdAt: Date = Date()
    init() {}
}

@Model
final class SchemaVersion18Marker {
    var createdAt: Date = Date()
    init() {}
}

// MARK: - Schema Version 1 (Initial)
// Initial schema with Trip and AppUser

enum SchemaVersion1: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(1, 0, 0)
    }
    
    static var models: [any PersistentModel.Type] {
        [AppUser.self]
    }
}

// MARK: - Schema Version 2 (Friends & Family)
// Added Friends & Family models: Friendship, Invite, Family, FamilyMember, PendingJoinRequest, ShareCode
// Added fields to AppUser: isRetiredGeneral, activeFamilyId, friendCount

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
            ShareCode.self
        ]
    }
}

// MARK: - Schema Version 3 (Avatar & Badge Identity)
// Added to AppUser: avatarId, equippedBadgeId, wasEverInFamily

enum SchemaVersion3: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(3, 0, 0)
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
            SchemaVersion3Marker.self  // Distinct model so V3 checksum differs from V2
        ]
    }
}

// MARK: - Schema Version 4 (Gameplay model foundation)
// Added TripSessionEntity, GameInstanceEntity for new trip/session and game-instance persistence.
// Legacy Trip removed in V9; TripSessionEntity is canonical.
enum SchemaVersion4: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(4, 0, 0)
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
            SchemaVersion3Marker.self,
            TripSessionEntity.self,
            GameInstanceEntity.self,
            SchemaVersion4Marker.self
        ]
    }
}

// MARK: - Schema Version 5 (Score snapshots — new table only for safe migration)
// Added GameScoreSnapshotEntity; no change to existing entities so V4→V5 is add-table only.
enum SchemaVersion5: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(5, 0, 0)
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
            SchemaVersion3Marker.self,
            TripSessionEntity.self,
            GameInstanceEntity.self,
            SchemaVersion4Marker.self,
            GameScoreSnapshotEntity.self,
            SchemaVersion5Marker.self
        ]
    }
}

// MARK: - Schema Version 6 (Multiplayer trip invites)
// Added TripInvite for trip invite flow; no change to existing entities.
enum SchemaVersion6: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(6, 0, 0)
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
            SchemaVersion3Marker.self,
            TripSessionEntity.self,
            GameInstanceEntity.self,
            SchemaVersion4Marker.self,
            GameScoreSnapshotEntity.self,
            SchemaVersion5Marker.self,
            TripInvite.self,
            SchemaVersion6Marker.self
        ]
    }
}

// MARK: - Schema Version 7 (Team support — new TripSessionTeamsEntity only)
// Added TripSessionTeamsEntity; TripSessionEntity unchanged to preserve schema fingerprint for migration.
// GameInstanceEntity is defined here with the V7 shape (no Step 07.5 config fields) so the existing store
// can match this schema; V8 uses the top-level GameInstanceEntity with the new optional properties.
enum SchemaVersion7: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(7, 0, 0)
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
            SchemaVersion3Marker.self,
            TripSessionEntity.self,
            SchemaVersion7.GameInstanceEntity.self,
            SchemaVersion4Marker.self,
            GameScoreSnapshotEntity.self,
            SchemaVersion5Marker.self,
            TripInvite.self,
            SchemaVersion6Marker.self,
            TripSessionTeamsEntity.self,
            SchemaVersion7Marker.self
        ]
    }

    /// V7 shape of GameInstanceEntity (no commonConfigData / game-specific payload). Nested here so the migration
    /// system has a type that matches the existing store; SwiftData may use the short name "GameInstanceEntity"
    /// for the table. App code uses the top-level GameInstanceEntity (SchemaVersion8).
    @Model
    final class GameInstanceEntity {
        var id: String
        var definitionId: String
        var sessionId: String
        var startedAt: Date
        var endedAt: Date?
        var ruleSetData: Data?

        init(id: String, definitionId: String, sessionId: String, startedAt: Date, endedAt: Date? = nil, ruleSetData: Data? = nil) {
            self.id = id
            self.definitionId = definitionId
            self.sessionId = sessionId
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.ruleSetData = ruleSetData
        }
    }
}

// MARK: - Schema Version 8 (Step 07.5 — Per-game config envelope on GameInstanceEntity)
// Added optional commonConfigData, gameSpecificPayloadType, gameSpecificPayloadVersion, gameSpecificPayloadData.
enum SchemaVersion8: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(8, 0, 0)
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
            SchemaVersion3Marker.self,
            TripSessionEntity.self,
            GameInstanceEntity.self,
            SchemaVersion4Marker.self,
            GameScoreSnapshotEntity.self,
            SchemaVersion5Marker.self,
            TripInvite.self,
            SchemaVersion6Marker.self,
            TripSessionTeamsEntity.self,
            SchemaVersion7Marker.self,
            SchemaVersion8Marker.self
        ]
    }
}

// MARK: - Schema Version 9 (Step 01 — Canonical gameplay only; Trip removed, TripActivityEventEntity added)
enum SchemaVersion9: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(9, 0, 0)
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
            SchemaVersion3Marker.self,
            TripSessionEntity.self,
            GameInstanceEntity.self,
            SchemaVersion4Marker.self,
            GameScoreSnapshotEntity.self,
            SchemaVersion5Marker.self,
            TripInvite.self,
            SchemaVersion6Marker.self,
            TripSessionTeamsEntity.self,
            SchemaVersion7Marker.self,
            SchemaVersion8Marker.self,
            TripActivityEventEntity.self,
            SchemaVersion9Marker.self
        ]
    }
}

// MARK: - Schema Version 10 (TripSessionEntity: add createdAt, remove legacyTripId)
enum SchemaVersion10: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(10, 0, 0)
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
            SchemaVersion3Marker.self,
            TripSessionEntity.self,
            GameInstanceEntity.self,
            SchemaVersion4Marker.self,
            GameScoreSnapshotEntity.self,
            SchemaVersion5Marker.self,
            TripInvite.self,
            SchemaVersion6Marker.self,
            TripSessionTeamsEntity.self,
            SchemaVersion7Marker.self,
            SchemaVersion8Marker.self,
            TripActivityEventEntity.self,
            SchemaVersion9Marker.self,
            SchemaVersion10Marker.self
        ]
    }
}

// MARK: - Schema Version 11 (Sync queue foundation)
// V11: Sync queue foundation (SyncQueueItemEntity, RemoteSyncMetadataEntity).
enum SchemaVersion11: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(11, 0, 0)
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
            SchemaVersion3Marker.self,
            TripSessionEntity.self,
            GameInstanceEntity.self,
            SchemaVersion4Marker.self,
            GameScoreSnapshotEntity.self,
            SchemaVersion5Marker.self,
            TripInvite.self,
            SchemaVersion6Marker.self,
            TripSessionTeamsEntity.self,
            SchemaVersion7Marker.self,
            SchemaVersion8Marker.self,
            TripActivityEventEntity.self,
            SchemaVersion9Marker.self,
            SchemaVersion10Marker.self,
            SyncQueueItemEntity.self,
            RemoteSyncMetadataEntity.self,
            SchemaVersion11Marker.self
        ]
    }
}

// MARK: - Schema Version 12 (Step 6.9.1 — Teams on GameInstance, remove TripSessionTeamsEntity)
// V12: GameInstanceEntity.teamsData added; TripSessionTeamsEntity removed.
enum SchemaVersion12: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(12, 0, 0)
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
            SchemaVersion3Marker.self,
            TripSessionEntity.self,
            SchemaVersion12.GameInstanceEntity.self,
            SchemaVersion4Marker.self,
            GameScoreSnapshotEntity.self,
            SchemaVersion5Marker.self,
            TripInvite.self,
            SchemaVersion6Marker.self,
            SchemaVersion7Marker.self,
            SchemaVersion8Marker.self,
            TripActivityEventEntity.self,
            SchemaVersion9Marker.self,
            SchemaVersion10Marker.self,
            SyncQueueItemEntity.self,
            RemoteSyncMetadataEntity.self,
            SchemaVersion11Marker.self,
            SchemaVersion12Marker.self
        ]
    }

    /// Frozen **V12–V14** game row: `teamsData`, **no** `fairnessUiLastAckAt`. Keeps checksums stable while top-level `GameInstanceEntity` evolves.
    @Model
    final class GameInstanceEntity {
        var id: String
        var definitionId: String
        var sessionId: String
        var startedAt: Date
        var endedAt: Date?
        var ruleSetData: Data?
        var commonConfigData: Data?
        var gameSpecificPayloadType: String?
        var gameSpecificPayloadVersion: String?
        var gameSpecificPayloadData: Data?
        var teamsData: Data?

        init(
            id: String,
            definitionId: String,
            sessionId: String,
            startedAt: Date,
            endedAt: Date? = nil,
            ruleSetData: Data? = nil,
            commonConfigData: Data? = nil,
            gameSpecificPayloadType: String? = nil,
            gameSpecificPayloadVersion: String? = nil,
            gameSpecificPayloadData: Data? = nil,
            teamsData: Data? = nil
        ) {
            self.id = id
            self.definitionId = definitionId
            self.sessionId = sessionId
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.ruleSetData = ruleSetData
            self.commonConfigData = commonConfigData
            self.gameSpecificPayloadType = gameSpecificPayloadType
            self.gameSpecificPayloadVersion = gameSpecificPayloadVersion
            self.gameSpecificPayloadData = gameSpecificPayloadData
            self.teamsData = teamsData
        }
    }
}

// MARK: - Schema Version 13 (Step 6.9.2 — TripSessionEntity: remove enabledCountryRawValues; region scope on GameInstance)
enum SchemaVersion13: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(13, 0, 0)
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
            SchemaVersion3Marker.self,
            TripSessionEntity.self,
            SchemaVersion12.GameInstanceEntity.self,
            SchemaVersion4Marker.self,
            GameScoreSnapshotEntity.self,
            SchemaVersion5Marker.self,
            TripInvite.self,
            SchemaVersion6Marker.self,
            SchemaVersion7Marker.self,
            SchemaVersion8Marker.self,
            TripActivityEventEntity.self,
            SchemaVersion9Marker.self,
            SchemaVersion10Marker.self,
            SyncQueueItemEntity.self,
            RemoteSyncMetadataEntity.self,
            SchemaVersion11Marker.self,
            SchemaVersion12Marker.self,
            SchemaVersion13Marker.self
        ]
    }
}

// MARK: - Schema Version 14 (Step 6.10 — TripSessionEntity.mode removed; TripInvite.tripMode removed; participation derived)
enum SchemaVersion14: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(14, 0, 0)
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
            SchemaVersion3Marker.self,
            TripSessionEntity.self,
            SchemaVersion12.GameInstanceEntity.self,
            SchemaVersion4Marker.self,
            GameScoreSnapshotEntity.self,
            SchemaVersion5Marker.self,
            TripInvite.self,
            SchemaVersion6Marker.self,
            SchemaVersion7Marker.self,
            SchemaVersion8Marker.self,
            TripActivityEventEntity.self,
            SchemaVersion9Marker.self,
            SchemaVersion10Marker.self,
            SyncQueueItemEntity.self,
            RemoteSyncMetadataEntity.self,
            SchemaVersion11Marker.self,
            SchemaVersion12Marker.self,
            SchemaVersion13Marker.self,
            SchemaVersion14Marker.self
        ]
    }
}

// MARK: - Schema Version 15 (Step 13.2 — GameInstanceEntity.fairnessUiLastAckAt)
enum SchemaVersion15: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(15, 0, 0)
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
            SchemaVersion3Marker.self,
            TripSessionEntity.self,
            GameInstanceEntity.self,
            SchemaVersion4Marker.self,
            GameScoreSnapshotEntity.self,
            SchemaVersion5Marker.self,
            TripInvite.self,
            SchemaVersion6Marker.self,
            SchemaVersion7Marker.self,
            SchemaVersion8Marker.self,
            TripActivityEventEntity.self,
            SchemaVersion9Marker.self,
            SchemaVersion10Marker.self,
            SyncQueueItemEntity.self,
            RemoteSyncMetadataEntity.self,
            SchemaVersion11Marker.self,
            SchemaVersion12Marker.self,
            SchemaVersion13Marker.self,
            SchemaVersion14Marker.self,
            SchemaVersion15Marker.self
        ]
    }
}

// MARK: - Schema Version 16 (Step 14 — PendingTripLeaveEntity for offline leave / sync)
enum SchemaVersion16: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(16, 0, 0)
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
            SchemaVersion3Marker.self,
            TripSessionEntity.self,
            GameInstanceEntity.self,
            SchemaVersion4Marker.self,
            GameScoreSnapshotEntity.self,
            SchemaVersion5Marker.self,
            TripInvite.self,
            SchemaVersion6Marker.self,
            SchemaVersion7Marker.self,
            SchemaVersion8Marker.self,
            TripActivityEventEntity.self,
            SchemaVersion9Marker.self,
            SchemaVersion10Marker.self,
            SyncQueueItemEntity.self,
            RemoteSyncMetadataEntity.self,
            SchemaVersion11Marker.self,
            SchemaVersion12Marker.self,
            SchemaVersion13Marker.self,
            SchemaVersion14Marker.self,
            SchemaVersion15Marker.self,
            PendingTripLeaveEntity.self,
            SchemaVersion16Marker.self
        ]
    }
}

// MARK: - Schema Version 17 (User lifetime stats cache)
// Persisted aggregates for profile lifetime statistics (`UserLifetimeStatsEntity`).

enum SchemaVersion17: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(17, 0, 0)
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
            SchemaVersion3Marker.self,
            TripSessionEntity.self,
            GameInstanceEntity.self,
            SchemaVersion4Marker.self,
            GameScoreSnapshotEntity.self,
            SchemaVersion5Marker.self,
            TripInvite.self,
            SchemaVersion6Marker.self,
            SchemaVersion7Marker.self,
            SchemaVersion8Marker.self,
            TripActivityEventEntity.self,
            SchemaVersion9Marker.self,
            SchemaVersion10Marker.self,
            SyncQueueItemEntity.self,
            RemoteSyncMetadataEntity.self,
            SchemaVersion11Marker.self,
            SchemaVersion12Marker.self,
            SchemaVersion13Marker.self,
            SchemaVersion14Marker.self,
            SchemaVersion15Marker.self,
            PendingTripLeaveEntity.self,
            SchemaVersion16Marker.self,
            UserLifetimeStatsEntity.self,
            SchemaVersion17Marker.self
        ]
    }
}

// MARK: - Schema Version 18 (Public lifetime stats Firestore cache)
// Cache rows for `public_lifetime_stats` listeners (friends + family + profile).

enum SchemaVersion18: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(18, 0, 0)
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
            SchemaVersion3Marker.self,
            TripSessionEntity.self,
            GameInstanceEntity.self,
            SchemaVersion4Marker.self,
            GameScoreSnapshotEntity.self,
            SchemaVersion5Marker.self,
            TripInvite.self,
            SchemaVersion6Marker.self,
            SchemaVersion7Marker.self,
            SchemaVersion8Marker.self,
            TripActivityEventEntity.self,
            SchemaVersion9Marker.self,
            SchemaVersion10Marker.self,
            SyncQueueItemEntity.self,
            RemoteSyncMetadataEntity.self,
            SchemaVersion11Marker.self,
            SchemaVersion12Marker.self,
            SchemaVersion13Marker.self,
            SchemaVersion14Marker.self,
            SchemaVersion15Marker.self,
            PendingTripLeaveEntity.self,
            SchemaVersion16Marker.self,
            UserLifetimeStatsEntity.self,
            SchemaVersion17Marker.self,
            PublicLifetimeStatsCacheEntity.self,
            SchemaVersion18Marker.self
        ]
    }
}

// MARK: - Migration Plan
enum AppMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaVersion1.self, SchemaVersion2.self, SchemaVersion3.self, SchemaVersion4.self, SchemaVersion5.self, SchemaVersion6.self, SchemaVersion7.self, SchemaVersion8.self, SchemaVersion9.self, SchemaVersion10.self, SchemaVersion11.self, SchemaVersion12.self, SchemaVersion13.self, SchemaVersion14.self, SchemaVersion15.self, SchemaVersion16.self, SchemaVersion17.self, SchemaVersion18.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: SchemaVersion1.self, toVersion: SchemaVersion2.self),
            .lightweight(fromVersion: SchemaVersion2.self, toVersion: SchemaVersion3.self),
            .lightweight(fromVersion: SchemaVersion3.self, toVersion: SchemaVersion4.self),
            .lightweight(fromVersion: SchemaVersion4.self, toVersion: SchemaVersion5.self),
            .lightweight(fromVersion: SchemaVersion5.self, toVersion: SchemaVersion6.self),
            .lightweight(fromVersion: SchemaVersion6.self, toVersion: SchemaVersion7.self),
            .lightweight(fromVersion: SchemaVersion7.self, toVersion: SchemaVersion8.self),
            .lightweight(fromVersion: SchemaVersion8.self, toVersion: SchemaVersion9.self),
            .lightweight(fromVersion: SchemaVersion9.self, toVersion: SchemaVersion10.self),
            .lightweight(fromVersion: SchemaVersion10.self, toVersion: SchemaVersion11.self),
            .lightweight(fromVersion: SchemaVersion11.self, toVersion: SchemaVersion12.self),
            .lightweight(fromVersion: SchemaVersion12.self, toVersion: SchemaVersion13.self),
            .lightweight(fromVersion: SchemaVersion13.self, toVersion: SchemaVersion14.self),
            .lightweight(fromVersion: SchemaVersion14.self, toVersion: SchemaVersion15.self),
            .lightweight(fromVersion: SchemaVersion15.self, toVersion: SchemaVersion16.self),
            .lightweight(fromVersion: SchemaVersion16.self, toVersion: SchemaVersion17.self),
            .lightweight(fromVersion: SchemaVersion17.self, toVersion: SchemaVersion18.self)
        ]
    }
}

// MARK: - Current Schema
// V18: Public lifetime stats listener cache (`PublicLifetimeStatsCacheEntity`).
typealias CurrentSchema = SchemaVersion18


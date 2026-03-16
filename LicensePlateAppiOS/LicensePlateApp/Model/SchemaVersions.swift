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
// TODO: Eventually deprecate legacy Trip once UI/features migrate to TripSessionEntity.
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

// MARK: - Migration Plan
enum AppMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaVersion1.self, SchemaVersion2.self, SchemaVersion3.self, SchemaVersion4.self, SchemaVersion5.self, SchemaVersion6.self, SchemaVersion7.self, SchemaVersion8.self, SchemaVersion9.self, SchemaVersion10.self]
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
            .lightweight(fromVersion: SchemaVersion9.self, toVersion: SchemaVersion10.self)
        ]
    }
}

// MARK: - Current Schema
// V10: TripSessionEntity has createdAt, no legacyTripId; TripStatus.draft removed.
typealias CurrentSchema = SchemaVersion10


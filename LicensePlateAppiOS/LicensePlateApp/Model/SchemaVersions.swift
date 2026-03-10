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

// MARK: - Schema Version 1 (Initial)
// Initial schema with Trip and AppUser

enum SchemaVersion1: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(1, 0, 0)
    }
    
    static var models: [any PersistentModel.Type] {
        [Trip.self, AppUser.self]
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
            Trip.self,
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
            Trip.self,
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
            Trip.self,
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
            Trip.self,
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

// MARK: - Migration Plan
// TODO: Once UI migrates to TripSessionEntity/GameInstanceEntity, plan legacy Trip deprecation.
enum AppMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaVersion1.self, SchemaVersion2.self, SchemaVersion3.self, SchemaVersion4.self, SchemaVersion5.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: SchemaVersion1.self, toVersion: SchemaVersion2.self),
            .lightweight(fromVersion: SchemaVersion2.self, toVersion: SchemaVersion3.self),
            .lightweight(fromVersion: SchemaVersion3.self, toVersion: SchemaVersion4.self),
            .lightweight(fromVersion: SchemaVersion4.self, toVersion: SchemaVersion5.self)
        ]
    }
}

// MARK: - Current Schema
// This points to the latest schema version
// When creating a new version, update this to point to the latest
// birthYear is stored in Firestore only (not SwiftData) to avoid schema migration
typealias CurrentSchema = SchemaVersion5


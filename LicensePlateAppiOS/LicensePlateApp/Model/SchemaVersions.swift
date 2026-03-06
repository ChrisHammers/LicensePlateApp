//
//  SchemaVersions.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//

import Foundation
import SwiftData

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
            ShareCode.self
        ]
    }
}

// MARK: - Migration Plan
enum AppMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaVersion1.self, SchemaVersion2.self, SchemaVersion3.self]
    }
    
    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: SchemaVersion1.self, toVersion: SchemaVersion2.self),
            .lightweight(fromVersion: SchemaVersion2.self, toVersion: SchemaVersion3.self)
        ]
    }
}

// MARK: - Current Schema
// This points to the latest schema version
// When creating a new version, update this to point to the latest
// birthYear is stored in Firestore only (not SwiftData) to avoid schema migration
typealias CurrentSchema = SchemaVersion3


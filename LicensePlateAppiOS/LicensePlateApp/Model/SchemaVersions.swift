//
//  SchemaVersions.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//

import Foundation
import SwiftData

// MARK: - Schema Version 1 (Current)
// This is the initial schema version
// When you need to migrate, create Version 2 and add migration logic

enum SchemaVersion1: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(1, 0, 0)
    }
    
    static var models: [any PersistentModel.Type] {
        [
            Trip.self,
            AppUser.self,
            Family.self,
            FamilyMember.self,
            Game.self,
            GameTeam.self,
            FriendRequest.self,
            AppCompetition.self
        ]
    }
}

// MARK: - Migration Plan
// When you create Version 2, add it to schemas and define migration stages
enum AppMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaVersion1.self]
        // Add future versions here, e.g.:
        // [SchemaVersion1.self, SchemaVersion2.self]
    }
    
    static var stages: [MigrationStage] {
        []
        // Add migration stages when creating Version 2, e.g.:
        // [.lightweight(fromVersion: SchemaVersion1.self, toVersion: SchemaVersion2.self)]
    }
}

// MARK: - Current Schema
// This points to the latest schema version
// When creating a new version, update this to point to the latest

typealias CurrentSchema = SchemaVersion1


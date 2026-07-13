//
//  SchemaVersions.swift
//  LicensePlateApp
//
//  Pre-release reset: single VersionedSchema (V1) matching the live @Model set.
//  Beta installs should delete/reinstall the app (or wipe the store) once after this change.
//

import Foundation
import SwiftData

// MARK: - Schema Version 1 (Current pre-release baseline)

enum SchemaVersion1: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(1, 0, 0)
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
        [SchemaVersion1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}

// MARK: - Current Schema

typealias CurrentSchema = SchemaVersion1

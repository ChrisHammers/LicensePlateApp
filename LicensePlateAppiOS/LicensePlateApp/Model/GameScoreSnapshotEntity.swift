//
//  GameScoreSnapshotEntity.swift
//  LicensePlateApp
//
//  SwiftData entity for score snapshots (V5). Stored separately to avoid altering GameInstanceEntity and keep migration lightweight.
//

import Foundation
import SwiftData

/// Persisted score snapshot for a game instance. One-to-one with GameInstanceEntity (by gameInstanceId).
@Model
final class GameScoreSnapshotEntity {
    var id: String
    var gameInstanceId: String
    var snapshotData: Data
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        gameInstanceId: String,
        snapshotData: Data,
        createdAt: Date = .now
    ) {
        self.id = id
        self.gameInstanceId = gameInstanceId
        self.snapshotData = snapshotData
        self.createdAt = createdAt
    }
}

//
//  TripJoinerHydrationTests.swift
//  LicensePlateAppTests
//
//  Step 12.5 — Joiner local session + games hydration matches active-list filtering.
//

import Foundation
import SwiftData
import Testing
@testable import LicensePlateApp

@MainActor
struct TripJoinerHydrationTests {

    @Test
    func hydratedSessionAppearsInActiveListForMemberUserId() throws {
        let sessionId = UUID()
        let ownerId = "owner-uid"
        let joinerId = "joiner-uid"
        let created = Date(timeIntervalSince1970: 1_800_000_000)

        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: TripSessionEntity.self, GameInstanceEntity.self, TripActivityEventEntity.self, GameScoreSnapshotEntity.self,
            configurations: config
        )
        let ctx = ModelContext(container)

        let tripRepo = TripSessionRepository.shared
        let gameRepo = GameInstanceRepository.shared
        tripRepo.setModelContext(ctx)
        gameRepo.setModelContext(ctx)

        let wireSession = TripSessionWireDTO(
            id: sessionId.uuidString,
            name: "Shared Trip",
            status: TripSessionState.active.rawValue,
            createdAt: created.timeIntervalSince1970,
            createdBy: ownerId,
            startedAt: created.timeIntervalSince1970,
            endedAt: nil,
            endedBy: nil,
            participants: [
                TripParticipantWireItem(userId: ownerId, role: TripParticipantRole.owner.rawValue, joinedAt: created.timeIntervalSince1970, leftAt: nil, teamId: nil),
                TripParticipantWireItem(userId: joinerId, role: TripParticipantRole.member.rawValue, joinedAt: created.timeIntervalSince1970, leftAt: nil, teamId: nil),
            ]
        )
        let domainSession = TripCanonicalMapper.domainSession(from: wireSession)
        try tripRepo.save(session: domainSession)

        let game = GameInstance(
            definitionId: GameType.licensePlate.rawValue,
            sessionId: sessionId,
            startedAt: created,
            ruleSet: GameRuleSet(gameDefinitionId: GameType.licensePlate.rawValue),
            commonConfig: CommonGameConfig()
        )
        try gameRepo.replaceGamesForSession(sessionId: sessionId, instances: [game])

        let forOwner = try tripRepo.loadActiveSessions(userId: ownerId)
        let forJoiner = try tripRepo.loadActiveSessions(userId: joinerId)
        #expect(forOwner.count == 1)
        #expect(forJoiner.count == 1)
        #expect(forJoiner.first?.id == sessionId)
    }
}

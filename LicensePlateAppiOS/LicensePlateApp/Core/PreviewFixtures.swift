//
//  PreviewFixtures.swift
//  LicensePlateApp
//
//  Step 13 — Deterministic fixtures for SwiftUI previews. Multi-game trip architecture.
//  Previews should use PreviewConstants, Preview*Fixtures, or Mock*Factory so data stays deterministic and consistent with tests (see MockFactoryRegistry).
//

import Foundation

// MARK: - Deterministic IDs and timestamps

enum PreviewConstants {
    static let sessionIdSolo = UUID(uuidString: "E621E1F8-C36C-4A1B-9F2D-111111111111")!
    static let sessionIdMulti = UUID(uuidString: "E621E1F8-C36C-4A1B-9F2D-222222222222")!
    static let sessionIdCollaborative = UUID(uuidString: "E621E1F8-C36C-4A1B-9F2D-333333333333")!
    static let sessionIdCompetitive = UUID(uuidString: "E621E1F8-C36C-4A1B-9F2D-444444444444")!
    static let sessionIdWithTeams = UUID(uuidString: "E621E1F8-C36C-4A1B-9F2D-555555555555")!
    static let sessionIdPartial = UUID(uuidString: "E621E1F8-C36C-4A1B-9F2D-666666666666")!
    static let sessionIdCompleted = UUID(uuidString: "E621E1F8-C36C-4A1B-9F2D-777777777777")!

    static let gameInstanceId1 = UUID(uuidString: "A1111111-1111-1111-1111-111111111111")!
    static let gameInstanceId2 = UUID(uuidString: "A2222222-2222-2222-2222-222222222222")!
    static let gameInstanceId3 = UUID(uuidString: "A3333333-3333-3333-3333-333333333333")!

    static let userId1 = "preview-user-1"
    static let userId2 = "preview-user-2"
    static let userId3 = "preview-user-3"

    static let teamId1 = "preview-team-1"
    static let teamId2 = "preview-team-2"

    static let discoveryId1 = "preview-discovery-1"
    static let discoveryId2 = "preview-discovery-2"

    static let fixedDate = Date(timeIntervalSince1970: 1_700_000_000) // ~Nov 2023
    static let fixedDateEnded = Date(timeIntervalSince1970: 1_700_010_000)
}

// MARK: - PreviewTripFixtures

enum PreviewTripFixtures {
    static func soloTrip() -> TripSession {
        TripSession(
            id: PreviewConstants.sessionIdSolo,
            name: "Solo Road Trip",
            status: .active,
            createdAt: PreviewConstants.fixedDate,
            createdBy: PreviewConstants.userId1,
            startedAt: PreviewConstants.fixedDate,
            endedAt: nil,
            participants: [PreviewParticipantFixtures.driver(userId: PreviewConstants.userId1)]
        )
    }

    /// Multiplayer trip (one participant; use for multi-game-type previews). Game mode is on each GameInstance.
    static func multiGameTrip() -> TripSession {
        TripSession(
            id: PreviewConstants.sessionIdMulti,
            name: "Multi-Game Trip",
            status: .active,
            createdAt: PreviewConstants.fixedDate,
            createdBy: PreviewConstants.userId1,
            startedAt: PreviewConstants.fixedDate,
            participants: [PreviewParticipantFixtures.driver(userId: PreviewConstants.userId1)]
        )
    }

    /// Multiplayer trip with two participants (e.g. family). For collaborative game behavior use a game with commonConfig.gameMode == .collaborative.
    static func collaborativeTrip() -> TripSession {
        TripSession(
            id: PreviewConstants.sessionIdCollaborative,
            name: "Family Road Trip",
            status: .active,
            createdAt: PreviewConstants.fixedDate,
            createdBy: PreviewConstants.userId1,
            startedAt: PreviewConstants.fixedDate,
            participants: [
                PreviewParticipantFixtures.driver(userId: PreviewConstants.userId1),
                PreviewParticipantFixtures.passenger(userId: PreviewConstants.userId2)
            ]
        )
    }

    /// Multiplayer trip with two participants. For competitive game behavior use a game with commonConfig.gameMode == .competitive.
    static func competitiveTrip() -> TripSession {
        TripSession(
            id: PreviewConstants.sessionIdCompetitive,
            name: "Competitive Trip",
            status: .active,
            createdAt: PreviewConstants.fixedDate,
            createdBy: PreviewConstants.userId1,
            startedAt: PreviewConstants.fixedDate,
            participants: [
                PreviewParticipantFixtures.driver(userId: PreviewConstants.userId1),
                PreviewParticipantFixtures.passenger(userId: PreviewConstants.userId2)
            ]
        )
    }

    /// Session for team-based preview. Teams are on GameInstance; use PreviewGameFixtures.licensePlateGame(sessionId:teams:) for a game with teams.
    static func tripWithTeams() -> TripSession {
        TripSession(
            id: PreviewConstants.sessionIdWithTeams,
            name: "Team Road Trip",
            status: .active,
            createdAt: PreviewConstants.fixedDate,
            createdBy: PreviewConstants.userId1,
            startedAt: PreviewConstants.fixedDate,
            participants: PreviewParticipantFixtures.participantsForSession(teamIds: (PreviewConstants.teamId1, PreviewConstants.teamId2))
        )
    }

    static func partiallyCompletedTrip() -> TripSession {
        TripSession(
            id: PreviewConstants.sessionIdPartial,
            name: "In Progress Trip",
            status: .active,
            createdAt: PreviewConstants.fixedDate,
            createdBy: PreviewConstants.userId1,
            startedAt: PreviewConstants.fixedDate,
            participants: [PreviewParticipantFixtures.driver(userId: PreviewConstants.userId1)]
        )
    }

    static func completedTrip() -> TripSession {
        TripSession(
            id: PreviewConstants.sessionIdCompleted,
            name: "Completed Trip",
            status: .ended,
            createdAt: PreviewConstants.fixedDate,
            createdBy: PreviewConstants.userId1,
            startedAt: PreviewConstants.fixedDate,
            endedAt: PreviewConstants.fixedDateEnded,
            endedBy: PreviewConstants.userId1,
            participants: [PreviewParticipantFixtures.driver(userId: PreviewConstants.userId1)]
        )
    }
}

// MARK: - PreviewGameFixtures

enum PreviewGameFixtures {
    static func licensePlateGame(sessionId: UUID = PreviewConstants.sessionIdSolo, teams: [TripTeam] = []) -> GameInstance {
        let ruleSet = GameRuleSet(gameDefinitionId: GameType.licensePlate.rawValue)
        var config = CommonGameConfig()
        config.lifecycleState = .started
        let lpConfig = LicensePlateGameConfig(selectedCountriesRawValues: [PlateRegion.Country.unitedStates.rawValue, PlateRegion.Country.canada.rawValue, PlateRegion.Country.mexico.rawValue])
        let payloadData = try? JSONEncoder().encode(lpConfig)
        return GameInstance(
            id: PreviewConstants.gameInstanceId1,
            definitionId: GameType.licensePlate.rawValue,
            sessionId: sessionId,
            startedAt: PreviewConstants.fixedDate,
            endedAt: nil,
            ruleSet: ruleSet,
            commonConfig: config,
            gameSpecificPayloadType: "license_plate",
            gameSpecificPayloadVersion: "1",
            gameSpecificPayloadData: payloadData,
            teams: teams
        )
    }

    static func multiGameInstances(for sessionId: UUID) -> [GameInstance] {
        let lp = licensePlateGame(sessionId: sessionId)
        var bingo = GameInstance(
            id: PreviewConstants.gameInstanceId2,
            definitionId: GameType.roadSignBingo.rawValue,
            sessionId: sessionId,
            startedAt: PreviewConstants.fixedDate,
            ruleSet: GameRuleSet(gameDefinitionId: GameType.roadSignBingo.rawValue)
        )
        var carModel = GameInstance(
            id: PreviewConstants.gameInstanceId3,
            definitionId: GameType.carModelSpotting.rawValue,
            sessionId: sessionId,
            startedAt: PreviewConstants.fixedDate,
            ruleSet: GameRuleSet(gameDefinitionId: GameType.carModelSpotting.rawValue)
        )
        bingo.commonConfig.lifecycleState = .started
        carModel.commonConfig.lifecycleState = .started
        return [lp, bingo, carModel]
    }
}

// MARK: - PreviewDiscoveryFixtures

enum PreviewDiscoveryFixtures {
    static func discovery(
        gameInstanceId: UUID = PreviewConstants.gameInstanceId1,
        participantId: String = PreviewConstants.userId1
    ) -> GameDiscovery {
        GameDiscovery(
            id: PreviewConstants.discoveryId1,
            gameInstanceId: gameInstanceId,
            participantId: participantId,
            targetId: "US-CA",
            discoveredAt: PreviewConstants.fixedDate,
            inputMethod: .list
        )
    }

    static func discoveryWithRiskFlag(
        gameInstanceId: UUID = PreviewConstants.gameInstanceId1,
        participantId: String = PreviewConstants.userId1
    ) -> GameDiscovery {
        let flag = RiskFlag(
            type: .rapidDiscovery,
            severity: .warning,
            source: .localHeuristic,
            presentationKey: "risk_rapid_discovery"
        )
        return GameDiscovery(
            id: PreviewConstants.discoveryId2,
            gameInstanceId: gameInstanceId,
            participantId: participantId,
            targetId: "US-TX",
            discoveredAt: PreviewConstants.fixedDate,
            inputMethod: .list,
            riskFlags: [flag]
        )
    }
}

// MARK: - PreviewParticipantFixtures

enum PreviewParticipantFixtures {
    static func driver(userId: String = PreviewConstants.userId1) -> TripParticipant {
        TripParticipant(
            userId: userId,
            role: .owner,
            joinedAt: PreviewConstants.fixedDate,
            teamId: nil
        )
    }

    static func passenger(userId: String = PreviewConstants.userId2) -> TripParticipant {
        TripParticipant(
            userId: userId,
            role: .member,
            joinedAt: PreviewConstants.fixedDate,
            teamId: nil
        )
    }

    static func participantsForSession(teamIds: (String, String)? = nil) -> [TripParticipant] {
        if let (t1, t2) = teamIds {
            return [
                TripParticipant(userId: PreviewConstants.userId1, role: .owner, joinedAt: PreviewConstants.fixedDate, teamId: t1),
                TripParticipant(userId: PreviewConstants.userId2, role: .member, joinedAt: PreviewConstants.fixedDate, teamId: t2)
            ]
        }
        return [driver(), passenger()]
    }
}

// MARK: - PreviewTeamFixtures

enum PreviewTeamFixtures {
    static func twoTeams(participantUserIds: ([String], [String])) -> [TripTeam] {
        [
            TripTeam(id: PreviewConstants.teamId1, name: "Team Alpha", participantUserIds: participantUserIds.0),
            TripTeam(id: PreviewConstants.teamId2, name: "Team Beta", participantUserIds: participantUserIds.1)
        ]
    }
}

// MARK: - PreviewTravelLogFixtures

enum PreviewTravelLogFixtures {
    static func travelLogEntry(
        sessionId: UUID = PreviewConstants.sessionIdCompleted,
        tripName: String = "Completed Trip"
    ) -> TravelLogEntry {
        TravelLogEntry(
            id: "preview-travel-log-1",
            sessionId: sessionId,
            tripName: tripName,
            endedAt: PreviewConstants.fixedDateEnded,
            summary: "12 regions found",
            participantCount: 1,
            gameCount: 1,
            status: .ended
        )
    }

    static func travelLogEntryWithSummaries() -> TravelLogEntry {
        TravelLogEntry(
            id: "preview-travel-log-2",
            sessionId: PreviewConstants.sessionIdCompleted,
            tripName: "Family Road Trip",
            endedAt: PreviewConstants.fixedDateEnded,
            summary: "License Plate: 15/50 • 2 participants",
            participantCount: 2,
            gameCount: 1,
            status: .ended
        )
    }
}

// MARK: - PreviewSummaryFixtures (TripSummary for detail view)

enum PreviewSummaryFixtures {
    static func tripSummarySolo() -> TripSummary {
        TripSummary(
            sessionId: PreviewConstants.sessionIdCompleted,
            tripName: "Completed Trip",
            tripMode: .solo,
            status: .ended,
            endedAt: PreviewConstants.fixedDateEnded,
            startedAt: PreviewConstants.fixedDate,
            participantCount: 1,
            gameCount: 1,
            totalDiscoveryCount: 12,
            games: [
                TripSummaryGameItem(
                    gameInstanceId: PreviewConstants.gameInstanceId1,
                    definitionId: GameType.licensePlate.rawValue,
                    discoveryCount: 12,
                    startedAt: PreviewConstants.fixedDate,
                    endedAt: PreviewConstants.fixedDateEnded,
                    firstDiscoveries: [],
                    completionGoal: 50,
                    progressDescription: "12 / 50 US states",
                    gameMode: .collaborative,
                    teamSummary: nil
                )
            ],
            rankedParticipants: TripParticipantRanking.rankContributions([
                ParticipantContribution(
                    participantId: PreviewConstants.userId1,
                    discoveryCount: 12,
                    weightedScore: 12,
                    firstFindCount: 12
                )
            ]),
            discoveryProjection: nil,
            locationMetadata: nil
        )
    }

    static func tripSummaryMultiGame() -> TripSummary {
        TripSummary(
            sessionId: PreviewConstants.sessionIdMulti,
            tripName: "Multi-Game Trip",
            tripMode: .solo,
            status: .ended,
            endedAt: PreviewConstants.fixedDateEnded,
            startedAt: PreviewConstants.fixedDate,
            participantCount: 1,
            gameCount: 3,
            totalDiscoveryCount: 25,
            games: [
                TripSummaryGameItem(
                    gameInstanceId: PreviewConstants.gameInstanceId1,
                    definitionId: GameType.licensePlate.rawValue,
                    discoveryCount: 12,
                    startedAt: PreviewConstants.fixedDate,
                    endedAt: PreviewConstants.fixedDateEnded,
                    firstDiscoveries: [],
                    completionGoal: 50,
                    progressDescription: "12 / 50",
                    gameMode: .collaborative,
                    teamSummary: "Road Crew"
                ),
                TripSummaryGameItem(
                    gameInstanceId: PreviewConstants.gameInstanceId2,
                    definitionId: GameType.roadSignBingo.rawValue,
                    discoveryCount: 8,
                    startedAt: PreviewConstants.fixedDate,
                    endedAt: PreviewConstants.fixedDateEnded,
                    firstDiscoveries: [],
                    completionGoal: nil,
                    progressDescription: nil,
                    gameMode: .competitive,
                    teamSummary: nil
                ),
                TripSummaryGameItem(
                    gameInstanceId: PreviewConstants.gameInstanceId3,
                    definitionId: GameType.carModelSpotting.rawValue,
                    discoveryCount: 5,
                    startedAt: PreviewConstants.fixedDate,
                    endedAt: PreviewConstants.fixedDateEnded,
                    firstDiscoveries: [],
                    completionGoal: nil,
                    progressDescription: nil,
                    gameMode: .collaborative,
                    teamSummary: nil
                )
            ],
            rankedParticipants: TripParticipantRanking.rankContributions([
                ParticipantContribution(
                    participantId: PreviewConstants.userId1,
                    discoveryCount: 25,
                    weightedScore: 25,
                    firstFindCount: 25
                )
            ]),
            discoveryProjection: nil,
            locationMetadata: nil
        )
    }

    /// Two license plate games both found the same region — trip-level first discoveries list shows two rows with game context.
    static func tripSummaryDuplicateRegionAcrossGames() -> TripSummary {
        let g1 = PreviewConstants.gameInstanceId1
        let g2 = PreviewConstants.gameInstanceId2
        let projection = DiscoveryCreditProjection(
            participantScores: [],
            targetSummaries: [
                TargetDiscoverySummary(
                    gameInstanceId: g1,
                    targetId: "us-ca",
                    firstFinderParticipantId: PreviewConstants.userId1,
                    allFinderParticipantIds: [PreviewConstants.userId1],
                    summaryLabel: "Found by \(PreviewConstants.userId1)"
                ),
                TargetDiscoverySummary(
                    gameInstanceId: g2,
                    targetId: "us-ca",
                    firstFinderParticipantId: PreviewConstants.userId2,
                    allFinderParticipantIds: [PreviewConstants.userId2],
                    summaryLabel: "Found by \(PreviewConstants.userId2)"
                )
            ]
        )
        return TripSummary(
            sessionId: PreviewConstants.sessionIdMulti,
            tripName: "Same state, two games",
            tripMode: .multiplayer,
            status: .ended,
            endedAt: PreviewConstants.fixedDateEnded,
            startedAt: PreviewConstants.fixedDate,
            participantCount: 2,
            gameCount: 2,
            totalDiscoveryCount: 2,
            games: [
                TripSummaryGameItem(
                    gameInstanceId: g1,
                    definitionId: GameType.licensePlate.rawValue,
                    discoveryCount: 1,
                    startedAt: PreviewConstants.fixedDate,
                    endedAt: PreviewConstants.fixedDateEnded,
                    firstDiscoveries: [],
                    completionGoal: 50,
                    progressDescription: "1 / 50 US states",
                    gameMode: .collaborative,
                    teamSummary: nil
                ),
                TripSummaryGameItem(
                    gameInstanceId: g2,
                    definitionId: GameType.licensePlate.rawValue,
                    discoveryCount: 1,
                    startedAt: PreviewConstants.fixedDate,
                    endedAt: PreviewConstants.fixedDateEnded,
                    firstDiscoveries: [],
                    completionGoal: 50,
                    progressDescription: "1 / 50 US states",
                    gameMode: .collaborative,
                    teamSummary: nil
                )
            ],
            rankedParticipants: TripParticipantRanking.rankContributions([
                ParticipantContribution(
                    participantId: PreviewConstants.userId1,
                    discoveryCount: 1,
                    weightedScore: 1.0,
                    firstFindCount: 1
                ),
                ParticipantContribution(
                    participantId: PreviewConstants.userId2,
                    discoveryCount: 1,
                    weightedScore: 1.0,
                    firstFindCount: 1
                )
            ]),
            discoveryProjection: projection,
            locationMetadata: nil
        )
    }

    /// Multiplayer collaborative: same region found by two participants (discovery highlights).
    static func tripSummaryCollaborativeTwoFindersOneRegion() -> TripSummary {
        let gid = PreviewConstants.gameInstanceId1
        let projection = DiscoveryCreditProjection(
            participantScores: [],
            targetSummaries: [
                TargetDiscoverySummary(
                    gameInstanceId: gid,
                    targetId: "us-tx",
                    firstFinderParticipantId: PreviewConstants.userId1,
                    allFinderParticipantIds: [PreviewConstants.userId1, PreviewConstants.userId2],
                    summaryLabel: "%d finders".localized(2)
                )
            ]
        )
        return TripSummary(
            sessionId: PreviewConstants.sessionIdCollaborative,
            tripName: "Family Trip",
            tripMode: .multiplayer,
            status: .ended,
            endedAt: PreviewConstants.fixedDateEnded,
            startedAt: PreviewConstants.fixedDate,
            participantCount: 2,
            gameCount: 1,
            totalDiscoveryCount: 2,
            games: [
                TripSummaryGameItem(
                    gameInstanceId: gid,
                    definitionId: GameType.licensePlate.rawValue,
                    discoveryCount: 2,
                    startedAt: PreviewConstants.fixedDate,
                    endedAt: PreviewConstants.fixedDateEnded,
                    firstDiscoveries: projection.targetSummaries,
                    completionGoal: 50,
                    progressDescription: "2 / 50 US states",
                    gameMode: .collaborative,
                    teamSummary: nil
                )
            ],
            rankedParticipants: TripParticipantRanking.rankContributions([
                ParticipantContribution(
                    participantId: PreviewConstants.userId1,
                    discoveryCount: 1,
                    weightedScore: 0.5,
                    firstFindCount: 1
                ),
                ParticipantContribution(
                    participantId: PreviewConstants.userId2,
                    discoveryCount: 1,
                    weightedScore: 0.5,
                    firstFindCount: 0
                )
            ]),
            discoveryProjection: projection,
            locationMetadata: nil
        )
    }

    /// Collaborative: three finders on one region — recap uses multi-name attribution line.
    static func tripSummaryCollaborativeThreeFindersOneRegion() -> TripSummary {
        let gid = PreviewConstants.gameInstanceId1
        let projection = DiscoveryCreditProjection(
            participantScores: [],
            targetSummaries: [
                TargetDiscoverySummary(
                    gameInstanceId: gid,
                    targetId: "us-tx",
                    firstFinderParticipantId: PreviewConstants.userId1,
                    allFinderParticipantIds: [PreviewConstants.userId1, PreviewConstants.userId2, PreviewConstants.userId3],
                    summaryLabel: "%d finders".localized(3)
                )
            ]
        )
        return TripSummary(
            sessionId: PreviewConstants.sessionIdCollaborative,
            tripName: "Three Finder Trip",
            tripMode: .multiplayer,
            status: .ended,
            endedAt: PreviewConstants.fixedDateEnded,
            startedAt: PreviewConstants.fixedDate,
            participantCount: 3,
            gameCount: 1,
            totalDiscoveryCount: 3,
            games: [
                TripSummaryGameItem(
                    gameInstanceId: gid,
                    definitionId: GameType.licensePlate.rawValue,
                    discoveryCount: 3,
                    startedAt: PreviewConstants.fixedDate,
                    endedAt: PreviewConstants.fixedDateEnded,
                    firstDiscoveries: projection.targetSummaries,
                    completionGoal: 50,
                    progressDescription: "3 / 50 US states",
                    gameMode: .collaborative,
                    teamSummary: nil
                )
            ],
            rankedParticipants: TripParticipantRanking.rankContributions([
                ParticipantContribution(
                    participantId: PreviewConstants.userId1,
                    discoveryCount: 1,
                    weightedScore: 1.0 / 3.0,
                    firstFindCount: 1
                ),
                ParticipantContribution(
                    participantId: PreviewConstants.userId2,
                    discoveryCount: 1,
                    weightedScore: 1.0 / 3.0,
                    firstFindCount: 0
                ),
                ParticipantContribution(
                    participantId: PreviewConstants.userId3,
                    discoveryCount: 1,
                    weightedScore: 1.0 / 3.0,
                    firstFindCount: 0
                )
            ]),
            discoveryProjection: projection,
            locationMetadata: nil
        )
    }

    /// Many highlight rows to exercise show-all / show-less in recap (Step 15).
    static func tripSummaryManyDiscoveryHighlights() -> TripSummary {
        let gid = PreviewConstants.gameInstanceId1
        let targetRows: [TargetDiscoverySummary] = (0..<22).map { i in
            TargetDiscoverySummary(
                gameInstanceId: gid,
                targetId: "us-\(i)",
                firstFinderParticipantId: PreviewConstants.userId1,
                allFinderParticipantIds: [PreviewConstants.userId1],
                summaryLabel: "Found by \(PreviewConstants.userId1)"
            )
        }
        let projection = DiscoveryCreditProjection(participantScores: [], targetSummaries: targetRows)
        return TripSummary(
            sessionId: PreviewConstants.sessionIdCollaborative,
            tripName: "Long highlights",
            tripMode: .solo,
            status: .ended,
            endedAt: PreviewConstants.fixedDateEnded,
            startedAt: PreviewConstants.fixedDate,
            participantCount: 1,
            gameCount: 1,
            totalDiscoveryCount: 22,
            games: [
                TripSummaryGameItem(
                    gameInstanceId: gid,
                    definitionId: GameType.licensePlate.rawValue,
                    discoveryCount: 22,
                    startedAt: PreviewConstants.fixedDate,
                    endedAt: PreviewConstants.fixedDateEnded,
                    firstDiscoveries: targetRows,
                    completionGoal: 50,
                    progressDescription: "22 / 50 US states",
                    gameMode: .collaborative,
                    teamSummary: nil
                )
            ],
            rankedParticipants: TripParticipantRanking.rankContributions([
                ParticipantContribution(
                    participantId: PreviewConstants.userId1,
                    discoveryCount: 22,
                    weightedScore: 22,
                    firstFindCount: 22
                )
            ]),
            discoveryProjection: projection,
            locationMetadata: nil
        )
    }

    /// Competitive multiplayer: tied weighted score (rank 1,1); `hasCompetitiveGame` true for summary UI.
    static func tripSummaryCompetitiveTied() -> TripSummary {
        let gid = PreviewConstants.gameInstanceId1
        return TripSummary(
            sessionId: PreviewConstants.sessionIdCollaborative,
            tripName: "Competitive Weekend",
            tripMode: .multiplayer,
            status: .ended,
            endedAt: PreviewConstants.fixedDateEnded,
            startedAt: PreviewConstants.fixedDate,
            participantCount: 2,
            gameCount: 1,
            totalDiscoveryCount: 4,
            games: [
                TripSummaryGameItem(
                    gameInstanceId: gid,
                    definitionId: GameType.licensePlate.rawValue,
                    discoveryCount: 4,
                    startedAt: PreviewConstants.fixedDate,
                    endedAt: PreviewConstants.fixedDateEnded,
                    firstDiscoveries: [],
                    completionGoal: 50,
                    progressDescription: "4 / 50 US states",
                    gameMode: .competitive,
                    teamSummary: nil
                )
            ],
            rankedParticipants: TripParticipantRanking.rankContributions([
                ParticipantContribution(
                    participantId: PreviewConstants.userId1,
                    discoveryCount: 2,
                    weightedScore: 2.0,
                    firstFindCount: 2
                ),
                ParticipantContribution(
                    participantId: PreviewConstants.userId2,
                    discoveryCount: 2,
                    weightedScore: 2.0,
                    firstFindCount: 2
                )
            ]),
            discoveryProjection: nil,
            locationMetadata: nil
        )
    }
}

// MARK: - PreviewInviteFixtures (TripInvite is @Model — use in preview with modelContainer and insert)

/// TripInvite is a SwiftData @Model. In previews, create a ModelContainer and insert:
/// `let invite = TripInvite(inviteId: "...", tripSessionId: sessionId.uuidString, ...); context.insert(invite)`
/// This struct holds the parameters for creating a TripInvite so previews can share deterministic data.
struct PreviewInviteFixturesParams {
    let inviteId: String
    let tripSessionId: String
    let tripName: String
    let fromUserId: String
    let toUserId: String?
    let status: TripInvite.TripInviteStatus
    let createdAt: Date
    let expiresAt: Date
    let respondedAt: Date?

    static func pendingInvite() -> PreviewInviteFixturesParams {
        PreviewInviteFixturesParams(
            inviteId: "preview-invite-pending",
            tripSessionId: PreviewConstants.sessionIdCollaborative.uuidString,
            tripName: "Family Road Trip",
            fromUserId: PreviewConstants.userId1,
            toUserId: PreviewConstants.userId2,
            status: .pending,
            createdAt: PreviewConstants.fixedDate,
            expiresAt: PreviewConstants.fixedDate.addingTimeInterval(86400 * 7),
            respondedAt: nil
        )
    }

    static func acceptedInvite() -> PreviewInviteFixturesParams {
        PreviewInviteFixturesParams(
            inviteId: "preview-invite-accepted",
            tripSessionId: PreviewConstants.sessionIdCollaborative.uuidString,
            tripName: "Family Road Trip",
            fromUserId: PreviewConstants.userId1,
            toUserId: PreviewConstants.userId2,
            status: .accepted,
            createdAt: PreviewConstants.fixedDate,
            expiresAt: PreviewConstants.fixedDate.addingTimeInterval(86400 * 7),
            respondedAt: PreviewConstants.fixedDateEnded
        )
    }
}

// MARK: - PreviewUserFixtures (AppUser is @Model)

/// AppUser is a SwiftData @Model. Use in previews with modelContainer(for: [AppUser.self, ...], inMemory: true)
/// and insert the user in the context. This struct describes fixture data; callers create AppUser in context.
/// Alternatively, use MockUserFactory in tests where a non-persisted clone is acceptable.
enum PreviewUserFixtures {
    /// User IDs and display names for consistent previews. Create AppUser in ModelContext with these values.
    static let userId1 = PreviewConstants.userId1
    static let userId2 = PreviewConstants.userId2
    static let userName1 = "Preview Driver"
    static let userName2 = "Preview Passenger"
}

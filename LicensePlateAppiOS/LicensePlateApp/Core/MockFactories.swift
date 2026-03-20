//
//  MockFactories.swift
//  LicensePlateApp
//
//  Step 13 — Factories for complete gameplay graphs. Deterministic; used by previews and tests.
//

import Foundation

// MARK: - MockTripFactory

enum MockTripFactory {
    static func makeSoloTrip(overrides: (inout TripSession) -> Void = { _ in }) -> TripSession {
        var session = TripSession(
            id: PreviewConstants.sessionIdSolo,
            name: "Solo Trip",
            status: .active,
            mode: .solo,
            createdAt: PreviewConstants.fixedDate,
            createdBy: PreviewConstants.userId1,
            startedAt: PreviewConstants.fixedDate,
            participants: [MockParticipantFactory.makeDriver(userId: PreviewConstants.userId1)]
        )
        overrides(&session)
        return session
    }

    static func makeCollaborativeTrip(overrides: (inout TripSession) -> Void = { _ in }) -> TripSession {
        var session = TripSession(
            id: PreviewConstants.sessionIdCollaborative,
            name: "Collaborative Trip",
            status: .active,
            mode: .multiplayer,
            createdAt: PreviewConstants.fixedDate,
            createdBy: PreviewConstants.userId1,
            startedAt: PreviewConstants.fixedDate,
            participants: [
                MockParticipantFactory.makeDriver(userId: PreviewConstants.userId1),
                MockParticipantFactory.makePassenger(userId: PreviewConstants.userId2)
            ]
        )
        overrides(&session)
        return session
    }

    static func makeCompetitiveTrip(overrides: (inout TripSession) -> Void = { _ in }) -> TripSession {
        var session = TripSession(
            id: PreviewConstants.sessionIdCompetitive,
            name: "Competitive Trip",
            status: .active,
            mode: .multiplayer,
            createdAt: PreviewConstants.fixedDate,
            createdBy: PreviewConstants.userId1,
            startedAt: PreviewConstants.fixedDate,
            participants: [
                MockParticipantFactory.makeDriver(userId: PreviewConstants.userId1),
                MockParticipantFactory.makePassenger(userId: PreviewConstants.userId2)
            ]
        )
        overrides(&session)
        return session
    }

    static func makeMultiGameTrip(overrides: (inout TripSession) -> Void = { _ in }) -> TripSession {
        var session = TripSession(
            id: PreviewConstants.sessionIdMulti,
            name: "Multi-Game Trip",
            status: .active,
            mode: .multiplayer,
            createdAt: PreviewConstants.fixedDate,
            createdBy: PreviewConstants.userId1,
            startedAt: PreviewConstants.fixedDate,
            participants: [MockParticipantFactory.makeDriver(userId: PreviewConstants.userId1)]
        )
        overrides(&session)
        return session
    }
}

// MARK: - MockGameFactory

enum MockGameFactory {
    static func makeLicensePlateGame(
        sessionId: UUID = PreviewConstants.sessionIdSolo,
        configOverrides: (inout CommonGameConfig) -> Void = { _ in }
    ) -> GameInstance {
        var config = CommonGameConfig()
        config.lifecycleState = .started
        configOverrides(&config)
        let ruleSet = GameRuleSet(gameDefinitionId: GameType.licensePlate.rawValue)
        let lpConfig = LicensePlateGameConfig(selectedCountriesRawValues: [PlateRegion.Country.unitedStates.rawValue, PlateRegion.Country.canada.rawValue, PlateRegion.Country.mexico.rawValue])
        let payloadData = try? JSONEncoder().encode(lpConfig)
        return GameInstance(
            id: PreviewConstants.gameInstanceId1,
            definitionId: GameType.licensePlate.rawValue,
            sessionId: sessionId,
            startedAt: PreviewConstants.fixedDate,
            ruleSet: ruleSet,
            commonConfig: config,
            gameSpecificPayloadType: "license_plate",
            gameSpecificPayloadVersion: "1",
            gameSpecificPayloadData: payloadData
        )
    }

    static func makeMultiGameTrip(sessionId: UUID) -> [GameInstance] {
        PreviewGameFixtures.multiGameInstances(for: sessionId)
    }
}

// MARK: - MockDiscoveryFactory

enum MockDiscoveryFactory {
    static func makeDiscovery(
        gameInstanceId: UUID = PreviewConstants.gameInstanceId1,
        participantId: String = PreviewConstants.userId1,
        overrides: (inout GameDiscovery) -> Void = { _ in }
    ) -> GameDiscovery {
        var d = GameDiscovery(
            id: PreviewConstants.discoveryId1,
            gameInstanceId: gameInstanceId,
            participantId: participantId,
            targetId: "US-CA",
            discoveredAt: PreviewConstants.fixedDate,
            inputMethod: .list
        )
        overrides(&d)
        return d
    }

    static func makeDuplicateDiscovery(
        gameInstanceId: UUID = PreviewConstants.gameInstanceId1,
        participantId: String = PreviewConstants.userId1,
        overrides: (inout GameDiscovery) -> Void = { _ in }
    ) -> GameDiscovery {
        var d = GameDiscovery(
            id: "mock-dup-discovery",
            gameInstanceId: gameInstanceId,
            participantId: participantId,
            targetId: "US-CA",
            discoveredAt: PreviewConstants.fixedDate.addingTimeInterval(60),
            inputMethod: .voice
        )
        overrides(&d)
        return d
    }

    static func makeDiscoveryWithRiskFlags(
        gameInstanceId: UUID = PreviewConstants.gameInstanceId1,
        participantId: String = PreviewConstants.userId1,
        flags: [RiskFlag]? = nil
    ) -> GameDiscovery {
        let riskFlags = flags ?? [
            RiskFlag(
                type: .rapidDiscovery,
                severity: .warning,
                source: .localHeuristic,
                presentationKey: "risk_rapid_discovery"
            )
        ]
        return GameDiscovery(
            id: PreviewConstants.discoveryId2,
            gameInstanceId: gameInstanceId,
            participantId: participantId,
            targetId: "US-TX",
            discoveredAt: PreviewConstants.fixedDate,
            inputMethod: .list,
            riskFlags: riskFlags
        )
    }
}

// MARK: - MockParticipantFactory

enum MockParticipantFactory {
    static func makeDriver(userId: String = PreviewConstants.userId1) -> TripParticipant {
        TripParticipant(
            userId: userId,
            role: .owner,
            joinedAt: PreviewConstants.fixedDate,
            teamId: nil
        )
    }

    static func makePassenger(userId: String = PreviewConstants.userId2) -> TripParticipant {
        TripParticipant(
            userId: userId,
            role: .member,
            joinedAt: PreviewConstants.fixedDate,
            teamId: nil
        )
    }
}

// MARK: - MockTeamFactory

enum MockTeamFactory {
    static func makeTwoTeams(participantUserIds: ([String], [String]) = ([PreviewConstants.userId1], [PreviewConstants.userId2])) -> [TripTeam] {
        PreviewTeamFixtures.twoTeams(participantUserIds: participantUserIds)
    }
}

// MARK: - MockCreditFactory

enum MockCreditFactory {
    static func makeCredit(
        discoveryId: String = PreviewConstants.discoveryId1,
        participantId: String = PreviewConstants.userId1,
        type: GameCreditType = .full
    ) -> GameCredit {
        GameCredit(
            discoveryId: discoveryId,
            participantId: participantId,
            creditType: type,
            weight: type == .full ? 1.0 : 0.5
        )
    }
}

// MARK: - MockTravelLogFactory

enum MockTravelLogFactory {
    static func makeTravelLogEntry(overrides: (inout TravelLogEntry) -> Void = { _ in }) -> TravelLogEntry {
        var entry = TravelLogEntry(
            id: "mock-travel-log-1",
            sessionId: PreviewConstants.sessionIdCompleted,
            tripName: "Completed Trip",
            endedAt: PreviewConstants.fixedDateEnded,
            summary: "12 regions found",
            participantCount: 1,
            gameCount: 1,
            status: .ended
        )
        overrides(&entry)
        return entry
    }

    static func makeTravelLogEntryWithSummary() -> TravelLogEntry {
        TravelLogEntry(
            id: "mock-travel-log-2",
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

// MARK: - MockInviteFactory (TripInvite is @Model — returns params for creation in ModelContext)

struct MockInviteParams {
    var inviteId: String
    var tripSessionId: String
    var tripName: String
    var tripMode: String
    var fromUserId: String
    var toUserId: String?
    var status: TripInvite.TripInviteStatus
    var createdAt: Date
    var expiresAt: Date
    var respondedAt: Date?
}

enum MockInviteFactory {
    static func makeInvite(
        status: TripInvite.TripInviteStatus = .pending,
        tripSessionId: String = PreviewConstants.sessionIdCollaborative.uuidString,
        tripName: String = "Family Road Trip",
        fromUserId: String = PreviewConstants.userId1,
        toUserId: String = PreviewConstants.userId2
    ) -> MockInviteParams {
        let createdAt = PreviewConstants.fixedDate
        let expiresAt = createdAt.addingTimeInterval(86400 * 7)
        return MockInviteParams(
            inviteId: "mock-invite-\(status.rawValue)",
            tripSessionId: tripSessionId,
            tripName: tripName,
            tripMode: TripMode.multiplayer.rawValue,
            fromUserId: fromUserId,
            toUserId: toUserId,
            status: status,
            createdAt: createdAt,
            expiresAt: expiresAt,
            respondedAt: status == .accepted ? PreviewConstants.fixedDateEnded : nil
        )
    }
}

// MARK: - MockUserFactory (AppUser is @Model — init exists; caller may insert into context)

enum MockUserFactory {
    /// Returns an AppUser with deterministic defaults. For SwiftData, insert into ModelContext when persistence is needed.
    static func makeUser(
        id: String = PreviewConstants.userId1,
        userName: String = "Preview User",
        avatarId: String? = "scout_otter"
    ) -> AppUser {
        AppUser(
            id: id,
            userName: userName,
            createdAt: PreviewConstants.fixedDate,
            lastUpdated: PreviewConstants.fixedDate,
            avatarId: avatarId
        )
    }

    static func makeSecondUser(id: String = PreviewConstants.userId2, userName: String = "Preview Passenger") -> AppUser {
        AppUser(
            id: id,
            userName: userName,
            createdAt: PreviewConstants.fixedDate,
            lastUpdated: PreviewConstants.fixedDate
        )
    }
}

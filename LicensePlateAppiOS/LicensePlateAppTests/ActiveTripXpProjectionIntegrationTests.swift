//
//  ActiveTripXpProjectionIntegrationTests.swift
//  LicensePlateAppTests
//

import Foundation
import Testing
@testable import LicensePlateApp

@MainActor
struct ActiveTripXpProjectionIntegrationTests {

    @Test func plateRowStaysFoundWhileLedgerProvisional() throws {
        let sessionId = UUID()
        let gameId = UUID()
        let uid = "user1"

        let session = TripSession(
            id: sessionId,
            name: "T",
            status: .active,
            createdAt: Date(),
            createdBy: uid,
            startedAt: Date(),
            participants: [
                TripParticipant(userId: uid, role: .owner, joinedAt: Date()),
                TripParticipant(userId: "user2", role: .member, joinedAt: Date())
            ]
        )

        let lpPayload = try JSONEncoder().encode(LicensePlateGameConfig())
        var game = GameInstance(
            id: gameId,
            definitionId: GameType.licensePlate.rawValue,
            sessionId: sessionId,
            ruleSet: GameRuleSet(gameDefinitionId: "license_plate"),
            commonConfig: CommonGameConfig(lifecycleState: .started, gameMode: .competitive),
            gameSpecificPayloadType: "license_plate",
            gameSpecificPayloadVersion: "1",
            gameSpecificPayloadData: lpPayload
        )

        let eventRepo = MockTripActivityEventRepository()
        let discoveryId = "disc-tx-1"
        let regionFound = TripActivityEvent(
            id: discoveryId,
            sessionId: sessionId,
            kind: .regionFound,
            payload: [
                TripActivityEventPayloadKey.regionId: "us-tx",
                TripActivityEventPayloadKey.gameInstanceId: gameId.uuidString,
                TripActivityEventPayloadKey.participantId: uid,
                TripActivityEventPayloadKey.inputMethod: FoundRegion.InputMethod.list.rawValue,
                TripActivityEventPayloadKey.discoveryEventId: discoveryId
            ]
        )
        try eventRepo.append(regionFound)

        let sessionRepo = MockTripSessionRepository()
        sessionRepo.seed(session)
        let gameRepo = MockGameInstanceRepository()
        gameRepo.seed(game)

        let mockLedger = MockXpLedgerRepository()
        let key = XpLedgerKeyBuilder.uniquenessKey(
            userId: uid,
            sessionId: sessionId,
            gameInstanceId: gameId,
            itemId: "us-tx",
            xpCategory: .baseRegionDiscovery
        ).storageString
        try mockLedger.append(
            XpLedgerEvent(
                userId: uid,
                sessionId: sessionId,
                gameInstanceId: gameId,
                sourceEventId: discoveryId,
                sourceEventType: TripActivityEventKind.regionFound.rawValue,
                itemId: "us-tx",
                grantKind: .provisionalDiscoveryXp,
                status: .provisional,
                xpDelta: 10,
                reasonCode: .discoveryClaimPendingResolution,
                xpUniquenessKey: key
            )
        )

        let mockRes = MockDiscoveryResolutionRepository()
        let syncCoordinator = MockSyncCoordinator()
        let recording = TripActivityEventRecordingService(tripActivityEventRepository: eventRepo, syncCoordinator: syncCoordinator)
        let gameLifecycle = GameInstanceLifecycleService(
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            tripActivityEventRecording: recording
        )
        let lifecycleService = TripSessionLifecycleService(
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            tripActivityEventRecording: recording,
            gameInstanceLifecycleService: gameLifecycle
        )
        let auth = FirebaseAuthService()
        auth.currentUser = AppUser(id: uid, userName: "U", firebaseUID: uid)

        let vm = LicensePlateGameViewModel(
            session: session,
            game: game,
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            lifecycleService: lifecycleService,
            tripActivityEventRecording: recording,
            authService: auth,
            xpLedger: mockLedger,
            discoveryResolutionRepository: mockRes
        )

        let row = vm.plateRowPresentationsByRegionId["us-tx"]
        #expect(row?.isVisuallyFound == true)
        #expect(row?.showPendingBadge == true)
        #expect(row?.detailLine == "xp.row.detail.pending_resolution".localized)
        #expect(row?.detailStyle == .pending)
        #expect(!(row?.accessibilityValue.localizedCaseInsensitiveContains("xp") ?? true))
        let projection = vm.discoveryProjectionsByItemId["us-tx"]
        #expect(projection?.xpPhase == .provisional)
    }
}

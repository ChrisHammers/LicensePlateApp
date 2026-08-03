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
        let row = try makeVMWithProvisionalFind(
            participantCount: 2,
            gameMode: .competitive,
            reasonCode: .discoveryClaimPendingResolution
        ).plateRowPresentationsByRegionId["us-tx"]

        #expect(row?.isVisuallyFound == true)
        #expect(row?.showPendingBadge == true)
        #expect(row?.detailLine == "xp.row.detail.pending_resolution".localized)
        #expect(row?.detailStyle == .pending)
        #expect(!(row?.accessibilityValue.localizedCaseInsensitiveContains("xp") ?? true))
    }

    @Test func soloPlateRowHidesPendingChromeWhileLedgerProvisional() throws {
        let vm = try makeVMWithProvisionalFind(
            participantCount: 1,
            gameMode: .competitive,
            reasonCode: .soloNewDiscovery
        )
        let row = vm.plateRowPresentationsByRegionId["us-tx"]
        let projection = vm.discoveryProjectionsByItemId["us-tx"]

        #expect(row?.isVisuallyFound == true)
        #expect(row?.showPendingBadge == false)
        #expect(row?.detailLine == nil)
        #expect(row?.detailStyle == nil)
        #expect(projection?.xpPhase == .provisional)
    }

    @Test func collaborativePlateRowHidesPendingChromeWhileLedgerProvisional() throws {
        let vm = try makeVMWithProvisionalFind(
            participantCount: 2,
            gameMode: .collaborative,
            reasonCode: .collaborativeSharedFinder
        )
        let row = vm.plateRowPresentationsByRegionId["us-tx"]
        let projection = vm.discoveryProjectionsByItemId["us-tx"]

        #expect(row?.isVisuallyFound == true)
        #expect(row?.showPendingBadge == false)
        #expect(row?.detailLine == nil)
        #expect(row?.detailStyle == nil)
        #expect(projection?.xpPhase == .provisional)
    }

    private func makeVMWithProvisionalFind(
        participantCount: Int,
        gameMode: GameMode,
        reasonCode: XpReasonCode
    ) throws -> LicensePlateGameViewModel {
        let sessionId = UUID()
        let gameId = UUID()
        let uid = "user1"

        var participants = [TripParticipant(userId: uid, role: .owner, joinedAt: Date())]
        if participantCount > 1 {
            participants.append(TripParticipant(userId: "user2", role: .member, joinedAt: Date()))
        }

        let session = TripSession(
            id: sessionId,
            name: "T",
            status: .active,
            createdAt: Date(),
            createdBy: uid,
            startedAt: Date(),
            participants: participants
        )

        let lpPayload = try JSONEncoder().encode(LicensePlateGameConfig())
        let game = GameInstance(
            id: gameId,
            definitionId: GameType.licensePlate.rawValue,
            sessionId: sessionId,
            ruleSet: GameRuleSet(gameDefinitionId: "license_plate"),
            commonConfig: CommonGameConfig(lifecycleState: .started, gameMode: gameMode),
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
                reasonCode: reasonCode,
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

        return LicensePlateGameViewModel(
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
    }
}

//
//  LateReplayOutcomeFreezeTests.swift
//  LicensePlateAppTests
//
//  COPPA FR-28h client half. The server now accepts a `region_found` replayed into an
//  already-ended game and stamps it `lateReplay`. Two client contracts follow:
//
//  1. A late replay is a real find everywhere the user sees finds, but it may not move a
//     competitive RESULT — standings are frozen at trip end.
//  2. `game not started` stopped being a permanent verdict. It is a hold, and holds must
//     not spend a row's retry budget; the two NEW replay-rejection messages are the real
//     verdicts and land terminally in `rejected`.
//

import Foundation
import FirebaseFunctions
import SwiftData
import Testing
@testable import LicensePlateApp

@MainActor
private func discovery(
    id: String,
    game: UUID,
    participant: String,
    target: String,
    at seconds: TimeInterval,
    lateReplay: Bool = false
) -> GameDiscovery {
    GameDiscovery(
        id: id,
        gameInstanceId: game,
        participantId: participant,
        targetId: target,
        discoveredAt: Date(timeIntervalSince1970: seconds),
        inputMethod: .list,
        isLateReplay: lateReplay
    )
}

// MARK: - Outcome freeze (driven through the REAL wired entry points)

@MainActor
struct CompetitiveOutcomeFreezeTests {

    private func competitiveGame(sessionId: UUID, gameId: UUID) -> GameInstance {
        var game = GameInstance(
            id: gameId,
            definitionId: "license_plate",
            sessionId: sessionId,
            startedAt: Date(timeIntervalSince1970: 1_000),
            endedAt: Date(timeIntervalSince1970: 2_000),
            ruleSet: GameRuleSet(gameDefinitionId: "license_plate")
        )
        game.commonConfig.gameMode = .competitive
        game.commonConfig.lifecycleState = .ended
        return game
    }

    private func endedSession(sessionId: UUID) -> TripSession {
        TripSession(
            id: sessionId,
            name: "Competitive Trip",
            status: .ended,
            createdAt: Date(timeIntervalSince1970: 900),
            endedAt: Date(timeIntervalSince1970: 2_000),
            participants: [
                TripParticipant(userId: "alice", role: .owner),
                TripParticipant(userId: "bob", role: .member)
            ]
        )
    }

    /// THE headline guarantee, through `TripSummaryBuilder.build` — the recap entry point
    /// the owner actually sees. Bob's late finds are timestamped EARLIER than Alice's, so
    /// under ordinary first-finder rules they would take the win.
    ///
    /// This drives the wired path end to end, so it fails if credits are rebuilt from the
    /// unfiltered set — the exact regression a credits-equivalent fixture would miss.
    @Test func theRecapWinnerIsUnchangedByLateReplays() {
        let sessionId = UUID()
        let gameId = UUID()
        let session = endedSession(sessionId: sessionId)
        let game = competitiveGame(sessionId: sessionId, gameId: gameId)

        let onTime = [
            discovery(id: "a1", game: gameId, participant: "alice", target: "CA", at: 1_500),
            discovery(id: "a2", game: gameId, participant: "alice", target: "NY", at: 1_600)
        ]
        let late = [
            discovery(id: "b1", game: gameId, participant: "bob", target: "TX", at: 1_100, lateReplay: true),
            discovery(id: "b2", game: gameId, participant: "bob", target: "OR", at: 1_150, lateReplay: true),
            discovery(id: "b3", game: gameId, participant: "bob", target: "WA", at: 1_200, lateReplay: true)
        ]

        let before = TripSummaryBuilder.build(session: session, games: [game], discoveries: onTime)
        let after = TripSummaryBuilder.build(session: session, games: [game], discoveries: onTime + late)

        #expect(before.rankedParticipants.first?.contribution.participantId == "alice")
        #expect(after.rankedParticipants.first?.contribution.participantId == "alice")
        #expect(
            before.rankedParticipants.map(\.contribution.participantId)
                == after.rankedParticipants.map(\.contribution.participantId)
        )
        // Weighted points identical, not merely the same ordering.
        #expect(
            before.rankedParticipants.map(\.contribution.weightedScore)
                == after.rankedParticipants.map(\.contribution.weightedScore)
        )
        #expect(before.rankedParticipants.map(\.rank) == after.rankedParticipants.map(\.rank))
    }

    /// The other half of the contract: the recap still SHOWS the late finds.
    @Test func theRecapStillCountsLateFindsAsDiscoveries() {
        let sessionId = UUID()
        let gameId = UUID()
        let session = endedSession(sessionId: sessionId)
        let game = competitiveGame(sessionId: sessionId, gameId: gameId)

        let onTime = [discovery(id: "a1", game: gameId, participant: "alice", target: "CA", at: 1_500)]
        let late = [discovery(id: "b1", game: gameId, participant: "bob", target: "TX", at: 1_100, lateReplay: true)]

        let after = TripSummaryBuilder.build(session: session, games: [game], discoveries: onTime + late)

        #expect(after.totalDiscoveryCount == 2, "late finds still count as finds")
    }

    /// ui-refactor-parity: with no late replays the recap behaves exactly as before.
    @Test func ordinaryCompetitivePlayIsUnaffected() {
        let sessionId = UUID()
        let gameId = UUID()
        let session = endedSession(sessionId: sessionId)
        let game = competitiveGame(sessionId: sessionId, gameId: gameId)

        let onTime = [
            discovery(id: "a1", game: gameId, participant: "alice", target: "CA", at: 1_500),
            discovery(id: "b1", game: gameId, participant: "bob", target: "TX", at: 1_100),
            discovery(id: "b2", game: gameId, participant: "bob", target: "OR", at: 1_200)
        ]
        let summary = TripSummaryBuilder.build(session: session, games: [game], discoveries: onTime)

        // Bob outscores Alice two finds to one, so Bob leads — exactly as before FR-28h.
        #expect(summary.rankedParticipants.first?.contribution.participantId == "bob")
        #expect(summary.rankedParticipants.first?.contribution.weightedScore == 2)
        #expect(summary.totalDiscoveryCount == 3)
    }

    /// `outcomeInputs` is the seam every wired site now uses: it must filter BOTH halves,
    /// because `weightedScore` comes entirely from credits.
    @Test func outcomeInputsFiltersDiscoveriesAndTheCreditsBuiltFromThem() {
        let gameId = UUID()
        let all = [
            discovery(id: "a1", game: gameId, participant: "alice", target: "CA", at: 1_500),
            discovery(id: "b1", game: gameId, participant: "bob", target: "TX", at: 1_100, lateReplay: true)
        ]

        let outcome = CompetitiveOutcomeEligibility.outcomeInputs(discoveries: all, mode: .competitive)

        #expect(outcome.discoveries.map(\.id) == ["a1"])
        #expect(outcome.credits.allSatisfy { $0.participantId == "alice" })
        #expect(!outcome.credits.contains { $0.discoveryId == "b1" })
    }
}

// MARK: - Replay flag parsing

@MainActor
struct LateReplayEventParsingTests {

    private func replay(payloadExtra: [String: String]) -> [GameDiscovery] {
        let sessionId = UUID()
        let gameId = UUID()
        var payload = [
            TripActivityEventPayloadKey.gameInstanceId: gameId.uuidString,
            TripActivityEventPayloadKey.regionId: "CA",
            TripActivityEventPayloadKey.participantId: "alice"
        ]
        payload.merge(payloadExtra) { _, new in new }
        let event = TripActivityEvent(
            id: "evt-1",
            sessionId: sessionId,
            kind: .regionFound,
            timestamp: Date(timeIntervalSince1970: 1_500),
            actorId: "alice",
            payload: payload
        )
        return TripActivityEventDiscoveryReplay.replay(events: [event], gameInstanceFilter: gameId).discoveries
    }

    @Test func theServerStampIsCarriedOntoTheDiscovery() {
        let found = replay(payloadExtra: [TripActivityEventPayloadKey.lateReplay: "true"])
        #expect(found.count == 1)
        #expect(found.first?.isLateReplay == true)
    }

    @Test func anOrdinaryFindCarriesNoStamp() {
        #expect(replay(payloadExtra: [:]).first?.isLateReplay == false)
    }

    /// Only the exact server value counts — parity with the server's own check.
    @Test func nearMissValuesAreNotTreatedAsLate() {
        for value in ["1", "yes", "TRUE", "", "false"] {
            let found = replay(payloadExtra: [TripActivityEventPayloadKey.lateReplay: value])
            #expect(found.first?.isLateReplay == false, "value=\(value)")
        }
    }
}

// MARK: - Error classification

@MainActor
struct LateReplayErrorClassificationTests {

    @MainActor
    private func makeQueue() throws -> SyncQueueRepository {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: AppMigrationPlan.self,
            configurations: [config]
        )
        let repository = SyncQueueRepository()
        repository.setModelContext(ModelContext(container))
        return repository
    }

    private func functionsError(_ message: String, code: FunctionsErrorCode = .failedPrecondition) -> NSError {
        NSError(
            domain: FunctionsErrorDomain,
            code: code.rawValue,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }

    private func drain(
        error: NSError,
        rowId: String = "row-1"
    ) async throws -> (repository: SyncQueueRepository, sessionId: UUID) {
        let repository = try makeQueue()
        let sessionId = UUID()
        try repository.enqueue(
            SyncQueueItem(
                id: rowId,
                kind: .gameplayEvent,
                state: .pending,
                attemptCount: 0,
                createdAt: .now,
                updatedAt: .now,
                payloadSessionId: sessionId.uuidString,
                payloadEventId: "evt-1"
            )
        )
        let coordinator = SyncCoordinator(repository: repository)
        coordinator.setLocalGameplayEventProvider { eventId in
            TripActivityEvent(id: eventId, sessionId: sessionId, kind: .regionFound)
        }
        coordinator.setCanonicalSessionPublisher { _ in }
        coordinator.setGameplayEventAppender { _ in throw error }
        await coordinator.processPendingSyncItems()
        return (repository, sessionId)
    }

    private func row(_ repository: SyncQueueRepository, id: String = "row-1") throws -> SyncQueueItem? {
        let failed = try repository.fetchFailedRetryDue()
        if let hit = failed.first(where: { $0.id == id }) { return hit }
        return try repository.fetchPending().first(where: { $0.id == id })
    }

    /// The regression that destroyed the owner's discoveries: this was PERMANENT, so every
    /// offline-completed trip's finds were cancelled outright. It is now a hold.
    @Test func gameNotStartedIsHeldAndSpendsNoBudget() async throws {
        let (repository, _) = try await drain(error: functionsError("game not started"))

        // Held rows are parked, so they are not retry-due yet — find it directly.
        let unrecovered = try repository.unrecoveredCancelledGameplayItems()
        #expect(unrecovered.isEmpty, "a hold must never land in the recoverable-cancel state")

        try repository.clearGameplayRetryBackoff()
        let held = try #require(try row(repository))
        #expect(held.state == .failed)
        #expect(held.attemptCount == 0, "a policy hold must not spend the retry budget")
    }

    /// The two new server verdicts are final — retrying cannot change either.
    @Test func replayVerdictsAreTerminalAndNeverRecovered() async throws {
        for message in ["replay outside game window", "replay horizon expired"] {
            let (repository, _) = try await drain(error: functionsError(message))
            #expect(try repository.fetchPending().isEmpty, "\(message)")
            #expect(try repository.fetchFailedRetryDue().isEmpty, "\(message)")
            // Terminal as `rejected`, so consent recovery never resurrects it.
            #expect(try repository.unrecoveredCancelledGameplayItems().isEmpty, "\(message)")
        }
    }

    /// A held find drains as soon as the publish catches up and the append succeeds.
    @Test func aHeldFindDrainsOnceThePublishCatchesUp() async throws {
        let repository = try makeQueue()
        let sessionId = UUID()
        try repository.enqueue(
            SyncQueueItem(
                id: "row-1",
                kind: .gameplayEvent,
                state: .pending,
                attemptCount: 0,
                createdAt: .now,
                updatedAt: .now,
                payloadSessionId: sessionId.uuidString,
                payloadEventId: "evt-1"
            )
        )
        let coordinator = SyncCoordinator(repository: repository)
        coordinator.setLocalGameplayEventProvider { eventId in
            TripActivityEvent(id: eventId, sessionId: sessionId, kind: .regionFound)
        }
        coordinator.setCanonicalSessionPublisher { _ in }

        var published = false
        coordinator.setGameplayEventAppender { _ in
            if !published {
                published = true
                throw self.functionsError("game not started")
            }
            return .accepted(lateReplay: false)
        }

        await coordinator.processPendingSyncItems()
        // Consent-style resume clears the hold's backoff; the second attempt succeeds.
        try repository.clearGameplayRetryBackoff()
        await coordinator.processPendingSyncItems()

        #expect(try repository.fetchPending().isEmpty)
        #expect(try repository.fetchFailedRetryDue().isEmpty)
        #expect(try repository.unrecoveredCancelledGameplayItems().isEmpty)
    }

    /// `game not found` keeps its own behaviour — it is the retry-capped, recoverable case.
    @Test func gameNotFoundIsStillDistinctFromGameNotStarted() async throws {
        let (repository, _) = try await drain(error: functionsError("game not found"))
        try repository.clearGameplayRetryBackoff()
        let parked = try #require(try row(repository))
        // Retry-capped path spends the budget; the hold path does not.
        #expect(parked.attemptCount == 1)
    }
}

// MARK: - G2. The previously revert-silent live-standings site

@MainActor
struct LateReplayStandingsTests {

    /// The live-standings derivation (`LicensePlateGameViewModel`) shares one rule with the
    /// recap. Nothing referenced `competitiveStandings` in tests, so the seam it now uses is
    /// pinned here directly. (Placement XP's freeze is the server's since §3.1.1 item 25 —
    /// `functions/src/progressionCore.ts`; the device no longer computes it.)
    @Test func standingsDerivationExcludesLateReplaysFromBothHalves() {
        let gameId = UUID()
        let discoveries = [
            GameDiscovery(
                id: "a1", gameInstanceId: gameId, participantId: "alice", targetId: "CA",
                discoveredAt: Date(timeIntervalSince1970: 1_500), inputMethod: .list
            ),
            GameDiscovery(
                id: "b1", gameInstanceId: gameId, participantId: "bob", targetId: "CA",
                discoveredAt: Date(timeIntervalSince1970: 1_100), inputMethod: .list,
                isLateReplay: true
            )
        ]

        let outcome = CompetitiveOutcomeEligibility.outcomeInputs(
            discoveries: discoveries,
            mode: .competitive
        )
        let ranked = TripParticipantRanking.rankContributions(
            ParticipantContributionBuilder.contributionSummary(
                discoveries: outcome.discoveries,
                credits: outcome.credits
            )
        )

        // Bob's late find is earlier on the SAME target — it would take the first-find
        // credit outright if it were eligible.
        #expect(ranked.count == 1)
        #expect(ranked.first?.contribution.participantId == "alice")
        #expect(ranked.first?.contribution.weightedScore == 1)
    }
}

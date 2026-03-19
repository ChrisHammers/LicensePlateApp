//
//  PreviewFixturesTests.swift
//  LicensePlateAppTests
//
//  Step 13 — Verify preview fixtures and mock factories build valid graphs.
//

import Foundation
import Testing
@testable import LicensePlateApp

@Suite("PreviewFixtures and MockFactories")
struct PreviewFixturesTests {

    @Test("PreviewTripFixtures build valid trips")
    func tripFixtures() {
        let solo = PreviewTripFixtures.soloTrip()
        #expect(solo.mode == .solo)
        #expect(solo.participants.count == 1)
        #expect(solo.name == "Solo Road Trip")

        let multi = PreviewTripFixtures.multiGameTrip()
        #expect(multi.mode == .multiplayer)
        #expect(multi.participants.count == 1)

        let collaborative = PreviewTripFixtures.collaborativeTrip()
        #expect(collaborative.mode == .multiplayer)
        #expect(collaborative.participants.count == 2)

        let competitive = PreviewTripFixtures.competitiveTrip()
        #expect(competitive.mode == .multiplayer)
        #expect(competitive.participants.count == 2)

        let completed = PreviewTripFixtures.completedTrip()
        #expect(completed.status == .ended)
        #expect(completed.endedAt != nil)
    }

    @Test("PreviewGameFixtures build valid game instances")
    func gameFixtures() {
        let game = PreviewGameFixtures.licensePlateGame()
        #expect(game.definitionId == GameType.licensePlate.rawValue)
        #expect(game.commonConfig.lifecycleState == .started)
        #expect(game.licensePlateConfig() != nil)

        let multi = PreviewGameFixtures.multiGameInstances(for: PreviewConstants.sessionIdMulti)
        #expect(multi.count == 3)
    }

    @Test("PreviewDiscoveryFixtures build valid discoveries")
    func discoveryFixtures() {
        let d = PreviewDiscoveryFixtures.discovery()
        #expect(d.targetId == "US-CA")
        #expect(d.inputMethod == .list)
        #expect(d.riskFlags == nil)

        let withRisk = PreviewDiscoveryFixtures.discoveryWithRiskFlag()
        #expect(withRisk.riskFlags?.isEmpty == false)
        #expect(withRisk.highestRiskSeverity == .warning)
    }

    @Test("PreviewParticipantFixtures and PreviewTeamFixtures")
    func participantAndTeamFixtures() {
        let driver = PreviewParticipantFixtures.driver()
        #expect(driver.role == .owner)
        let passenger = PreviewParticipantFixtures.passenger()
        #expect(passenger.role == .member)

        let teams = PreviewTeamFixtures.twoTeams(participantUserIds: (["u1"], ["u2"]))
        #expect(teams.count == 2)
        #expect(teams[0].participantUserIds == ["u1"])
    }

    @Test("PreviewTravelLogFixtures and PreviewSummaryFixtures")
    func travelLogAndSummaryFixtures() {
        let entry = PreviewTravelLogFixtures.travelLogEntry()
        #expect(entry.gameCount == 1)
        #expect(entry.status == .ended)

        let summary = PreviewSummaryFixtures.tripSummarySolo()
        #expect(summary.totalDiscoveryCount == 12)
        #expect(summary.games.count == 1)

        let multiSummary = PreviewSummaryFixtures.tripSummaryMultiGame()
        #expect(multiSummary.gameCount == 3)
    }

    @Test("MockFactories build complete graph")
    func mockFactoriesGraph() {
        let session = MockTripFactory.makeSoloTrip()
        let game = MockGameFactory.makeLicensePlateGame(sessionId: session.id)
        #expect(game.sessionId == session.id)

        let discovery = MockDiscoveryFactory.makeDiscovery(gameInstanceId: game.id, participantId: session.participants[0].userId)
        #expect(discovery.gameInstanceId == game.id)
        #expect(discovery.participantId == session.participants[0].userId)

        let credit = MockCreditFactory.makeCredit(discoveryId: discovery.id, participantId: discovery.participantId)
        #expect(credit.discoveryId == discovery.id)
    }

    @Test("MockInviteFactory and PreviewInviteFixtures params")
    func inviteParams() {
        let params = MockInviteFactory.makeInvite(status: .pending)
        #expect(params.status == .pending)
        #expect(params.tripSessionId.isEmpty == false)

        let pending = PreviewInviteFixturesParams.pendingInvite()
        #expect(pending.status == .pending)
        let accepted = PreviewInviteFixturesParams.acceptedInvite()
        #expect(accepted.status == .accepted)
    }

    // MARK: - MockFactoryRegistry (Step 13.5)

    @Test("MockFactoryRegistry lists all factory names and each is non-empty")
    func registryFactoryNames() {
        let names = MockFactoryRegistry.allFactoryNames
        #expect(names.isEmpty == false)
        for name in names {
            #expect(name.isEmpty == false)
        }
        #expect(names.contains("MockTripFactory"))
        #expect(names.contains("MockGameFactory"))
        #expect(names.contains("MockDiscoveryFactory"))
        #expect(names.contains("MockCreditFactory"))
    }

    @Test("MockFactoryRegistry registered factories are callable")
    func registryFactoriesCallable() {
        _ = MockTripFactory.makeSoloTrip()
        _ = MockGameFactory.makeLicensePlateGame()
        _ = MockDiscoveryFactory.makeDiscovery()
        _ = MockParticipantFactory.makeDriver()
        _ = MockTeamFactory.makeTwoTeams()
        _ = MockCreditFactory.makeCredit()
        _ = MockTravelLogFactory.makeTravelLogEntry()
        _ = MockInviteFactory.makeInvite(status: .pending)
        _ = MockUserFactory.makeUser()
    }

    @Test("MockFactoryRegistry makeFullGameplayGraph builds linked session → game → discovery → credit")
    func registryFullGraph() {
        let graph = MockFactoryRegistry.makeFullGameplayGraph()
        #expect(graph.game.sessionId == graph.session.id)
        #expect(graph.discovery.gameInstanceId == graph.game.id)
        #expect(graph.discovery.participantId == graph.session.participants[0].userId)
        #expect(graph.credit.discoveryId == graph.discovery.id)
        #expect(graph.credit.participantId == graph.discovery.participantId)
    }
}

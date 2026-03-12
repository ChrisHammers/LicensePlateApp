//
//  MockFactoryRegistry.swift
//  LicensePlateApp
//
//  Step 13.5 — Registry of mock factories for discoverability and validation. Use PreviewConstants, Preview*Fixtures, or Mock*Factory in previews so data stays deterministic and consistent with tests.
//

import Foundation

/// Registry of all mock factory names. Tests can iterate this list to verify each factory exists and is callable.
/// Previews and tests should use these factories (or Preview*Fixtures) so data stays deterministic.
enum MockFactoryRegistry {
    static let allFactoryNames: [String] = [
        "MockTripFactory",
        "MockGameFactory",
        "MockDiscoveryFactory",
        "MockParticipantFactory",
        "MockTeamFactory",
        "MockCreditFactory",
        "MockTravelLogFactory",
        "MockInviteFactory",
        "MockUserFactory"
    ]

    /// Builds a full gameplay graph (session → game → discovery → credit) using existing mock factories.
    /// Uses PreviewConstants for deterministic IDs. Use in previews and tests for a single-call graph.
    struct FullGameplayGraph {
        let session: TripSession
        let game: GameInstance
        let discovery: GameDiscovery
        let credit: GameCredit
    }

    static func makeFullGameplayGraph(
        sessionOverrides: (inout TripSession) -> Void = { _ in },
        gameConfigOverrides: (inout CommonGameConfig) -> Void = { _ in },
        discoveryOverrides: (inout GameDiscovery) -> Void = { _ in }
    ) -> FullGameplayGraph {
        var session = MockTripFactory.makeSoloTrip(overrides: sessionOverrides)
        var game = MockGameFactory.makeLicensePlateGame(sessionId: session.id, configOverrides: gameConfigOverrides)
        var discovery = MockDiscoveryFactory.makeDiscovery(
            gameInstanceId: game.id,
            participantId: session.participants[0].userId,
            overrides: discoveryOverrides
        )
        let credit = MockCreditFactory.makeCredit(
            discoveryId: discovery.id,
            participantId: discovery.participantId
        )
        return FullGameplayGraph(session: session, game: game, discovery: discovery, credit: credit)
    }
}

//
//  DiscoveryLocationPayloadTests.swift
//  LicensePlateAppTests
//
//  GPS Step 4 — location at plate find: LocationData payload round-trip, replay
//  population of foundAtLocation, and the ViewModel gate (setting + staleness).
//

import Foundation
import CoreLocation
import Testing
@testable import LicensePlateApp

// MARK: - LocationData payload round-trip (pure)

struct LocationDataPayloadTests {

    @Test func payloadFieldsRoundTripThroughInit() {
        let original = LocationData(from: CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090),
            altitude: 12.5,
            horizontalAccuracy: 8,
            verticalAccuracy: 4,
            timestamp: Date(timeIntervalSince1970: 1_750_000_000)
        ))
        let decoded = LocationData(payload: original.payloadFields())
        #expect(decoded != nil)
        #expect(decoded?.latitude == original.latitude)
        #expect(decoded?.longitude == original.longitude)
        #expect(decoded?.altitude == original.altitude)
        #expect(decoded?.horizontalAccuracy == original.horizontalAccuracy)
        #expect(decoded?.verticalAccuracy == original.verticalAccuracy)
        #expect(decoded?.timestamp == original.timestamp)
    }

    @Test func initNilWhenCoordinatesMissingOrMalformed() {
        #expect(LocationData(payload: nil) == nil)
        #expect(LocationData(payload: [:]) == nil)
        #expect(LocationData(payload: [TripActivityEventPayloadKey.locationLatitude: "37.0"]) == nil)
        #expect(LocationData(payload: [
            TripActivityEventPayloadKey.locationLatitude: "not-a-number",
            TripActivityEventPayloadKey.locationLongitude: "-122.0"
        ]) == nil)
    }
}

/// Field-wise comparison (LocationData is not Equatable in the app module).
func locationDataEqual(_ lhs: LocationData?, _ rhs: LocationData?) -> Bool {
    guard let lhs, let rhs else { return lhs == nil && rhs == nil }
    return lhs.latitude == rhs.latitude
        && lhs.longitude == rhs.longitude
        && lhs.altitude == rhs.altitude
        && lhs.horizontalAccuracy == rhs.horizontalAccuracy
        && lhs.verticalAccuracy == rhs.verticalAccuracy
        && lhs.timestamp == rhs.timestamp
}

// MARK: - Replay populates foundAtLocation (pure)

struct DiscoveryReplayLocationTests {

    private func regionFoundEvent(sessionId: UUID, gameId: UUID, payloadExtras: [String: String] = [:]) -> TripActivityEvent {
        var payload: [String: String] = [
            TripActivityEventPayloadKey.regionId: "us-ca",
            TripActivityEventPayloadKey.gameInstanceId: gameId.uuidString,
            TripActivityEventPayloadKey.participantId: "u1",
            TripActivityEventPayloadKey.inputMethod: FoundRegion.InputMethod.list.rawValue
        ]
        payload.merge(payloadExtras) { _, new in new }
        return TripActivityEvent(sessionId: sessionId, kind: .regionFound, actorId: "u1", payload: payload)
    }

    @Test func replayPopulatesLocationFromPayloadKeys() {
        let sessionId = UUID()
        let gameId = UUID()
        let fix = LocationData(from: CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 44.97, longitude: -93.26),
            altitude: 250,
            horizontalAccuracy: 10,
            verticalAccuracy: 6,
            timestamp: Date(timeIntervalSince1970: 1_751_000_000)
        ))
        let event = regionFoundEvent(sessionId: sessionId, gameId: gameId, payloadExtras: fix.payloadFields())

        let result = TripActivityEventDiscoveryReplay.replay(events: [event], gameInstanceFilter: gameId)

        #expect(locationDataEqual(result.discoveries.first?.location, fix))
        #expect(locationDataEqual(result.foundRegions.first?.foundAtLocation, fix))
    }

    @Test func replayLeavesLocationNilWhenKeysAbsent() {
        let sessionId = UUID()
        let gameId = UUID()
        let event = regionFoundEvent(sessionId: sessionId, gameId: gameId)

        let result = TripActivityEventDiscoveryReplay.replay(events: [event], gameInstanceFilter: gameId)

        #expect(result.discoveries.first != nil)
        #expect(result.discoveries.first?.location == nil)
        #expect(result.foundRegions.first?.foundAtLocation == nil)
    }
}

// MARK: - ViewModel gate (setting + staleness; find never blocked)

@MainActor
struct DiscoveryLocationGateTests {

    private final class StubLocationSettings: LocationSettingsProviding {
        var saveLocationWhenMarkingPlates: Bool
        var showMyLocationOnLargeMap = true
        var trackMyLocationDuringTrips = true
        init(saveLocationWhenMarkingPlates: Bool) {
            self.saveLocationWhenMarkingPlates = saveLocationWhenMarkingPlates
        }
    }

    @Test func warmCacheFiresOnlyWhenSettingOn() {
        var warmCount = 0
        let eventRepo = MockTripActivityEventRepository()
        let viewModelOn = makeViewModel(
            saveLocationSetting: true, fix: nil, eventRepo: eventRepo,
            warmLocationFix: { warmCount += 1 }
        )
        viewModelOn.warmDiscoveryLocationCacheIfNeeded()
        #expect(warmCount == 1)
        _ = viewModelOn.submitDiscovery(regionID: "us-wy", inputMethod: .list)
        #expect(warmCount == 2)

        var warmCountOff = 0
        let viewModelOff = makeViewModel(
            saveLocationSetting: false, fix: nil, eventRepo: MockTripActivityEventRepository(),
            warmLocationFix: { warmCountOff += 1 }
        )
        viewModelOff.warmDiscoveryLocationCacheIfNeeded()
        _ = viewModelOff.submitDiscovery(regionID: "us-wy", inputMethod: .list)
        #expect(warmCountOff == 0)
    }

    private func makeViewModel(
        saveLocationSetting: Bool,
        fix: CLLocation?,
        eventRepo: MockTripActivityEventRepository,
        warmLocationFix: @escaping @MainActor () -> Void = {}
    ) -> LicensePlateGameViewModel {
        let sessionId = UUID()
        let gameId = UUID()
        let session = TripSession(
            id: sessionId,
            name: "T",
            status: .active,
            createdAt: Date(),
            createdBy: "u1",
            startedAt: Date(),
            participants: []
        )
        let game = GameInstance(
            id: gameId,
            definitionId: GameType.licensePlate.rawValue,
            sessionId: sessionId,
            ruleSet: GameRuleSet(gameDefinitionId: "license_plate"),
            commonConfig: CommonGameConfig(lifecycleState: .started, configLocked: true, configLockReason: .gameStarted)
        )
        let sessionRepo = MockTripSessionRepository()
        sessionRepo.seed(session)
        let gameRepo = MockGameInstanceRepository()
        gameRepo.seed(game)
        let auth = FirebaseAuthService()
        auth.currentUser = AppUser(id: "u1", userName: "U", firebaseUID: "u1")

        return LicensePlateGameViewModel(
            session: session,
            game: game,
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            lifecycleService: MockTripSessionLifecycleService(),
            gameInstanceLifecycleService: MockGameInstanceLifecycleService(),
            tripActivityEventRecording: TripActivityEventRecordingService(
                tripActivityEventRepository: eventRepo,
                syncCoordinator: MockSyncCoordinator()
            ),
            authService: auth,
            locationSettings: StubLocationSettings(saveLocationWhenMarkingPlates: saveLocationSetting),
            currentLocationFix: { fix },
            warmLocationFix: warmLocationFix
        )
    }

    private func freshFix() -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 40.0, longitude: -105.0),
            altitude: 1600,
            horizontalAccuracy: 5,
            verticalAccuracy: 3,
            timestamp: Date()
        )
    }

    private func recordedRegionFoundPayload(_ eventRepo: MockTripActivityEventRepository) -> [String: String]? {
        eventRepo.appendedEvents().first { $0.kind == .regionFound }?.payload
    }

    @Test func settingOnFreshFixAttachesLocationKeys() {
        let eventRepo = MockTripActivityEventRepository()
        let viewModel = makeViewModel(saveLocationSetting: true, fix: freshFix(), eventRepo: eventRepo)

        let result = viewModel.submitDiscovery(regionID: "us-co", inputMethod: .list)

        guard case .success = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        let payload = recordedRegionFoundPayload(eventRepo)
        #expect(payload?[TripActivityEventPayloadKey.locationLatitude] == "40.0")
        #expect(payload?[TripActivityEventPayloadKey.locationLongitude] == "-105.0")
        #expect(LocationData(payload: payload) != nil)
    }

    @Test func settingOffOmitsLocationKeysAndFindSucceeds() {
        let eventRepo = MockTripActivityEventRepository()
        let viewModel = makeViewModel(saveLocationSetting: false, fix: freshFix(), eventRepo: eventRepo)

        let result = viewModel.submitDiscovery(regionID: "us-co", inputMethod: .list)

        guard case .success = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        let payload = recordedRegionFoundPayload(eventRepo)
        #expect(payload?[TripActivityEventPayloadKey.locationLatitude] == nil)
        #expect(LocationData(payload: payload) == nil)
    }

    @Test func staleFixOmitsLocationKeysAndFindSucceeds() {
        let staleFix = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 40.0, longitude: -105.0),
            altitude: 1600,
            horizontalAccuracy: 5,
            verticalAccuracy: 3,
            timestamp: Date(timeIntervalSinceNow: -300)
        )
        let eventRepo = MockTripActivityEventRepository()
        let viewModel = makeViewModel(saveLocationSetting: true, fix: staleFix, eventRepo: eventRepo)

        let result = viewModel.submitDiscovery(regionID: "us-co", inputMethod: .list)

        guard case .success = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(recordedRegionFoundPayload(eventRepo)?[TripActivityEventPayloadKey.locationLatitude] == nil)
    }

    @Test func missingFixOmitsLocationKeysAndFindSucceeds() {
        let eventRepo = MockTripActivityEventRepository()
        let viewModel = makeViewModel(saveLocationSetting: true, fix: nil, eventRepo: eventRepo)

        let result = viewModel.submitDiscovery(regionID: "us-co", inputMethod: .list)

        guard case .success = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(recordedRegionFoundPayload(eventRepo)?[TripActivityEventPayloadKey.locationLatitude] == nil)
    }
}

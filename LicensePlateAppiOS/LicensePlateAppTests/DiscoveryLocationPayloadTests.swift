//
//  DiscoveryLocationPayloadTests.swift
//  LicensePlateAppTests
//
//  GPS Step 4 — location at plate find: LocationData payload round-trip, replay
//  population of foundAtLocation, and the ViewModel gate (setting + staleness).
//
//  COPPA remediation F-4 / FR-45 — also pins the shared-payload precision contract:
//  latitude/longitude rounded to 3 decimals (~110 m), altitude and horizontal/vertical
//  accuracy never written, timestamp kept.
//

import Foundation
import CoreLocation
import Testing
@testable import LicensePlateApp

// MARK: - LocationData payload round-trip (pure)

struct LocationDataPayloadTests {

    private static let sampleFix = LocationData(from: CLLocation(
        coordinate: CLLocationCoordinate2D(latitude: 37.334899, longitude: -122.009056),
        altitude: 12.5,
        horizontalAccuracy: 8,
        verticalAccuracy: 4,
        timestamp: Date(timeIntervalSince1970: 1_750_000_000)
    ))

    /// COPPA F-4 / FR-45: shared coordinates are rounded to 3 dp (~110 m).
    @Test func payloadRoundsCoordinatesToThreeDecimals() {
        let fields = Self.sampleFix.payloadFields()
        #expect(fields[TripActivityEventPayloadKey.locationLatitude] == "37.335")
        #expect(fields[TripActivityEventPayloadKey.locationLongitude] == "-122.009")
    }

    /// Rounding is nearest, not truncation, and survives the negative hemisphere.
    @Test func coarsenedCoordinateRoundsToNearest() {
        #expect(LocationData.payloadCoordinateDecimalPlaces == 3)
        #expect(LocationData.coarsenedCoordinate(40.0) == 40.0)
        #expect(LocationData.coarsenedCoordinate(40.1234) == 40.123)
        #expect(LocationData.coarsenedCoordinate(40.1236) == 40.124)
        #expect(LocationData.coarsenedCoordinate(-105.98765) == -105.988)
    }

    /// Altitude and both accuracy figures are dropped at write time — they are never uploaded.
    @Test func payloadOmitsAltitudeAndAccuracyKeys() {
        let fields = Self.sampleFix.payloadFields()
        #expect(fields[TripActivityEventPayloadKey.locationAltitude] == nil)
        #expect(fields[TripActivityEventPayloadKey.locationHorizontalAccuracy] == nil)
        #expect(fields[TripActivityEventPayloadKey.locationVerticalAccuracy] == nil)
        #expect(Set(fields.keys) == [
            TripActivityEventPayloadKey.locationLatitude,
            TripActivityEventPayloadKey.locationLongitude,
            TripActivityEventPayloadKey.locationTimestamp
        ])
    }

    /// Decode still works with the dropped keys absent; they take the defensive defaults.
    @Test func payloadFieldsRoundTripThroughInit() {
        let original = Self.sampleFix
        let decoded = LocationData(payload: original.payloadFields())
        #expect(decoded != nil)
        #expect(decoded?.latitude == LocationData.coarsenedCoordinate(original.latitude))
        #expect(decoded?.longitude == LocationData.coarsenedCoordinate(original.longitude))
        #expect(decoded?.altitude == 0)
        #expect(decoded?.horizontalAccuracy == -1)
        #expect(decoded?.verticalAccuracy == -1)
        #expect(decoded?.timestamp == original.timestamp)
    }

    /// Events written before the precision change still decode their legacy keys.
    @Test func initStillReadsLegacyAltitudeAndAccuracyKeys() {
        let decoded = LocationData(payload: [
            TripActivityEventPayloadKey.locationLatitude: "37.335",
            TripActivityEventPayloadKey.locationLongitude: "-122.009",
            TripActivityEventPayloadKey.locationAltitude: "12.5",
            TripActivityEventPayloadKey.locationHorizontalAccuracy: "8.0",
            TripActivityEventPayloadKey.locationVerticalAccuracy: "4.0"
        ])
        #expect(decoded?.altitude == 12.5)
        #expect(decoded?.horizontalAccuracy == 8.0)
        #expect(decoded?.verticalAccuracy == 4.0)
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
            coordinate: CLLocationCoordinate2D(latitude: 44.9724567, longitude: -93.2634567),
            altitude: 250,
            horizontalAccuracy: 10,
            verticalAccuracy: 6,
            timestamp: Date(timeIntervalSince1970: 1_751_000_000)
        ))
        let event = regionFoundEvent(sessionId: sessionId, gameId: gameId, payloadExtras: fix.payloadFields())

        let result = TripActivityEventDiscoveryReplay.replay(events: [event], gameInstanceFilter: gameId)

        // What replay can recover is the coarse fix, not the original one.
        let expected = LocationData(payload: fix.payloadFields())
        #expect(locationDataEqual(result.discoveries.first?.location, expected))
        #expect(locationDataEqual(result.foundRegions.first?.foundAtLocation, expected))
        #expect(result.discoveries.first?.location?.latitude == 44.972)
        #expect(result.discoveries.first?.location?.longitude == -93.263)
        #expect(result.discoveries.first?.location?.timestamp == fix.timestamp)
        #expect(result.discoveries.first?.location?.horizontalAccuracy == -1)
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

    private func freshFix(
        latitude: CLLocationDegrees = 40.0,
        longitude: CLLocationDegrees = -105.0
    ) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
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

    /// The recorded event carries a coarse fix and no altitude/accuracy, even though the
    /// capture-side check reads `horizontalAccuracy` to decide the fix is usable at all.
    @Test func recordedPayloadIsCoarseAndOmitsAltitudeAndAccuracy() {
        let eventRepo = MockTripActivityEventRepository()
        let viewModel = makeViewModel(
            saveLocationSetting: true,
            fix: freshFix(latitude: 40.0189234, longitude: -105.2705678),
            eventRepo: eventRepo
        )

        _ = viewModel.submitDiscovery(regionID: "us-co", inputMethod: .list)

        let payload = recordedRegionFoundPayload(eventRepo)
        #expect(payload?[TripActivityEventPayloadKey.locationLatitude] == "40.019")
        #expect(payload?[TripActivityEventPayloadKey.locationLongitude] == "-105.271")
        #expect(payload?[TripActivityEventPayloadKey.locationAltitude] == nil)
        #expect(payload?[TripActivityEventPayloadKey.locationHorizontalAccuracy] == nil)
        #expect(payload?[TripActivityEventPayloadKey.locationVerticalAccuracy] == nil)
        #expect(payload?[TripActivityEventPayloadKey.locationTimestamp] != nil)
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

    /// Warm-cadence invariant: a fix refreshed at one periodic tick must still be inside the
    /// 60 s capture window at the NEXT tick, including the refresh-threshold age it may already
    /// carry and one-shot GPS latency (budgeted 5 s). With threshold == interval (the old bug),
    /// every other tick skipped its refresh, leaving a recurring ~30 s window where finds on
    /// non-map tabs (voice, list) silently dropped location.
    @Test func locationWarmCadenceKeepsFixInsideCaptureWindow() {
        let oneShotLatencyBudget: TimeInterval = 5
        let maxCaptureAge: TimeInterval = 60 // LicensePlateGameViewModel.maxLocationFixAgeForDiscovery (private)
        #expect(
            LicensePlateGameViewModel.locationWarmRefreshThreshold
                + LicensePlateGameViewModel.locationWarmInterval
                + oneShotLatencyBudget <= maxCaptureAge
        )
        #expect(LicensePlateGameViewModel.locationWarmRefreshThreshold < LicensePlateGameViewModel.locationWarmInterval)
    }
}

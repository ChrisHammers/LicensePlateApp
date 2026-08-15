//
//  TripRouteTrackingServiceTests.swift
//  LicensePlateAppTests
//
//  GPS Step 6 — capture gating (trip active + setting + authorization) and
//  min-distance point appending, via the injectable location source seam.
//

import Foundation
import Combine
import CoreLocation
import Testing
@testable import LicensePlateApp

@MainActor
struct TripRouteTrackingServiceTests {

    private final class FakeLocationSource: RouteTrackingLocationSource {
        let subject = PassthroughSubject<CLLocation?, Never>()
        let authorizationSubject = CurrentValueSubject<Bool, Never>(true)
        var locationPublisher: AnyPublisher<CLLocation?, Never> { subject.eraseToAnyPublisher() }
        var locationAuthorizationPublisher: AnyPublisher<Bool, Never> {
            authorizationSubject.eraseToAnyPublisher()
        }
        var isAuthorizedForLocation = true {
            didSet { authorizationSubject.send(isAuthorizedForLocation) }
        }
        private(set) var beginCount = 0
        private(set) var endCount = 0
        func beginRouteTracking() { beginCount += 1 }
        func endRouteTracking() { endCount += 1 }
    }

    private func makeService(
        source: FakeLocationSource,
        track: Bool,
        userId: String = "user-a",
        childRestricted: Bool = false
    ) -> (TripRouteTrackingService, UUID) {
        let sessionId = UUID()
        let prefsStore = TripParticipantPrefsStore(
            defaults: UserDefaults(suiteName: "test.route.\(UUID().uuidString)")!
        )
        prefsStore.apply(
            sessionId: sessionId,
            userId: userId,
            prefs: TripParticipantPrefs(
                skipVoiceConfirmation: false,
                saveLocationWhenMarkingPlates: true,
                showMyLocationOnLargeMap: true,
                trackMyLocationDuringTrip: track,
                source: .seededFromAccountDefaults
            )
        )
        let privacy = UserDefaults(suiteName: "test.route.privacy.\(UUID().uuidString)")!
        LocationSettingsBootstrap.registerFactoryDefaults(using: privacy)
        let resolver = EffectiveSettingsResolver(
            privacyDefaults: privacy,
            prefsStore: prefsStore,
            childRestriction: .fixed(childRestricted)
        )
        let service = TripRouteTrackingService(locationSource: source, resolver: resolver)
        return (service, sessionId)
    }

    private func fix(lat: Double, lon: Double, accuracy: Double = 10) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            altitude: 0,
            horizontalAccuracy: accuracy,
            verticalAccuracy: 5,
            timestamp: Date()
        )
    }

    @Test func startsCaptureWhenTripActiveSettingOnAuthorized() {
        let source = FakeLocationSource()
        let (service, sessionId) = makeService(source: source, track: true)

        service.tripDidStart(sessionId: sessionId, viewerUserId: "user-a")

        #expect(service.isCapturing == true)
        #expect(source.beginCount == 1)
    }

    @Test func doesNotCaptureWhenSettingOff() {
        let source = FakeLocationSource()
        let (service, sessionId) = makeService(source: source, track: false)

        service.tripDidStart(sessionId: sessionId, viewerUserId: "user-a")

        #expect(service.isCapturing == false)
        #expect(source.beginCount == 0)
    }

    @Test func doesNotCaptureWhenUnauthorized() {
        let source = FakeLocationSource()
        source.isAuthorizedForLocation = false
        let (service, sessionId) = makeService(source: source, track: true)

        service.tripDidStart(sessionId: sessionId, viewerUserId: "user-a")

        #expect(service.isCapturing == false)
    }

    @Test func startsCaptureWhenAuthorizationBecomesGranted() async {
        let source = FakeLocationSource()
        source.isAuthorizedForLocation = false
        let (service, sessionId) = makeService(source: source, track: true)
        service.tripDidStart(sessionId: sessionId, viewerUserId: "user-a")
        #expect(service.isCapturing == false)

        source.isAuthorizedForLocation = true
        await Task.yield()

        #expect(service.isCapturing == true)
        #expect(source.beginCount == 1)
    }

    @Test func stopsCaptureAndClearsSessionOnTripEnd() {
        let source = FakeLocationSource()
        let (service, sessionId) = makeService(source: source, track: true)

        service.tripDidStart(sessionId: sessionId, viewerUserId: "user-a")
        #expect(service.isCapturing == true)

        service.tripDidEnd(sessionId: sessionId)
        #expect(service.isCapturing == false)
        #expect(service.activeTripSessionId == nil)
        #expect(source.endCount == 1)
    }

    @Test func appendsPointsWhenCapturing() {
        let source = FakeLocationSource()
        let (service, sessionId) = makeService(source: source, track: true)
        service.tripDidStart(sessionId: sessionId, viewerUserId: "user-a")

        source.subject.send(fix(lat: 1, lon: 1))
        #expect(service.routePoints.count == 1)
    }

    @Test func dropsPointsCloserThanMinimumSeparation() {
        let source = FakeLocationSource()
        let (service, sessionId) = makeService(source: source, track: true)
        service.tripDidStart(sessionId: sessionId, viewerUserId: "user-a")

        source.subject.send(fix(lat: 37.0, lon: -122.0))
        source.subject.send(fix(lat: 37.00001, lon: -122.0))
        #expect(service.routePoints.count == 1)
    }

    @Test func doesNotAppendWhenNotCapturing() {
        let source = FakeLocationSource()
        let (service, sessionId) = makeService(source: source, track: false)
        service.tripDidStart(sessionId: sessionId, viewerUserId: "user-a")

        source.subject.send(fix(lat: 1, lon: 1))
        #expect(service.routePoints.isEmpty)
    }

    @Test func restartSameSessionKeepsPoints() {
        let source = FakeLocationSource()
        let (service, sessionId) = makeService(source: source, track: true)
        service.tripDidStart(sessionId: sessionId, viewerUserId: "user-a")
        source.subject.send(fix(lat: 1, lon: 1))
        #expect(service.routePoints.count == 1)

        service.tripDidStart(sessionId: sessionId, viewerUserId: "user-a")
        #expect(service.routePoints.count == 1)

        service.tripDidStart(sessionId: UUID(), viewerUserId: "user-a")
        #expect(service.routePoints.isEmpty)
    }

    /// COPPA F-31 (FR-75a): the child signal is ANDed inside the resolver, so a restricted
    /// session never begins capture even with the trip active, the setting on and the OS
    /// authorization already granted.
    @Test func childRestrictedSessionNeverCapturesDespiteSettingOnAndAuthorization() {
        let source = FakeLocationSource()
        let (service, sessionId) = makeService(source: source, track: true, childRestricted: true)

        service.tripDidStart(sessionId: sessionId, viewerUserId: "user-a")

        #expect(service.isCapturing == false)
        #expect(source.beginCount == 0)
        source.subject.send(fix(lat: 1, lon: 1))
        #expect(service.routePoints.isEmpty)
    }
}

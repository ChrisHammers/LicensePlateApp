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
        var locationPublisher: AnyPublisher<CLLocation?, Never> { subject.eraseToAnyPublisher() }
        var isAuthorizedForLocation = true
        private(set) var beginCount = 0
        private(set) var endCount = 0
        func beginRouteTracking() { beginCount += 1 }
        func endRouteTracking() { endCount += 1 }
    }

    private final class StubSettings: LocationSettingsProviding {
        var saveLocationWhenMarkingPlates = true
        var showMyLocationOnLargeMap = true
        var trackMyLocationDuringTrips: Bool
        init(track: Bool) { trackMyLocationDuringTrips = track }
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
        let service = TripRouteTrackingService(locationSource: source, settings: StubSettings(track: true))

        service.tripDidStart(sessionId: UUID())

        #expect(service.isCapturing == true)
        #expect(source.beginCount == 1)
    }

    @Test func doesNotCaptureWhenSettingOff() {
        let source = FakeLocationSource()
        let service = TripRouteTrackingService(locationSource: source, settings: StubSettings(track: false))

        service.tripDidStart(sessionId: UUID())

        #expect(service.isCapturing == false)
        #expect(source.beginCount == 0)
    }

    @Test func doesNotCaptureWhenUnauthorized() {
        let source = FakeLocationSource()
        source.isAuthorizedForLocation = false
        let service = TripRouteTrackingService(locationSource: source, settings: StubSettings(track: true))

        service.tripDidStart(sessionId: UUID())

        #expect(service.isCapturing == false)
    }

    @Test func stopsCaptureAndClearsSessionOnTripEnd() {
        let source = FakeLocationSource()
        let service = TripRouteTrackingService(locationSource: source, settings: StubSettings(track: true))
        let sessionId = UUID()

        service.tripDidStart(sessionId: sessionId)
        service.tripDidEnd(sessionId: sessionId)

        #expect(service.isCapturing == false)
        #expect(service.activeTripSessionId == nil)
        #expect(source.endCount == 1)
    }

    @Test func tripEndForDifferentSessionIsIgnored() {
        let source = FakeLocationSource()
        let service = TripRouteTrackingService(locationSource: source, settings: StubSettings(track: true))

        service.tripDidStart(sessionId: UUID())
        service.tripDidEnd(sessionId: UUID())

        #expect(service.isCapturing == true)
    }

    @Test func appendsOnlyPointsBeyondMinimumSeparation() {
        let source = FakeLocationSource()
        let service = TripRouteTrackingService(locationSource: source, settings: StubSettings(track: true))
        service.tripDidStart(sessionId: UUID())

        source.subject.send(fix(lat: 39.7500, lon: -104.9900))
        // ~11 m north of the first point — below the 50 m separation, dropped
        source.subject.send(fix(lat: 39.7501, lon: -104.9900))
        // ~1.1 km north — kept
        source.subject.send(fix(lat: 39.7600, lon: -104.9900))

        #expect(service.routePoints.count == 2)
    }

    @Test func ignoresInvalidAccuracyAndNilFixes() {
        let source = FakeLocationSource()
        let service = TripRouteTrackingService(locationSource: source, settings: StubSettings(track: true))
        service.tripDidStart(sessionId: UUID())

        source.subject.send(nil)
        source.subject.send(fix(lat: 39.75, lon: -104.99, accuracy: -1))

        #expect(service.routePoints.isEmpty)
    }

    @Test func restartingSameTripKeepsPoints_newTripClearsThem() {
        let source = FakeLocationSource()
        let service = TripRouteTrackingService(locationSource: source, settings: StubSettings(track: true))
        let sessionId = UUID()
        service.tripDidStart(sessionId: sessionId)
        source.subject.send(fix(lat: 39.75, lon: -104.99))
        #expect(service.routePoints.count == 1)

        service.tripDidStart(sessionId: sessionId)
        #expect(service.routePoints.count == 1)

        service.tripDidEnd(sessionId: sessionId)
        service.tripDidStart(sessionId: UUID())
        #expect(service.routePoints.isEmpty)
    }
}

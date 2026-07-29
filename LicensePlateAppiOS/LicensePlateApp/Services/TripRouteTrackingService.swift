//
//  TripRouteTrackingService.swift
//  LicensePlateApp
//
//  GPS Step 6 — owns route capture for the active trip. Starts when a trip becomes
//  active AND the effective "Track my location during trips" setting is on AND location
//  is authorized; stops on trip end/cancel or toggle-off. Points are per-device telemetry,
//  not gameplay events — they never enter the TripActivityEvent log or sync to trip docs.
//  Privacy: coordinates stay in-process; never log them or pass them to AnalyticsService.
//

import Foundation
import Combine
import CoreLocation

/// Location source seam so gating/appending logic is unit-testable without CoreLocation.
@MainActor
protocol RouteTrackingLocationSource: AnyObject {
    var locationPublisher: AnyPublisher<CLLocation?, Never> { get }
    var isAuthorizedForLocation: Bool { get }
    func beginRouteTracking()
    func endRouteTracking()
}

@MainActor
final class TripRouteTrackingService: ObservableObject {

    static let shared = TripRouteTrackingService()

    /// Points closer than this to the previous kept point are dropped (ribbon granularity).
    static let minimumPointSeparationMeters: CLLocationDistance = 50

    @Published private(set) var routePoints: [CLLocation] = []
    @Published private(set) var activeTripSessionId: UUID?
    @Published private(set) var isCapturing = false

    /// Points are persisted in batches of this size (plus a final flush on stop).
    static let persistenceBatchSize = 10

    private let locationSource: RouteTrackingLocationSource
    private let resolver: EffectiveSettingsResolver
    private var viewerUserId: String?
    private let repository: TripRoutePointRepository
    private var locationCancellable: AnyCancellable?
    private var settingsCancellable: AnyCancellable?
    private var unpersistedPoints: [CLLocation] = []

    init(
        locationSource: RouteTrackingLocationSource = LocationManager.shared,
        resolver: EffectiveSettingsResolver = .shared,
        repository: TripRoutePointRepository = .shared
    ) {
        self.locationSource = locationSource
        self.resolver = resolver
        self.repository = repository
        settingsCancellable = resolver.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.evaluateCapture()
            }
    }

    // MARK: - Lifecycle hooks (called by TripSessionLifecycleService / ViewModel resume)

    func tripDidStart(sessionId: UUID, viewerUserId: String? = nil) {
        if let viewerUserId, !viewerUserId.isEmpty {
            self.viewerUserId = viewerUserId
        }
        if activeTripSessionId != sessionId {
            activeTripSessionId = sessionId
            unpersistedPoints = []
            // GPS Step 7 — restore persisted points so the ribbon survives relaunch.
            routePoints = (try? repository.points(tripSessionId: sessionId)) ?? []
        }
        evaluateCapture()
    }

    /// Resume after app relaunch: the lifecycle start hook never fired in this process.
    func resumeIfActive(session: TripSession, viewerUserId: String? = nil) {
        guard session.status == .active else { return }
        tripDidStart(sessionId: session.id, viewerUserId: viewerUserId)
    }

    func tripDidEnd(sessionId: UUID) {
        guard activeTripSessionId == sessionId else { return }
        stopCapture()
        activeTripSessionId = nil
    }

    /// Cancel is a soft delete of the trip's local data — drop its route too (GPS Step 7).
    func tripWasCancelled(sessionId: UUID) {
        tripDidEnd(sessionId: sessionId)
        try? repository.deletePoints(tripSessionId: sessionId)
        routePoints = []
    }

    /// Hard sign-out: stop capture without flushing points (store is about to be wiped).
    func stopForAccountPurge() {
        locationCancellable = nil
        if isCapturing {
            isCapturing = false
            locationSource.endRouteTracking()
        }
        unpersistedPoints = []
        routePoints = []
        activeTripSessionId = nil
    }

    // MARK: - Capture

    private func evaluateCapture() {
        guard let sessionId = activeTripSessionId, let userId = viewerUserId, !userId.isEmpty else {
            if isCapturing { stopCapture() }
            return
        }
        let track = resolver.resolve(sessionId: sessionId, userId: userId).trackMyLocationDuringTrips
        let shouldCapture = track && locationSource.isAuthorizedForLocation
        if shouldCapture && !isCapturing {
            startCapture()
        } else if !shouldCapture && isCapturing {
            stopCapture()
        }
    }

    private func startCapture() {
        isCapturing = true
        locationSource.beginRouteTracking()
        locationCancellable = locationSource.locationPublisher
            .sink { [weak self] location in
                self?.append(location)
            }
        if let activeTripSessionId {
            AnalyticsService.shared.log(.routeTrackingStarted(tripId: activeTripSessionId.uuidString))
        }
    }

    private func stopCapture() {
        guard isCapturing else { return }
        isCapturing = false
        locationCancellable = nil
        locationSource.endRouteTracking()
        flushUnpersistedPoints()
        if let activeTripSessionId {
            AnalyticsService.shared.log(.routeTrackingStopped(tripId: activeTripSessionId.uuidString))
        }
    }

    private func append(_ location: CLLocation?) {
        guard isCapturing, let location, location.horizontalAccuracy >= 0 else { return }
        if let last = routePoints.last,
           location.distance(from: last) < Self.minimumPointSeparationMeters {
            return
        }
        routePoints.append(location)
        unpersistedPoints.append(location)
        if unpersistedPoints.count >= Self.persistenceBatchSize {
            flushUnpersistedPoints()
        }
    }

    private func flushUnpersistedPoints() {
        guard let activeTripSessionId, !unpersistedPoints.isEmpty else { return }
        // Failure keeps the batch for the next flush; capture is never interrupted.
        if (try? repository.append(points: unpersistedPoints, tripSessionId: activeTripSessionId)) != nil {
            unpersistedPoints = []
        }
    }
}

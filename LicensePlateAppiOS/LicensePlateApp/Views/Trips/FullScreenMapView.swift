//
//  FullScreenMapView.swift
//  LicensePlateApp
//

import SwiftUI
import MapKit
import CoreLocation
import GoogleMaps
import Combine

/// Provider-switching full-screen map shared by game and trip screens.
struct FullScreenMapView: View {
    let tripSessionId: UUID
    let enabledCountries: [PlateRegion.Country]
    /// When non-nil, only these region IDs are drawn (territory / DC filters). Nil keeps country-only filtering.
    var enabledRegionIds: Set<String>? = nil
    let foundRegionIDs: [String]
    let foundRegions: [FoundRegion]
    let finderIdentities: [String: UserRepository.UserIdentitySnapshot]
    @Binding var cameraPosition: GMSCameraPosition
    @ObservedObject var locationManager: LocationManager
    let namespace: Namespace.ID
    @Binding var isPresented: Bool

    @AppStorage("appMapProvider") private var appMapProviderRaw: String = AppPreferences.defaultMapProvider().rawValue
    @AppStorage(NewTripDefaultsKeys.showMyActiveTripOnLargeMap) private var showActiveTripRoute = true
    @ObservedObject private var routeTracking = TripRouteTrackingService.shared

    private var mapProvider: AppMapProvider {
        AppMapProvider(rawValue: appMapProviderRaw) ?? AppPreferences.defaultMapProvider()
    }

    private var routeCoordinates: [CLLocationCoordinate2D] {
        guard showActiveTripRoute, routeTracking.activeTripSessionId == tripSessionId else { return [] }
        return routeTracking.routePoints.map(\.coordinate)
    }

    var body: some View {
        Group {
            if mapProvider == .google {
                FullScreenGoogleMapView(
                    tripSessionId: tripSessionId,
                    enabledCountries: enabledCountries,
                    enabledRegionIds: enabledRegionIds,
                    foundRegionIDs: foundRegionIDs,
                    foundRegions: foundRegions,
                    finderIdentities: finderIdentities,
                    routeCoordinates: routeCoordinates,
                    cameraPosition: $cameraPosition,
                    locationManager: locationManager,
                    namespace: namespace,
                    isPresented: $isPresented
                )
            } else {
                FullScreenAppleMapView(
                    tripSessionId: tripSessionId,
                    country: enabledCountries.first ?? .unitedStates,
                    foundRegionIDs: foundRegionIDs,
                    foundRegions: foundRegions,
                    finderIdentities: finderIdentities,
                    routeCoordinates: routeCoordinates,
                    locationManager: locationManager,
                    namespace: namespace,
                    isPresented: $isPresented
                )
            }
        }
    }
}

// Full screen map view with location support (Google Maps)
struct FullScreenGoogleMapView: View {
    let tripSessionId: UUID
    let enabledCountries: [PlateRegion.Country]
    var enabledRegionIds: Set<String>? = nil
    let foundRegionIDs: [String]
    let foundRegions: [FoundRegion]
    let finderIdentities: [String: UserRepository.UserIdentitySnapshot]
    let routeCoordinates: [CLLocationCoordinate2D]
    @Binding var cameraPosition: GMSCameraPosition
    @ObservedObject var locationManager: LocationManager
    let namespace: Namespace.ID
    @Binding var isPresented: Bool
    
    @EnvironmentObject private var authService: FirebaseAuthService
    @AppStorage("appMapStyle") private var appMapStyleRaw: String = AppMapStyle.standard.rawValue
    @AppStorage("appShowUserAvatarOnMap") private var appShowUserAvatarOnMap = false
    @ObservedObject private var effectiveSettings = EffectiveSettingsResolver.shared

    init(
        tripSessionId: UUID,
        enabledCountries: [PlateRegion.Country],
        enabledRegionIds: Set<String>? = nil,
        foundRegionIDs: [String],
        foundRegions: [FoundRegion],
        finderIdentities: [String: UserRepository.UserIdentitySnapshot],
        routeCoordinates: [CLLocationCoordinate2D],
        cameraPosition: Binding<GMSCameraPosition>,
        locationManager: LocationManager,
        namespace: Namespace.ID,
        isPresented: Binding<Bool>
    ) {
        self.tripSessionId = tripSessionId
        self.enabledCountries = enabledCountries
        self.enabledRegionIds = enabledRegionIds
        self.foundRegionIDs = foundRegionIDs
        self.foundRegions = foundRegions
        self.finderIdentities = finderIdentities
        self.routeCoordinates = routeCoordinates
        self._cameraPosition = cameraPosition
        self.locationManager = locationManager
        self.namespace = namespace
        self._isPresented = isPresented
    }

    private var finderPinIcons: [String: UIImage] {
        finderIdentities.compactMapValues { identity in
            FinderPinBadge.markerIcon(
                avatarImage: AvatarCatalog.image(forAvatarId: identity.avatarId),
                displayName: identity.displayName
            )
        }
    }

    private var finderDisplayNames: [String: String] {
        let currentId = authService.currentUser?.firebaseUID ?? authService.currentUser?.id
        return Dictionary(uniqueKeysWithValues: finderIdentities.map { userId, identity in
            (
                userId,
                ParticipantDisplayName.decorated(
                    identity.displayName,
                    userId: userId,
                    currentUserId: currentId
                )
            )
        })
    }
    
    private var regions: [PlateRegion] {
        PlateRegion.all.filter { region in
            guard enabledCountries.contains(region.country) else { return false }
            if let enabledRegionIds { return enabledRegionIds.contains(region.id) }
            return true
        }
    }
    
    private var mapType: GMSMapViewType {
        let mapStyle = AppMapStyle(rawValue: appMapStyleRaw) ?? .standard
        return mapStyle.googleMapType
    }
    
    private var showUserLocation: Bool {
        let uid = authService.currentUser?.firebaseUID ?? authService.currentUser?.id ?? ""
        let show = effectiveSettings.resolve(sessionId: tripSessionId, userId: uid).showMyLocationOnLargeMap
        return (locationManager.authorizationStatus == .authorizedWhenInUse || locationManager.authorizationStatus == .authorizedAlways)
            && show
    }
    
    private var userAvatarImage: UIImage? {
        AvatarCatalog.image(forAvatarId: authService.currentUser?.avatarId)
    }
    
    var body: some View {
        ZStack {
            // Full screen map
              GoogleMapView(
                cameraPosition: $cameraPosition,
                foundRegionIDs: foundRegionIDs,
                foundRegions: foundRegions,
                finderPinIcons: finderPinIcons,
                finderDisplayNames: finderDisplayNames,
                routeCoordinates: routeCoordinates,
                showUserLocation: showUserLocation,
                userLocation: locationManager.location?.coordinate,
                showUserAvatarOnMap: appShowUserAvatarOnMap,
                userAvatarImage: userAvatarImage,
                mapType: mapType,
                regions: regions,
                namespace: namespace
            )
            .modifier(ConditionalMatchedGeometryEffect(
                id: "map",
                namespace: namespace,
                isActive: isPresented && !UIAccessibility.isReduceMotionEnabled
            ))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
            .onAppear {
                // Start location updates if permission granted
                if showUserLocation {
                    locationManager.startUpdatingLocation()
                }
            }
            .onDisappear {
                locationManager.stopUpdatingLocation()
            }
            
            // Close button - positioned below safe area at top right
            GeometryReader { geometry in
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            withAccessibleAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                isPresented = false
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(Color.Theme.primaryBlue)
                                .background(
                                    Circle()
                                        .fill(Color.white)
                                        .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
                                )
                        }
                        .safeAreaPadding(.all)
                        .padding(.trailing, 0)
                        .padding(.top, 32)
                    }
                    Spacer()
                }
            }
        }
        .background(
            Color(
                light: Color.black,
                dark: Color(red: 0.05, green: 0.05, blue: 0.05)
            ).ignoresSafeArea()
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .toolbar(.hidden, for: .navigationBar)
    }
}

// MARK: - Conditional Matched Geometry Effect

/// View modifier that conditionally applies matched geometry effect
/// Respects reduced motion settings for accessibility
struct ConditionalMatchedGeometryEffect: ViewModifier {
    let id: String
    let namespace: Namespace.ID
    let isActive: Bool
    
    func body(content: Content) -> some View {
        if isActive {
            content.matchedGeometryEffect(id: id, in: namespace)
        } else {
            content
        }
    }
}

/// Provides pulse phase for map user-location ring. Single source of truth so we never modify view state during body.
@MainActor
private final class MapPulsePhaseProvider: ObservableObject {
    static let shared = MapPulsePhaseProvider()
    static let pulseDuration: TimeInterval = 1.4
    
    @Published private(set) var phase: Double = 0
    private var timer: Timer?
    
    private init() {
        startTimer()
    }
    
    private func startTimer() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let t = Date().timeIntervalSinceReferenceDate
            let newPhase = (t.truncatingRemainder(dividingBy: Self.pulseDuration)) / Self.pulseDuration
            DispatchQueue.main.async { [weak self] in
                self?.phase = newPhase
            }
        }
        timer?.tolerance = 0.01
        RunLoop.main.add(timer!, forMode: .common)
    }
}

/// User location indicator: outer ring that pulses outward; optional inner green dot (hidden when avatar is shown)
private struct UserLocationPulseView: View {
    static let outerSize: CGFloat = 56
    static let innerSize: CGFloat = 24
    /// When true, only the pulse ring is drawn (no inner dot) so the avatar is the only “center”
    var avatarVisible: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var pulseProvider = MapPulsePhaseProvider.shared
    
    var body: some View {
        ZStack {
            // Outer circle — pulses outward and fades (phase from provider, no state updates in view)
            if !reduceMotion {
                Circle()
                    .fill(Color.green.opacity(0.9))
                    .frame(width: Self.outerSize, height: Self.outerSize)
                    .scaleEffect(0.6 + 0.9 * pulseProvider.phase)
                    .opacity(0.6 * (1 - pulseProvider.phase))
            } else {
                Circle()
                    .fill(Color.green.opacity(0.4))
                    .frame(width: Self.outerSize, height: Self.outerSize)
            }
            Circle()
                .fill(Color.green)
                .frame(width: !avatarVisible ? Self.innerSize: 32, height: !avatarVisible ? Self.innerSize : 32)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: !avatarVisible ? 3 : 0)
                )
        }
        .shadow(color: Color.black.opacity(0.3), radius: 4, x: 0, y: 2)
    }
}

// Full screen map view with location support (Apple Maps)
/// Internal (not private) so `FullScreenMapPreviews.swift` can preview it — canvas thunks
/// for this 2900-line file time out, so previews live in that small dedicated file.
struct FullScreenAppleMapView: View {
    let tripSessionId: UUID
    let country: PlateRegion.Country
    let foundRegionIDs: [String]
    let foundRegions: [FoundRegion]
    let finderIdentities: [String: UserRepository.UserIdentitySnapshot]
    let routeCoordinates: [CLLocationCoordinate2D]
    @ObservedObject var locationManager: LocationManager
    let namespace: Namespace.ID
    @Binding var isPresented: Bool
    
    @EnvironmentObject private var authService: FirebaseAuthService
    @AppStorage("appShowUserAvatarOnMap") private var appShowUserAvatarOnMap = false
    @ObservedObject private var effectiveSettings = EffectiveSettingsResolver.shared
    @State private var mapCameraPosition: MapCameraPosition

    private static let foundDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    init(
        tripSessionId: UUID = UUID(),
        country: PlateRegion.Country,
        foundRegionIDs: [String],
        foundRegions: [FoundRegion],
        finderIdentities: [String: UserRepository.UserIdentitySnapshot] = [:],
        routeCoordinates: [CLLocationCoordinate2D] = [],
        locationManager: LocationManager,
        namespace: Namespace.ID,
        isPresented: Binding<Bool>
    ) {
        self.tripSessionId = tripSessionId
        self.country = country
        self.foundRegionIDs = foundRegionIDs
        self.foundRegions = foundRegions
        self.finderIdentities = finderIdentities
        self.routeCoordinates = routeCoordinates
        self.locationManager = locationManager
        self.namespace = namespace
        self._isPresented = isPresented
        
        // Initialize map region based on country
        let initialRegion: MKCoordinateRegion
        switch country {
        case .unitedStates:
            initialRegion = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 40.8283, longitude: -106.5795),
                span: MKCoordinateSpan(latitudeDelta: 50, longitudeDelta: 100)
            )
        case .canada:
            initialRegion = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 56.1304, longitude: -106.3468),
                span: MKCoordinateSpan(latitudeDelta: 30, longitudeDelta: 60)
            )
        case .mexico:
            initialRegion = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 23.6345, longitude: -102.5528),
                span: MKCoordinateSpan(latitudeDelta: 15, longitudeDelta: 20)
            )
        }
        
        _mapCameraPosition = State(initialValue: .region(initialRegion))
    }
    
    private var regions: [PlateRegion] {
        PlateRegion.all.filter { $0.country == country }
    }
    
    private var coordinateForRegion: (PlateRegion) -> CLLocationCoordinate2D {
        { region in
            let coordinates: [String: CLLocationCoordinate2D] = [
                // United States
                "us-al": CLLocationCoordinate2D(latitude: 32.806671, longitude: -86.791130),
                "us-ak": CLLocationCoordinate2D(latitude: 61.370716, longitude: -152.404419),
                "us-az": CLLocationCoordinate2D(latitude: 33.729759, longitude: -111.431221),
                "us-ar": CLLocationCoordinate2D(latitude: 34.969704, longitude: -92.373123),
                "us-ca": CLLocationCoordinate2D(latitude: 36.116203, longitude: -119.681564),
                "us-co": CLLocationCoordinate2D(latitude: 39.059811, longitude: -105.311104),
                "us-ct": CLLocationCoordinate2D(latitude: 41.597782, longitude: -72.755371),
                "us-de": CLLocationCoordinate2D(latitude: 39.318523, longitude: -75.507141),
                "us-fl": CLLocationCoordinate2D(latitude: 27.766279, longitude: -81.686783),
                "us-ga": CLLocationCoordinate2D(latitude: 33.040619, longitude: -83.643074),
                "us-hi": CLLocationCoordinate2D(latitude: 21.094318, longitude: -157.498337),
                "us-id": CLLocationCoordinate2D(latitude: 44.240459, longitude: -114.478828),
                "us-il": CLLocationCoordinate2D(latitude: 40.349457, longitude: -88.986137),
                "us-in": CLLocationCoordinate2D(latitude: 39.849426, longitude: -86.258278),
                "us-ia": CLLocationCoordinate2D(latitude: 42.011539, longitude: -93.210526),
                "us-ks": CLLocationCoordinate2D(latitude: 38.526600, longitude: -96.726486),
                "us-ky": CLLocationCoordinate2D(latitude: 37.668140, longitude: -84.670067),
                "us-la": CLLocationCoordinate2D(latitude: 31.169546, longitude: -91.867805),
                "us-me": CLLocationCoordinate2D(latitude: 44.323535, longitude: -69.765261),
                "us-md": CLLocationCoordinate2D(latitude: 39.063946, longitude: -76.802101),
                "us-ma": CLLocationCoordinate2D(latitude: 42.230171, longitude: -71.530106),
                "us-mi": CLLocationCoordinate2D(latitude: 43.326618, longitude: -84.536095),
                "us-mn": CLLocationCoordinate2D(latitude: 45.694454, longitude: -93.900192),
                "us-ms": CLLocationCoordinate2D(latitude: 32.741646, longitude: -89.678696),
                "us-mo": CLLocationCoordinate2D(latitude: 38.456085, longitude: -92.288368),
                "us-mt": CLLocationCoordinate2D(latitude: 46.921925, longitude: -110.454353),
                "us-ne": CLLocationCoordinate2D(latitude: 41.125370, longitude: -98.268082),
                "us-nv": CLLocationCoordinate2D(latitude: 38.313515, longitude: -117.055374),
                "us-nh": CLLocationCoordinate2D(latitude: 43.452492, longitude: -71.563896),
                "us-nj": CLLocationCoordinate2D(latitude: 40.298904, longitude: -74.521011),
                "us-nm": CLLocationCoordinate2D(latitude: 34.840515, longitude: -106.248482),
                "us-ny": CLLocationCoordinate2D(latitude: 42.165726, longitude: -74.948051),
                "us-nc": CLLocationCoordinate2D(latitude: 35.630066, longitude: -79.806419),
                "us-nd": CLLocationCoordinate2D(latitude: 47.528912, longitude: -99.784012),
                "us-oh": CLLocationCoordinate2D(latitude: 40.388783, longitude: -82.764915),
                "us-ok": CLLocationCoordinate2D(latitude: 35.565342, longitude: -96.928917),
                "us-or": CLLocationCoordinate2D(latitude: 44.572021, longitude: -122.070938),
                "us-pa": CLLocationCoordinate2D(latitude: 40.590752, longitude: -77.209755),
                "us-ri": CLLocationCoordinate2D(latitude: 41.680893, longitude: -71.51178),
                "us-sc": CLLocationCoordinate2D(latitude: 33.856892, longitude: -80.945007),
                "us-sd": CLLocationCoordinate2D(latitude: 44.299782, longitude: -99.438828),
                "us-tn": CLLocationCoordinate2D(latitude: 35.747845, longitude: -86.692345),
                "us-tx": CLLocationCoordinate2D(latitude: 31.054487, longitude: -97.563461),
                "us-ut": CLLocationCoordinate2D(latitude: 40.150032, longitude: -111.862434),
                "us-vt": CLLocationCoordinate2D(latitude: 44.045876, longitude: -72.710686),
                "us-va": CLLocationCoordinate2D(latitude: 37.769337, longitude: -78.169968),
                "us-wa": CLLocationCoordinate2D(latitude: 47.400902, longitude: -121.490494),
                "us-wv": CLLocationCoordinate2D(latitude: 38.491226, longitude: -80.954453),
                "us-wi": CLLocationCoordinate2D(latitude: 44.268543, longitude: -89.616508),
                "us-wy": CLLocationCoordinate2D(latitude: 42.755966, longitude: -107.302490),
                "us-dc": CLLocationCoordinate2D(latitude: 38.907192, longitude: -77.036873),
                "us-pr": CLLocationCoordinate2D(latitude: 18.220833, longitude: -66.590149),
                "us-gu": CLLocationCoordinate2D(latitude: 13.444304, longitude: 144.793731),
                "us-vi": CLLocationCoordinate2D(latitude: 18.335765, longitude: -64.896335),
                "us-as": CLLocationCoordinate2D(latitude: -14.271000, longitude: -170.132217),
                "us-mp": CLLocationCoordinate2D(latitude: 17.330830, longitude: 145.384690),
                // Canada
                "ca-ab": CLLocationCoordinate2D(latitude: 53.933271, longitude: -116.576504),
                "ca-bc": CLLocationCoordinate2D(latitude: 53.726669, longitude: -127.647621),
                "ca-mb": CLLocationCoordinate2D(latitude: 53.760861, longitude: -98.813876),
                "ca-nb": CLLocationCoordinate2D(latitude: 46.565316, longitude: -66.461916),
                "ca-nl": CLLocationCoordinate2D(latitude: 53.135509, longitude: -57.660436),
                "ca-nt": CLLocationCoordinate2D(latitude: 64.825545, longitude: -124.845733),
                "ca-ns": CLLocationCoordinate2D(latitude: 44.682006, longitude: -63.744311),
                "ca-nu": CLLocationCoordinate2D(latitude: 70.299771, longitude: -83.107577),
                "ca-on": CLLocationCoordinate2D(latitude: 50.000000, longitude: -85.000000),
                "ca-pe": CLLocationCoordinate2D(latitude: 46.510712, longitude: -63.416813),
                "ca-qc": CLLocationCoordinate2D(latitude: 52.939916, longitude: -73.549136),
                "ca-sk": CLLocationCoordinate2D(latitude: 52.939916, longitude: -106.450864),
                "ca-yt": CLLocationCoordinate2D(latitude: 64.282327, longitude: -135.000000),
                // Mexico
                "mx-ags": CLLocationCoordinate2D(latitude: 21.885256, longitude: -102.291567),
                "mx-bcn": CLLocationCoordinate2D(latitude: 30.840634, longitude: -115.283758),
                "mx-bcs": CLLocationCoordinate2D(latitude: 26.044444, longitude: -111.666072),
                "mx-cam": CLLocationCoordinate2D(latitude: 19.830125, longitude: -90.534909),
                "mx-chp": CLLocationCoordinate2D(latitude: 16.756931, longitude: -93.129235),
                "mx-chh": CLLocationCoordinate2D(latitude: 28.632996, longitude: -106.069100),
                "mx-coa": CLLocationCoordinate2D(latitude: 27.058676, longitude: -101.706829),
                "mx-col": CLLocationCoordinate2D(latitude: 19.245234, longitude: -103.724087),
                "mx-dur": CLLocationCoordinate2D(latitude: 24.027720, longitude: -104.653176),
                "mx-gua": CLLocationCoordinate2D(latitude: 21.019015, longitude: -101.257359),
                "mx-gro": CLLocationCoordinate2D(latitude: 17.573988, longitude: -99.497688),
                "mx-hid": CLLocationCoordinate2D(latitude: 20.091143, longitude: -98.762387),
                "mx-jal": CLLocationCoordinate2D(latitude: 20.659699, longitude: -103.349609),
                "mx-mex": CLLocationCoordinate2D(latitude: 19.496873, longitude: -99.723267),
                "mx-mic": CLLocationCoordinate2D(latitude: 19.566519, longitude: -101.706829),
                "mx-mor": CLLocationCoordinate2D(latitude: 18.681305, longitude: -99.101350),
                "mx-nay": CLLocationCoordinate2D(latitude: 21.751384, longitude: -105.231098),
                "mx-nle": CLLocationCoordinate2D(latitude: 25.592172, longitude: -99.996194),
                "mx-oax": CLLocationCoordinate2D(latitude: 17.073184, longitude: -96.726588),
                "mx-pue": CLLocationCoordinate2D(latitude: 19.041440, longitude: -98.206273),
                "mx-que": CLLocationCoordinate2D(latitude: 20.588793, longitude: -100.389888),
                "mx-roo": CLLocationCoordinate2D(latitude: 19.181738, longitude: -88.479137),
                "mx-slp": CLLocationCoordinate2D(latitude: 22.156469, longitude: -100.985540),
                "mx-sin": CLLocationCoordinate2D(latitude: 25.172109, longitude: -107.801228),
                "mx-son": CLLocationCoordinate2D(latitude: 29.297019, longitude: -110.330925),
                "mx-tab": CLLocationCoordinate2D(latitude: 18.166850, longitude: -92.618927),
                "mx-tam": CLLocationCoordinate2D(latitude: 24.266940, longitude: -98.836275),
                "mx-tla": CLLocationCoordinate2D(latitude: 19.313923, longitude: -98.240447),
                "mx-ver": CLLocationCoordinate2D(latitude: 19.173773, longitude: -96.134224),
                "mx-yuc": CLLocationCoordinate2D(latitude: 20.684285, longitude: -89.094338),
                "mx-zac": CLLocationCoordinate2D(latitude: 23.293451, longitude: -102.700737),
                "mx-cmx": CLLocationCoordinate2D(latitude: 19.432608, longitude: -99.133209)
            ]
            return coordinates[region.id] ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
        }
    }
    
    var body: some View {
        ZStack {
            // Full screen map
            Map(position: $mapCameraPosition) {
                // Region annotations
                ForEach(PlateRegion.all) { region in
                    Annotation(region.name, coordinate: coordinateForRegion(region)) {
                        Circle()
                            .fill(foundRegionIDs.contains(region.id) ? Color.Theme.accentYellow : Color.Theme.primaryBlue.opacity(0.6))
                            .frame(width: 16, height: 16)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: 2)
                            )
                            .shadow(color: Color.black.opacity(0.3), radius: 3, x: 0, y: 2)
                    }
                }
                
                // Live route ribbon (GPS Step 6) — parity with GoogleMapView.renderRoutePolyline
                if routeCoordinates.count >= 2 {
                    MapPolyline(coordinates: routeCoordinates)
                        .stroke(Color.Theme.primaryBlue, lineWidth: 4)
                }

                // Where-found pins at capture locations (parity with GoogleMapView.renderFoundLocationMarkers)
                ForEach(foundRegions.filter { $0.foundAtLocation != nil }) { foundRegion in
                    if let locationData = foundRegion.foundAtLocation {
                        let regionName = PlateRegion.all.first(where: { $0.id == foundRegion.regionID })?.name ?? foundRegion.regionID
                        let finderIdentity = foundRegion.foundBy.flatMap { finderIdentities[$0] }
                        let dateText = Self.foundDateFormatter.string(from: foundRegion.foundAt)
                        let foundText = finderIdentity.map { identity in
                            let name = ParticipantDisplayName.decorated(
                                identity.displayName,
                                userId: foundRegion.foundBy ?? "",
                                currentUserId: authService.currentUser?.firebaseUID ?? authService.currentUser?.id
                            )
                            return "Found by %@ on %@".localized(name, dateText)
                        } ?? "Found on %@".localized(dateText)
                        Annotation(regionName, coordinate: CLLocationCoordinate2D(
                            latitude: locationData.latitude,
                            longitude: locationData.longitude
                        )) {
                            FinderPinBadgeView(
                                avatarImage: AvatarCatalog.image(forAvatarId: finderIdentity?.avatarId),
                                displayName: finderIdentity?.displayName
                            )
                            .accessibilityLabel("\(regionName), \(foundText)")
                        }
                    }
                }

                // User location: single annotation with ZStack so green is behind, avatar on top
                if let userLocation = locationManager.location,
                   locationManager.authorizationStatus == .authorizedWhenInUse || locationManager.authorizationStatus == .authorizedAlways,
                   effectiveSettings.resolve(
                    sessionId: tripSessionId,
                    userId: authService.currentUser?.firebaseUID ?? authService.currentUser?.id ?? ""
                   ).showMyLocationOnLargeMap {
                    Annotation("Your Location".localized, coordinate: userLocation.coordinate) {
                        ZStack {
                            // Green pulse ring (and dot when no avatar) — back layer
                            UserLocationPulseView(avatarVisible: appShowUserAvatarOnMap)
                            // Avatar — front layer, always on top of green
                            if appShowUserAvatarOnMap,
                               let avatarImage = AvatarCatalog.image(forAvatarId: authService.currentUser?.avatarId) {
                                Image(uiImage: avatarImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 32, height: 32)
                                    .clipShape(Circle())
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white, lineWidth: 1)
                                    )
                                    .shadow(color: Color.black.opacity(0.3), radius: 3, x: 0, y: 2)
                            }
                        }
                    }
                }
            }
            .mapStyle(AppPreferences.mapStyleFromPreference())
            .matchedGeometryEffect(id: "map", in: namespace)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
            .onAppear {
                // Start location updates if permission granted
                if locationManager.authorizationStatus == .authorizedWhenInUse || locationManager.authorizationStatus == .authorizedAlways {
                    locationManager.startUpdatingLocation()
                }
            }
            .onDisappear {
                locationManager.stopUpdatingLocation()
            }
            
            // Close button - positioned below safe area at top right
            GeometryReader { geometry in
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            withAccessibleAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                isPresented = false
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(Color.Theme.primaryBlue)
                                .background(
                                    Circle()
                                        .fill(Color.white)
                                        .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
                                )
                        }
                        .safeAreaPadding(.all)
                        .padding(.trailing, 0)
                        .padding(.top, 32)
                    }
                    Spacer()
                }
            }
        }
        .background(
            Color(
                light: Color.black,
                dark: Color(red: 0.05, green: 0.05, blue: 0.05)
            ).ignoresSafeArea()
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .toolbar(.hidden, for: .navigationBar)
    }
}

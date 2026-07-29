//
//  RegionMapView.swift
//  LicensePlateApp
//

import SwiftUI
import MapKit
import CoreLocation
import GoogleMaps

/// Provider-switching compact region map shared by game and trip screens.
struct RegionMapView: View {
    let tripSessionId: UUID
    let enabledCountries: [PlateRegion.Country]
    let foundRegionIDs: [String]
    let foundRegions: [FoundRegion]
    let visibleCountry: PlateRegion.Country
    @Binding var cameraPosition: GMSCameraPosition
    let namespace: Namespace.ID
    @Binding var showFullScreen: Bool
    @ObservedObject var locationManager: LocationManager

    @AppStorage("appMapProvider") private var appMapProviderRaw: String = AppPreferences.defaultMapProvider().rawValue
    @AppStorage(NewTripDefaultsKeys.showMyActiveTripOnSmallMap) private var showActiveTripRoute = true
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
                RegionGoogleMapView(
                    enabledCountries: enabledCountries,
                    foundRegionIDs: foundRegionIDs,
                    foundRegions: foundRegions,
                    routeCoordinates: routeCoordinates,
                    visibleCountry: visibleCountry,
                    cameraPosition: $cameraPosition,
                    namespace: namespace,
                    showFullScreen: $showFullScreen,
                    locationManager: locationManager
                )
            } else {
                RegionAppleMapView(
                    country: visibleCountry,
                    foundRegionIDs: foundRegionIDs,
                    routeCoordinates: routeCoordinates,
                    namespace: namespace,
                    showFullScreen: $showFullScreen,
                    locationManager: locationManager
                )
            }
        }
    }
}

// Map view showing regions for enabled countries (Google Maps)
struct RegionGoogleMapView: View {
    let enabledCountries: [PlateRegion.Country]
    let foundRegionIDs: [String]
    let foundRegions: [FoundRegion]
    let routeCoordinates: [CLLocationCoordinate2D]
    let visibleCountry: PlateRegion.Country
    @Binding var cameraPosition: GMSCameraPosition
    let namespace: Namespace.ID
    @Binding var showFullScreen: Bool
    @ObservedObject var locationManager: LocationManager
    
    @AppStorage("appMapStyle") private var appMapStyleRaw: String = AppMapStyle.standard.rawValue
    
    init(enabledCountries: [PlateRegion.Country], foundRegionIDs: [String], foundRegions: [FoundRegion], routeCoordinates: [CLLocationCoordinate2D], visibleCountry: PlateRegion.Country, cameraPosition: Binding<GMSCameraPosition>, namespace: Namespace.ID, showFullScreen: Binding<Bool>, locationManager: LocationManager) {
        self.enabledCountries = enabledCountries
        self.foundRegionIDs = foundRegionIDs
        self.foundRegions = foundRegions
        self.routeCoordinates = routeCoordinates
        self.visibleCountry = visibleCountry
        self._cameraPosition = cameraPosition
        self.namespace = namespace
        self._showFullScreen = showFullScreen
        self.locationManager = locationManager
    }
    
    private var regionsForCurrentCountry: [PlateRegion] {
        PlateRegion.all.filter { enabledCountries.contains($0.country) }
    }
    
    private var mapType: GMSMapViewType {
        let mapStyle = AppMapStyle(rawValue: appMapStyleRaw) ?? .standard
        return mapStyle.googleMapType
    }
    
    /// Calculate camera position for a specific country (using old Apple Maps span values)
    private func calculateCameraPositionForCountry(_ country: PlateRegion.Country) -> (CLLocationCoordinate2D, Float) {
        // Convert old MKCoordinateSpan values to Google Maps zoom levels
        // Formula: zoom = log2(360 / latitudeDelta)
        // Old values from RegionMapView in the attached file:
        // US: span (50, 50) 
        // Canada: span (30, 60)
        // Mexico: span (15, 20)
        switch country {
        case .unitedStates:
            // Old: span (50, 50) -> zoom = log2(360/50) ≈ 2.85, but use slightly higher for better view
            let center = CLLocationCoordinate2D(latitude: 40.8283, longitude: -106.5795)
            let span = MKCoordinateSpan(latitudeDelta: 50, longitudeDelta: 50)
            let camera = GMSCameraPosition.from(center: center, span: span)
            return (center, camera.zoom)
        case .canada:
            // Old: span (30, 60) -> zoom = log2(360/30) ≈ 3.58
            let center = CLLocationCoordinate2D(latitude: 56.1304, longitude: -106.3468)
            let span = MKCoordinateSpan(latitudeDelta: 30, longitudeDelta: 60)
            let camera = GMSCameraPosition.from(center: center, span: span)
            return (center, camera.zoom)
        case .mexico:
            // Old: span (15, 20) -> zoom = log2(360/15) ≈ 4.58
            let center = CLLocationCoordinate2D(latitude: 23.6345, longitude: -102.5528)
            let span = MKCoordinateSpan(latitudeDelta: 15, longitudeDelta: 20)
            let camera = GMSCameraPosition.from(center: center, span: span)
            return (center, camera.zoom)
        }
    }
    
    var body: some View {
        ZStack {
            GoogleMapView(
                cameraPosition: $cameraPosition,
                foundRegionIDs: foundRegionIDs,
                foundRegions: foundRegions,
                routeCoordinates: routeCoordinates,
                showUserLocation: false,
                userLocation: locationManager.location?.coordinate,
                mapType: mapType,
                regions: regionsForCurrentCountry,
                namespace: namespace
            )
            .disabled(true)
            .modifier(ConditionalMatchedGeometryEffect(
                id: "map",
                namespace: namespace,
                isActive: !showFullScreen && !UIAccessibility.isReduceMotionEnabled
            ))
            
            // Invisible tap area
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    withAccessibleAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                        showFullScreen = true
                    }
                }
                .accessibilityLabel("Map showing %@ regions".localized(visibleCountry.rawValue.localized))
                .accessibilityHint("Double tap to open full screen map".localized)
                .accessibilityAddTraits(.isButton)
        }
        .onChange(of: visibleCountry) { oldValue, newValue in
            // Only update camera position for small map, not full screen map
            if !showFullScreen {
                let (center, zoom) = calculateCameraPositionForCountry(newValue)
                withAccessibleAnimation(.easeInOut(duration: 0.5)) {
                    cameraPosition = GMSCameraPosition.from(coordinate: center, zoom: zoom)
                }
            }
        }
    }
    
    private func coordinateForRegion(_ region: PlateRegion) -> CLLocationCoordinate2D {
        // Approximate center coordinates for regions
        // This is a simplified approach - in production you'd want more precise coordinates
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

// Map view showing regions for a specific country (Apple Maps)
struct RegionAppleMapView: View {
    let country: PlateRegion.Country
    let foundRegionIDs: [String]
    let routeCoordinates: [CLLocationCoordinate2D]
    let namespace: Namespace.ID
    @Binding var showFullScreen: Bool
    @ObservedObject var locationManager: LocationManager
    
    @State private var mapCameraPosition: MapCameraPosition
    
    init(country: PlateRegion.Country, foundRegionIDs: [String], routeCoordinates: [CLLocationCoordinate2D], namespace: Namespace.ID, showFullScreen: Binding<Bool>, locationManager: LocationManager) {
        self.country = country
        self.foundRegionIDs = foundRegionIDs
        self.routeCoordinates = routeCoordinates
        self.namespace = namespace
        self._showFullScreen = showFullScreen
        self.locationManager = locationManager
        _mapCameraPosition = State(initialValue: .region(Self.mapRegion(for: country)))
    }
    
    private var regionsForCurrentCountry: [PlateRegion] {
        PlateRegion.all.filter { $0.country == country }
    }
  
    private var regionsFound: [PlateRegion] {
        PlateRegion.all.filter { foundRegionIDs.contains($0.id)}
    }
    
    var body: some View {
        ZStack {
            Map(position: $mapCameraPosition) {
                if routeCoordinates.count >= 2 {
                    MapPolyline(coordinates: routeCoordinates)
                        .stroke(Color.Theme.primaryBlue, lineWidth: 4)
                }
                ForEach(regionsFound) { region in
                    Annotation(region.name, coordinate: coordinateForRegion(region)) {
                    Circle()
                        .fill(foundRegionIDs.contains(region.id) ? Color.Theme.accentYellow : Color.Theme.primaryBlue.opacity(0.6))
                        .frame(width: 12, height: 12)
                        .overlay(
                            Circle()
                                .stroke(Color.white, lineWidth: 2)
                        )
                        .shadow(color: Color.black.opacity(0.3), radius: 2, x: 0, y: 1)
                    }
                }
            }
            .mapStyle(AppPreferences.mapStyleFromPreference())
            .disabled(true)
            .matchedGeometryEffect(id: "map", in: namespace)
            
            // Invisible tap area
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    withAccessibleAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                        showFullScreen = true
                    }
                }
                .accessibilityLabel("Map showing %@ regions".localized(country.rawValue.localized))
                .accessibilityHint("Double tap to open full screen map".localized)
                .accessibilityAddTraits(.isButton)
        }
        .onChange(of: country) { oldValue, newValue in
            // Update map region when country changes
            withAccessibleAnimation(.easeInOut(duration: 0.5)) {
                mapCameraPosition = .region(Self.mapRegion(for: newValue))
            }
        }
    }

    private static func mapRegion(for country: PlateRegion.Country) -> MKCoordinateRegion {
        switch country {
        case .unitedStates:
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 40.8283, longitude: -106.5795),
                span: MKCoordinateSpan(latitudeDelta: 50, longitudeDelta: 50)
            )
        case .canada:
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 56.1304, longitude: -106.3468),
                span: MKCoordinateSpan(latitudeDelta: 30, longitudeDelta: 60)
            )
        case .mexico:
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 23.6345, longitude: -102.5528),
                span: MKCoordinateSpan(latitudeDelta: 15, longitudeDelta: 20)
            )
        }
    }
    
    private func coordinateForRegion(_ region: PlateRegion) -> CLLocationCoordinate2D {
        // Approximate center coordinates for regions
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

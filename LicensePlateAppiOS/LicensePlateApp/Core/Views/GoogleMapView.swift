//
//  GoogleMapView.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//

import SwiftUI
import GoogleMaps
import CoreLocation
import MapKit

/// SwiftUI wrapper for Google Maps with region boundary polygons
struct GoogleMapView: UIViewRepresentable {
    @Binding var cameraPosition: GMSCameraPosition
    let foundRegionIDs: [String]
    let foundRegions: [FoundRegion] // Full found regions data for markers
    let showUserLocation: Bool
    let userLocation: CLLocationCoordinate2D? // User's current location coordinate
    let mapType: GMSMapViewType
    let regions: [PlateRegion]
    let namespace: Namespace.ID?
    
    // Optional: Custom map style (if nil, will use preference-based style)
    let mapStyle: GMSMapStyle?
    
    init(
        cameraPosition: Binding<GMSCameraPosition>,
        foundRegionIDs: [String] = [],
        foundRegions: [FoundRegion] = [],
        showUserLocation: Bool = false,
        userLocation: CLLocationCoordinate2D? = nil,
        mapType: GMSMapViewType = .normal,
        regions: [PlateRegion] = PlateRegion.all,
        namespace: Namespace.ID? = nil,
        mapStyle: GMSMapStyle? = nil
    ) {
        self._cameraPosition = cameraPosition
        self.foundRegionIDs = foundRegionIDs
        self.foundRegions = foundRegions
        self.showUserLocation = showUserLocation
        self.userLocation = userLocation
        self.mapType = mapType
        self.regions = regions
        self.namespace = namespace
        self.mapStyle = mapStyle
    }
    
    private var effectiveMapStyle: GMSMapStyle? {
        // Use provided style, or get from preference
        return mapStyle ?? GoogleMapStyle.styleFromPreference()
    }
    
    /// Check if region borders should be shown based on user preference
    private var shouldShowRegionBorders: Bool {
        UserDefaults.standard.bool(forKey: "appShowRegionBorders")
    }
    
    /// Check if markers should be shown based on user preference
    private var shouldShowMarkers: Bool {
        UserDefaults.standard.bool(forKey: "appShowMapMarkers")
    }
    
    func makeUIView(context: Context) -> GMSMapView {
        let mapView = GMSMapView(frame: .zero, camera: cameraPosition)
        mapView.delegate = context.coordinator
        mapView.mapType = mapType
        // Disable built-in user location (we use custom green marker instead)
        mapView.isMyLocationEnabled = false
        mapView.settings.myLocationButton = false
        
        // Apply custom map style if provided or from preference
        if let style = effectiveMapStyle {
            mapView.mapStyle = style
        }
        
        // Render region polygons only if preference is enabled
        if shouldShowRegionBorders {
            context.coordinator.renderRegions(
                on: mapView,
                regions: regions,
                foundRegionIDs: foundRegionIDs
            )
        }
        
        // Render markers only if preference is enabled
        if shouldShowMarkers {
            context.coordinator.renderMarkers(
                on: mapView,
                foundRegions: foundRegions,
                regions: regions
            )
        }
        
        // Render custom user location marker if enabled and location available
        if showUserLocation, let location = userLocation {
            context.coordinator.renderUserLocationMarker(
                on: mapView,
                coordinate: location
            )
        }
        
        return mapView
    }
    
    func updateUIView(_ mapView: GMSMapView, context: Context) {
        // Update camera position
        mapView.animate(to: cameraPosition)
        
        // Update map type
        mapView.mapType = mapType
        
        // Keep built-in user location disabled (we use custom green marker instead)
        mapView.isMyLocationEnabled = false
        mapView.settings.myLocationButton = false
        
        // Update map style (check preference in case it changed)
        if let style = effectiveMapStyle {
            mapView.mapStyle = style
        } else {
            mapView.mapStyle = nil // Reset to default
        }
        
        // Update region polygons only if preference is enabled
        if shouldShowRegionBorders {
            context.coordinator.renderRegions(
                on: mapView,
                regions: regions,
                foundRegionIDs: foundRegionIDs
            )
        } else {
            // Clear all polygons if preference is disabled
            context.coordinator.clearAllPolygons(on: mapView)
        }
        
        // Update markers only if preference is enabled
        if shouldShowMarkers {
            context.coordinator.renderMarkers(
                on: mapView,
                foundRegions: foundRegions,
                regions: regions
            )
        } else {
            // Clear all markers if preference is disabled
            context.coordinator.clearAllMarkers(on: mapView)
        }
        
        // Update custom user location marker if enabled and location available
        if showUserLocation, let location = userLocation {
            context.coordinator.renderUserLocationMarker(
                on: mapView,
                coordinate: location
            )
        } else {
            // Clear user location marker if disabled or no location
            context.coordinator.clearUserLocationMarker(on: mapView)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, GMSMapViewDelegate {
        var parent: GoogleMapView
        private var polygons: [String: GMSPolygon] = [:]
        private var countryPolygons: [String: GMSPolygon] = [:] // Separate storage for country boundaries (map context only)
        private var markers: [String: GMSMarker] = [:] // Storage for region markers
        private var userLocationMarker: GMSMarker? // Custom green user location marker
        private var cachedPaths: [String: GMSMutablePath] = [:]
        private var lastFoundRegionIDs: Set<String> = []
        private var lastRegionIDs: Set<String> = []
        private var countriesRendered = false // Track if country boundaries have been rendered
        
        init(_ parent: GoogleMapView) {
            self.parent = parent
        }
        
        func renderRegions(
            on mapView: GMSMapView,
            regions: [PlateRegion],
            foundRegionIDs: [String]
        ) {
            let currentFoundSet = Set(foundRegionIDs)
            let currentRegionSet = Set(regions.map { $0.id })
            
            // Check if we need to rebuild polygons (regions changed)
            let regionsChanged = currentRegionSet != lastRegionIDs
            let foundStatusChanged = currentFoundSet != lastFoundRegionIDs
            
            // If regions changed, rebuild everything
            if regionsChanged {
                // Remove old polygons that are no longer needed
                for (regionId, polygon) in polygons {
                    if !currentRegionSet.contains(regionId) {
                        polygon.map = nil
                        polygons.removeValue(forKey: regionId)
                        cachedPaths.removeValue(forKey: regionId)
                    }
                }
                
                // Create or update polygons for current regions
                for region in regions {
                    let boundary = RegionBoundaries.boundary(for: region.id)
                    guard !boundary.isEmpty else { continue }
                    
                    // Create or reuse cached path
                    let path: GMSMutablePath
                    if let cachedPath = cachedPaths[region.id] {
                        path = cachedPath
                    } else {
                        path = GMSMutablePath()
                        for coordinate in boundary {
                            path.add(coordinate)
                        }
                        // Close the path
                        path.add(boundary[0])
                        cachedPaths[region.id] = path
                    }
                    
                    // Create or update polygon
                    let polygon: GMSPolygon
                    if let existingPolygon = polygons[region.id] {
                        polygon = existingPolygon
                    } else {
                        polygon = GMSPolygon(path: path)
                        polygon.strokeColor = UIColor.white.withAlphaComponent(0.9)
                        polygon.strokeWidth = 3.0
                        polygon.title = region.name
                        polygon.map = mapView
                        polygons[region.id] = polygon
                    }
                    
                    // Update color based on found status - solid and playful (Waze-like)
                    let isFound = foundRegionIDs.contains(region.id)
                    polygon.fillColor = isFound ? 
                        UIColor(Color.Theme.accentYellow).withAlphaComponent(0.9) : 
                        UIColor(Color.Theme.primaryBlue).withAlphaComponent(0.9)
                    polygon.strokeWidth = 3.0
                }
            } else if foundStatusChanged {
                // Only update colors if found status changed - solid and playful (Waze-like)
                for region in regions {
                    guard let polygon = polygons[region.id] else { continue }
                    let isFound = foundRegionIDs.contains(region.id)
                    polygon.fillColor = isFound ? 
                        UIColor(Color.Theme.accentYellow).withAlphaComponent(0.9) : 
                        UIColor(Color.Theme.primaryBlue).withAlphaComponent(0.9)
                }
            }
            
            // Update tracking sets
            lastFoundRegionIDs = currentFoundSet
            lastRegionIDs = currentRegionSet
            
            // Render country boundaries for map context (only if region borders are enabled)
            if parent.shouldShowRegionBorders {
                renderCountryBoundaries(on: mapView)
            }
        }
        
        /// Clear all polygons from the map (when region borders are disabled)
        func clearAllPolygons(on mapView: GMSMapView) {
            // Remove all game region polygons
            for (_, polygon) in polygons {
                polygon.map = nil
            }
            polygons.removeAll()
            cachedPaths.removeAll()
            lastFoundRegionIDs.removeAll()
            lastRegionIDs.removeAll()
            
            // Also remove country boundaries when borders are disabled
            for (_, polygon) in countryPolygons {
                polygon.map = nil
            }
            countryPolygons.removeAll()
            countriesRendered = false
        }
        
        /// Render markers for found regions that have location data (WHERE they were found)
        /// COMMENTED OUT: This shows where the user was when they found a region
        /// Keeping this code for future use when we want to show location-based markers
        /*
        func renderMarkersWhereFound(
            on mapView: GMSMapView,
            foundRegions: [FoundRegion],
            regions: [PlateRegion]
        ) {
            // Create a set of current found region IDs with locations
            let currentFoundWithLocations = Set(foundRegions.compactMap { region in
                region.foundAtLocation != nil ? region.regionID : nil
            })
            
            // Remove markers for regions that are no longer found or no longer have locations
            for (regionId, marker) in markers {
                if !currentFoundWithLocations.contains(regionId) {
                    marker.map = nil
                    markers.removeValue(forKey: regionId)
                }
            }
            
            // Add or update markers for found regions with locations
            for foundRegion in foundRegions {
                guard let locationData = foundRegion.foundAtLocation else { continue }
                guard regions.contains(where: { $0.id == foundRegion.regionID }) else { continue }
                
                let coordinate = CLLocationCoordinate2D(
                    latitude: locationData.latitude,
                    longitude: locationData.longitude
                )
                
                // Get region name for marker title
                let regionName = regions.first(where: { $0.id == foundRegion.regionID })?.name ?? foundRegion.regionID
                
                // Create or update marker
                let marker: GMSMarker
                if let existingMarker = markers[foundRegion.regionID] {
                    marker = existingMarker
                    marker.position = coordinate
                } else {
                    marker = GMSMarker(position: coordinate)
                    marker.title = regionName
                    marker.snippet = "Found on \(formatDate(foundRegion.foundAt))"
                    marker.icon = GMSMarker.markerImage(with: UIColor(Color.Theme.accentYellow))
                    marker.map = mapView
                    markers[foundRegion.regionID] = marker
                }
            }
        }
        */
        
        /// Render markers at region centers showing found/unfound status (WHAT regions were found)
        /// This matches the old Apple Maps behavior - shows markers at region centers
        func renderMarkers(
            on mapView: GMSMapView,
            foundRegions: [FoundRegion],
            regions: [PlateRegion]
        ) {
            let currentFoundSet = Set(parent.foundRegionIDs)
            let currentRegionSet = Set(regions.map { $0.id })
            
            // Remove markers for regions that are no longer in the current set
            for (regionId, marker) in markers {
                if !currentRegionSet.contains(regionId) {
                    marker.map = nil
                    markers.removeValue(forKey: regionId)
                }
            }
            
            // Add or update markers for all regions at their centers
            for region in regions {
                let coordinate = coordinateForRegion(region)
                guard coordinate.latitude != 0 || coordinate.longitude != 0 else { continue }
                
                let isFound = currentFoundSet.contains(region.id)
                
                // Create or update marker
                let marker: GMSMarker
                if let existingMarker = markers[region.id] {
                    marker = existingMarker
                } else {
                    marker = GMSMarker(position: coordinate)
                    marker.title = region.name
                    marker.map = mapView
                    markers[region.id] = marker
                }
                
                // Update marker color based on found status
                // Orange/yellow for found, blue for unfound
                // Create custom round circle icons instead of pin shape
                if isFound {
                    marker.icon = createRoundMarkerIcon(color: UIColor(Color.Theme.accentYellow), size: 16)
                } else {
                    marker.icon = createRoundMarkerIcon(color: UIColor(Color.Theme.primaryBlue).withAlphaComponent(0.6), size: 16)
                }
            }
        }
        
        /// Create a custom round circle marker icon (not pin shape)
        private func createRoundMarkerIcon(color: UIColor, size: CGFloat) -> UIImage {
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
            return renderer.image { context in
                // Draw white stroke circle
                let strokeRect = CGRect(x: 1, y: 1, width: size - 2, height: size - 2)
                context.cgContext.setStrokeColor(UIColor.white.cgColor)
                context.cgContext.setLineWidth(2.0)
                context.cgContext.addEllipse(in: strokeRect)
                context.cgContext.strokePath()
                
                // Draw filled circle
                let fillRect = CGRect(x: 2, y: 2, width: size - 4, height: size - 4)
                context.cgContext.setFillColor(color.cgColor)
                context.cgContext.fillEllipse(in: fillRect)
            }
        }
        
        /// Render custom green user location marker with extra circle (matches old Apple Maps behavior)
        func renderUserLocationMarker(
            on mapView: GMSMapView,
            coordinate: CLLocationCoordinate2D
        ) {
            // Create or update user location marker
            let marker: GMSMarker
            if let existingMarker = userLocationMarker {
                marker = existingMarker
                marker.position = coordinate
            } else {
                marker = GMSMarker(position: coordinate)
                marker.title = "Your Location"
                marker.map = mapView
                userLocationMarker = marker
            }
            
            // Create custom green marker with extra circle overlay
            // Inner circle: 20pt green with white stroke
            // Outer circle: 32pt green with opacity 0.3
            let size: CGFloat = 32
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
            let icon = renderer.image { context in
                // Draw outer circle (larger, semi-transparent)
                let outerRect = CGRect(x: 0, y: 0, width: size, height: size)
                context.cgContext.setFillColor(UIColor.green.withAlphaComponent(0.3).cgColor)
                context.cgContext.fillEllipse(in: outerRect)
                
                // Draw inner circle (smaller, solid)
                let innerSize: CGFloat = 20
                let innerRect = CGRect(x: (size - innerSize) / 2, y: (size - innerSize) / 2, width: innerSize, height: innerSize)
                context.cgContext.setFillColor(UIColor.green.cgColor)
                context.cgContext.fillEllipse(in: innerRect)
                
                // Draw white stroke on inner circle
                context.cgContext.setStrokeColor(UIColor.white.cgColor)
                context.cgContext.setLineWidth(3.0)
                context.cgContext.addEllipse(in: innerRect)
                context.cgContext.strokePath()
            }
            
            marker.icon = icon
            marker.groundAnchor = CGPoint(x: 0.5, y: 0.5) // Center the icon on the coordinate
        }
        
        /// Clear user location marker
        func clearUserLocationMarker(on mapView: GMSMapView) {
            if let marker = userLocationMarker {
                marker.map = nil
                userLocationMarker = nil
            }
        }
        
        /// Get center coordinate for a region (for placing markers)
        private func coordinateForRegion(_ region: PlateRegion) -> CLLocationCoordinate2D {
            // Region center coordinates (same as old Apple Maps implementation)
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
            
            return coordinates[region.id.lowercased()] ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
        }
        
        /// Clear all markers from the map
        func clearAllMarkers(on mapView: GMSMapView) {
            for (_, marker) in markers {
                marker.map = nil
            }
            markers.removeAll()
        }
        
        /// Format date for marker snippet
        private func formatDate(_ date: Date) -> String {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
        
        /// Render country boundaries from GeoJSON for map visual context only
        /// These are NOT game regions and cannot be found/selected
        private func renderCountryBoundaries(on mapView: GMSMapView) {
            // Only render once
            guard !countriesRendered else { return }
            
            // Load country boundaries from GeoJSON
            let countryBoundaries = GeoJSONLoader.loadBoundaries(from: "countries")
            
            for (countryCode, coordinates) in countryBoundaries {
                guard !coordinates.isEmpty else { continue }
                
                // Skip if already rendered
                if countryPolygons[countryCode] != nil { continue }
                
                let path = GMSMutablePath()
                for coordinate in coordinates {
                    path.add(coordinate)
                }
                path.add(coordinates[0]) // Close path
                
                let polygon = GMSPolygon(path: path)
                // Lighter colors for country boundaries (map context only)
                polygon.fillColor = UIColor(Color.Theme.primaryBlue).withAlphaComponent(0.2)
                polygon.strokeColor = UIColor.white.withAlphaComponent(0.6)
                polygon.strokeWidth = 1.5
                polygon.map = mapView
                
                countryPolygons[countryCode] = polygon
            }
            
            countriesRendered = true
        }
    }
}

/// Helper to create GMSCameraPosition from CLLocationCoordinate2D
extension GMSCameraPosition {
    static func from(
        coordinate: CLLocationCoordinate2D,
        zoom: Float = 6.0
    ) -> GMSCameraPosition {
        return GMSCameraPosition.camera(withTarget: coordinate, zoom: zoom)
    }
    
    static func from(
        center: CLLocationCoordinate2D,
        span: MKCoordinateSpan
    ) -> GMSCameraPosition {
        // Convert span to zoom level (approximate)
        let latDelta = span.latitudeDelta
        let zoom = Float(log2(360.0 / Double(latDelta)))
        
        return GMSCameraPosition.camera(withTarget: center, zoom: zoom)
    }
}


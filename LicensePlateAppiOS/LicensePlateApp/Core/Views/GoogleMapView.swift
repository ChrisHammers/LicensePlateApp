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
        mapType: GMSMapViewType = .normal,
        regions: [PlateRegion] = PlateRegion.all,
        namespace: Namespace.ID? = nil,
        mapStyle: GMSMapStyle? = nil
    ) {
        self._cameraPosition = cameraPosition
        self.foundRegionIDs = foundRegionIDs
        self.foundRegions = foundRegions
        self.showUserLocation = showUserLocation
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
        mapView.isMyLocationEnabled = showUserLocation
        mapView.settings.myLocationButton = showUserLocation
        
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
        
        return mapView
    }
    
    func updateUIView(_ mapView: GMSMapView, context: Context) {
        // Update camera position
        mapView.animate(to: cameraPosition)
        
        // Update map type
        mapView.mapType = mapType
        
        // Update user location
        mapView.isMyLocationEnabled = showUserLocation
        mapView.settings.myLocationButton = showUserLocation
        
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
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, GMSMapViewDelegate {
        var parent: GoogleMapView
        private var polygons: [String: GMSPolygon] = [:]
        private var countryPolygons: [String: GMSPolygon] = [:] // Separate storage for country boundaries (map context only)
        private var markers: [String: GMSMarker] = [:] // Storage for region markers
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
        
        /// Render markers for found regions that have location data
        func renderMarkers(
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


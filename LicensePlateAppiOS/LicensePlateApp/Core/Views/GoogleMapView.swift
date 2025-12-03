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
    let showUserLocation: Bool
    let mapType: GMSMapViewType
    let regions: [PlateRegion]
    let namespace: Namespace.ID?
    
    // Optional: Custom map style (if nil, will use preference-based style)
    let mapStyle: GMSMapStyle?
    
    init(
        cameraPosition: Binding<GMSCameraPosition>,
        foundRegionIDs: [String] = [],
        showUserLocation: Bool = false,
        mapType: GMSMapViewType = .normal,
        regions: [PlateRegion] = PlateRegion.all,
        namespace: Namespace.ID? = nil,
        mapStyle: GMSMapStyle? = nil
    ) {
        self._cameraPosition = cameraPosition
        self.foundRegionIDs = foundRegionIDs
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
        
        // Render region polygons
        context.coordinator.renderRegions(
            on: mapView,
            regions: regions,
            foundRegionIDs: foundRegionIDs
        )
        
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
        
        // Update region polygons
        context.coordinator.renderRegions(
            on: mapView,
            regions: regions,
            foundRegionIDs: foundRegionIDs
        )
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, GMSMapViewDelegate {
        var parent: GoogleMapView
        private var polygons: [String: GMSPolygon] = [:]
        private var cachedPaths: [String: GMSMutablePath] = [:]
        private var lastFoundRegionIDs: Set<String> = []
        private var lastRegionIDs: Set<String> = []
        
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
                        polygon.strokeColor = UIColor.white.withAlphaComponent(0.8)
                        polygon.strokeWidth = 2.0
                        polygon.title = region.name
                        polygon.map = mapView
                        polygons[region.id] = polygon
                    }
                    
                    // Update color based on found status
                    let isFound = foundRegionIDs.contains(region.id)
                    polygon.fillColor = isFound ? 
                        UIColor(Color.Theme.accentYellow).withAlphaComponent(0.5) : 
                        UIColor(Color.Theme.primaryBlue).withAlphaComponent(0.3)
                }
            } else if foundStatusChanged {
                // Only update colors if found status changed
                for region in regions {
                    guard let polygon = polygons[region.id] else { continue }
                    let isFound = foundRegionIDs.contains(region.id)
                    polygon.fillColor = isFound ? 
                        UIColor(Color.Theme.accentYellow).withAlphaComponent(0.5) : 
                        UIColor(Color.Theme.primaryBlue).withAlphaComponent(0.3)
                }
            }
            
            // Update tracking sets
            lastFoundRegionIDs = currentFoundSet
            lastRegionIDs = currentRegionSet
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


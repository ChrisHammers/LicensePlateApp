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
    
    // Optional: Custom map style
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
    
    func makeUIView(context: Context) -> GMSMapView {
        let mapView = GMSMapView(frame: .zero, camera: cameraPosition)
        mapView.delegate = context.coordinator
        mapView.mapType = mapType
        mapView.isMyLocationEnabled = showUserLocation
        mapView.settings.myLocationButton = showUserLocation
        
        // Apply custom map style if provided
        if let style = mapStyle {
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
        
        // Update map style
        if let style = mapStyle {
            mapView.mapStyle = style
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
        
        init(_ parent: GoogleMapView) {
            self.parent = parent
        }
        
        func renderRegions(
            on mapView: GMSMapView,
            regions: [PlateRegion],
            foundRegionIDs: [String]
        ) {
            // Clear existing polygons
            polygons.values.forEach { $0.map = nil }
            polygons.removeAll()
            
            // Get color scheme
            let unfoundColor = UIColor(Color.Theme.primaryBlue).withAlphaComponent(0.3)
            let foundColor = UIColor(Color.Theme.accentYellow).withAlphaComponent(0.5)
            let strokeColor = UIColor.white.withAlphaComponent(0.8)
            
            // Create polygon for each region
            for region in regions {
                let boundary = RegionBoundaries.boundary(for: region.id)
                guard !boundary.isEmpty else { continue }
                
                let path = GMSMutablePath()
                for coordinate in boundary {
                    path.add(coordinate)
                }
                // Close the path
                path.add(boundary[0])
                
                let polygon = GMSPolygon(path: path)
                polygon.fillColor = foundRegionIDs.contains(region.id) ? foundColor : unfoundColor
                polygon.strokeColor = strokeColor
                polygon.strokeWidth = 2.0
                polygon.title = region.name
                polygon.map = mapView
                
                polygons[region.id] = polygon
            }
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


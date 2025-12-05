//
//  GoogleMapView.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//

import SwiftUI
import GoogleMaps
import GoogleMapsUtils
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
    
    // Rendering mode toggle (for comparison testing)
    @AppStorage("useGMURendering") private var useGMURendering = false
    @AppStorage("useTileOverlayRendering") private var useTileOverlayRendering = false
    
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
        // Only update camera position if it actually changed and user is not interacting
        // This prevents the map from recentering while user is zooming/panning
        if !context.coordinator.isUserInteracting {
            let currentCamera = mapView.camera
            let newCamera = cameraPosition
            
            // Check if the difference is significant (more than just rounding errors)
            let latDiff = abs(currentCamera.target.latitude - newCamera.target.latitude)
            let lonDiff = abs(currentCamera.target.longitude - newCamera.target.longitude)
            let zoomDiff = abs(currentCamera.zoom - newCamera.zoom)
            
            // Only animate if there's a significant difference (user didn't just move it slightly)
            if latDiff > 0.001 || lonDiff > 0.001 || zoomDiff > 0.1 {
                mapView.animate(to: cameraPosition)
                context.coordinator.lastCameraPosition = cameraPosition
            }
        }
        
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
    
    // MARK: - Cleanup
    
    /// Clean up map resources when the view is removed from the hierarchy
    /// This helps reduce the duration of multiple CCTClearcutUploader instances
    func dismantleUIView(_ mapView: GMSMapView, coordinator: Coordinator) {
        // Clear all polygons
        coordinator.clearAllPolygons(on: mapView)
        
        // Clear all markers
        coordinator.clearAllMarkers(on: mapView)
        
        // Clear user location marker
        coordinator.clearUserLocationMarker(on: mapView)
        
        // Remove delegate to prevent any callbacks after view is dismantled
        mapView.delegate = nil
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, GMSMapViewDelegate {
        var parent: GoogleMapView
        private var polygons: [String: [GMSPolygon]] = [:] // Array of polygons per region (for MultiPolygon support)
        private var countryPolygons: [String: GMSPolygon] = [:] // Separate storage for country boundaries (map context only)
        private var markers: [String: GMSMarker] = [:] // Storage for region markers
        private var userLocationMarker: GMSMarker? // Custom green user location marker
        private var cachedPaths: [String: [GMSMutablePath]] = [:] // Array of paths per region (for MultiPolygon support)
        private var lastFoundRegionIDs: Set<String> = []
        private var lastRegionIDs: Set<String> = []
        private var countriesRendered = false // Track if country boundaries have been rendered
        var lastCameraPosition: GMSCameraPosition? // Track last camera position to avoid unnecessary updates
        var isUserInteracting = false // Track if user is interacting with the map
        private var lastViewportBounds: GMSVisibleRegion? // Cache viewport bounds for culling
        private var lastZoomLevel: Float = 0 // Cache zoom level for LOD
        
        // GMU rendering components
        private var gmuRenderer: GMUGeometryRenderer?
        private var gmuFeatures: [GMUFeature] = []
        private var gmuStyles: [String: GMUStyle] = [:] // Region ID -> Style mapping
        
        // Tile overlay rendering components
        private var tileLayer: RegionTileLayer?
        
        init(_ parent: GoogleMapView) {
            self.parent = parent
        }
        
        // MARK: - GMSMapViewDelegate
        
        func mapView(_ mapView: GMSMapView, willMove gesture: Bool) {
            isUserInteracting = gesture
        }
        
        func mapView(_ mapView: GMSMapView, didChange position: GMSCameraPosition) {
            // Update the binding when user moves the map to keep them in sync
            if isUserInteracting {
                lastCameraPosition = position
                // Update parent's camera position binding to match user's movement
                DispatchQueue.main.async {
                  self.parent.$cameraPosition.wrappedValue = position
                }
            }
        }
        
        func mapView(_ mapView: GMSMapView, idleAt position: GMSCameraPosition) {
            // User finished interacting - update binding to final position
            isUserInteracting = false
            lastCameraPosition = position
            
            // Check if viewport changed significantly and trigger re-render if needed
            let currentViewport = mapView.projection.visibleRegion()
            let currentZoom = position.zoom
            let zoomChangedSignificantly = abs(currentZoom - (lastZoomLevel)) > 1.0
            
            if zoomChangedSignificantly {
                lastViewportBounds = nil // Force viewport recalculation
                lastZoomLevel = currentZoom
            }
            
            DispatchQueue.main.async {
              self.parent.$cameraPosition.wrappedValue = position
            }
        }
        
        // Helper to trigger region re-render from coordinator
        private func renderRegionsIfNeeded(on mapView: GMSMapView) {
            // This will be called from the parent to trigger re-render
            // The actual rendering happens in updateUIView
        }
        
        /// Check if a region's boundary intersects with the visible viewport
        private func regionIntersectsViewport(_ region: PlateRegion, viewport: GMSVisibleRegion) -> Bool {
            let boundaries = RegionBoundaries.boundaries(for: region.id)
            guard !boundaries.isEmpty else { return false }
            
            // Get bounding box of region (from first polygon)
            let firstBoundary = boundaries[0]
            guard !firstBoundary.isEmpty else { return false }
            
            var minLat = firstBoundary[0].latitude
            var maxLat = firstBoundary[0].latitude
            var minLon = firstBoundary[0].longitude
            var maxLon = firstBoundary[0].longitude
            
            for coord in firstBoundary {
                minLat = min(minLat, coord.latitude)
                maxLat = max(maxLat, coord.latitude)
                minLon = min(minLon, coord.longitude)
                maxLon = max(maxLon, coord.longitude)
            }
            
            // Check if bounding box intersects viewport
            let viewportMinLat = min(viewport.nearLeft.latitude, viewport.nearRight.latitude, viewport.farLeft.latitude, viewport.farRight.latitude)
            let viewportMaxLat = max(viewport.nearLeft.latitude, viewport.nearRight.latitude, viewport.farLeft.latitude, viewport.farRight.latitude)
            let viewportMinLon = min(viewport.nearLeft.longitude, viewport.nearRight.longitude, viewport.farLeft.longitude, viewport.farRight.longitude)
            let viewportMaxLon = max(viewport.nearLeft.longitude, viewport.nearRight.longitude, viewport.farLeft.longitude, viewport.farRight.longitude)
            
            return !(maxLat < viewportMinLat || minLat > viewportMaxLat || maxLon < viewportMinLon || minLon > viewportMaxLon)
        }
        
        /// Get simplified boundary based on zoom level (Level of Detail)
        /// Always returns boundaries (never empty) - boundaries should always be visible
        private func getSimplifiedBoundary(_ boundary: [CLLocationCoordinate2D], zoom: Float) -> [CLLocationCoordinate2D] {
            // At very low zoom (< 5), use very aggressive simplification but still render
            if zoom < 5 {
                if boundary.count > 50 {
                    let step = max(1, boundary.count / 50)
                    let simplified = stride(from: 0, to: boundary.count, by: step).map { boundary[$0] }
                    // Always include first and last point
                    if let lastSimplified = simplified.last,
                       let lastOriginal = boundary.last,
                       (lastSimplified.latitude != lastOriginal.latitude || lastSimplified.longitude != lastOriginal.longitude) {
                        return simplified + [lastOriginal]
                    }
                    return simplified
                }
                return boundary
            }
            
            // At low zoom (5-8), use aggressive simplification
            if zoom < 8 {
                if boundary.count > 100 {
                    let step = max(1, boundary.count / 100)
                    return stride(from: 0, to: boundary.count, by: step).map { boundary[$0] }
                }
                return boundary
            }
            
            // At medium zoom (8-10), use moderate simplification
            if zoom < 10 {
                if boundary.count > 500 {
                    let step = max(1, boundary.count / 500)
                    return stride(from: 0, to: boundary.count, by: step).map { boundary[$0] }
                }
                return boundary
            }
            
            // At high zoom (>= 10), use full resolution
            return boundary
        }
        
        func renderRegions(
            on mapView: GMSMapView,
            regions: [PlateRegion],
            foundRegionIDs: [String]
        ) {
            // Check which rendering mode to use
            if parent.useTileOverlayRendering {
                renderRegionsWithTileOverlay(on: mapView, regions: regions, foundRegionIDs: foundRegionIDs)
                return
            }
            
            if parent.useGMURendering {
                renderRegionsWithGMU(on: mapView, regions: regions, foundRegionIDs: foundRegionIDs)
                return
            }
            
            // Use custom rendering (existing implementation)
            #if DEBUG
            let renderStartTime = CFAbsoluteTimeGetCurrent()
            #endif
            
            let currentFoundSet = Set(foundRegionIDs)
            let currentRegionSet = Set(regions.map { $0.id })
            let currentZoom = mapView.camera.zoom
            let currentViewport = mapView.projection.visibleRegion()
            
            // Check if viewport or zoom changed significantly (for LOD)
            let zoomChangedSignificantly = abs(currentZoom - lastZoomLevel) > 1.0
            let viewportChanged = lastViewportBounds == nil || zoomChangedSignificantly
            
            // Check if we need to rebuild polygons (regions changed)
            let regionsChanged = currentRegionSet != lastRegionIDs
            let foundStatusChanged = currentFoundSet != lastFoundRegionIDs
            
            // Always render all enabled regions - boundaries should always be visible
            // Viewport culling removed based on performance analysis showing:
            // - Viewport filtering takes ~4ms even when filtering everything out
            // - Performance is acceptable with all regions (37 regions in 57ms felt "snappy")
            // - Viewport culling was causing boundaries to not appear
            let visibleRegions = regions
            
            // Check what needs to be updated
            // Create new polygons if: regions changed or polygons don't exist for all regions
            let needsNewPolygons = regionsChanged || polygons.isEmpty || 
                visibleRegions.contains { region in
                    !polygons.keys.contains(region.id)
                }
            
            // Update paths if: zoom changed significantly (for LOD) or first render
            // Check BEFORE updating lastZoomLevel
            let needsPathUpdate = zoomChangedSignificantly || lastZoomLevel == 0
            
            // Clear GMU renderer and tile layer when using custom rendering (avoid conflicts)
            if gmuRenderer != nil {
                gmuRenderer?.clear()
                gmuRenderer = nil
                gmuFeatures.removeAll()
                gmuStyles.removeAll()
            }
            
            if tileLayer != nil {
                tileLayer?.map = nil
                tileLayer = nil
            }
            
            // Early exit if nothing needs to be done
            if !needsNewPolygons && !needsPathUpdate && !foundStatusChanged {
                #if DEBUG
                let totalRenderTime = CFAbsoluteTimeGetCurrent() - renderStartTime
                if totalRenderTime > 0.016 { // Only log if > 16ms (60fps threshold)
                    print("📊 PERFORMANCE: No changes - \(String(format: "%.3f", totalRenderTime * 1000))ms")
                }
                #endif
                // Update tracking sets for next time
                lastFoundRegionIDs = currentFoundSet
                lastRegionIDs = currentRegionSet
                lastViewportBounds = currentViewport
                lastZoomLevel = currentZoom
                return // Exit early - nothing to do
            }
            
            lastViewportBounds = currentViewport
            lastZoomLevel = currentZoom
            
            #if DEBUG
            let filterTime: Double = 0 // No filtering anymore
            #endif
            
            // If we need to create new polygons or update paths, rebuild them
            if needsNewPolygons || needsPathUpdate {
                #if DEBUG
                let cleanupStartTime = CFAbsoluteTimeGetCurrent()
                #endif
                
                // Remove old polygons that are no longer in the enabled regions list
                for (regionId, regionPolygons) in polygons {
                    if !currentRegionSet.contains(regionId) {
                        for polygon in regionPolygons {
                            polygon.map = nil
                        }
                        polygons.removeValue(forKey: regionId)
                        cachedPaths.removeValue(forKey: regionId)
                    }
                }
                
                #if DEBUG
                let cleanupTime = CFAbsoluteTimeGetCurrent() - cleanupStartTime
                let batchStartTime = CFAbsoluteTimeGetCurrent()
                var totalBoundaryLookupTime: Double = 0
                var totalPathCreationTime: Double = 0
                var totalPolygonCreationTime: Double = 0
                var totalCoordinates: Int = 0
                var totalPolygons: Int = 0
                var slowestRegion: (id: String, time: Double)? = nil
                #endif
                
                // Batch polygon updates using CATransaction
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                
                // Create or update polygons for visible regions only
                for region in visibleRegions {
                    #if DEBUG
                    let regionStartTime = CFAbsoluteTimeGetCurrent()
                    #endif
                    
                    #if DEBUG
                    let boundaryLookupStart = CFAbsoluteTimeGetCurrent()
                    #endif
                    let boundaries = RegionBoundaries.boundaries(for: region.id)
                    #if DEBUG
                    let boundaryLookupTime = CFAbsoluteTimeGetCurrent() - boundaryLookupStart
                    totalBoundaryLookupTime += boundaryLookupTime
                    #endif
                    
                    guard !boundaries.isEmpty else {
                        #if DEBUG
                        print("⚠️ DEBUG: Region \(region.id) has no boundaries")
                        #endif
                        continue
                    }
                    
                    // Get or create array of polygons for this region
                    var regionPolygons: [GMSPolygon]
                    if let existing = polygons[region.id] {
                        regionPolygons = existing
                    } else {
                        regionPolygons = []
                    }
                    
                    // Get or create cached paths for this region
                    var regionPaths: [GMSMutablePath]
                    if let cached = cachedPaths[region.id] {
                        regionPaths = cached
                    } else {
                        regionPaths = []
                    }
                    
                    // Ensure we have enough polygons and paths for all boundaries
                    let isFound = foundRegionIDs.contains(region.id)
                    let fillColor = isFound ? 
                        UIColor(Color.Theme.accentYellow).withAlphaComponent(0.9) : 
                        UIColor(Color.Theme.primaryBlue).withAlphaComponent(0.9)
                    
                    // Try to use pre-cached paths first (Option 1 + Option 3)
                    let cachedPathsForZoom = PolygonPathCache.shared.getCachedPaths(for: region.id, zoom: currentZoom)
                    let useCachedPaths = cachedPathsForZoom != nil && !cachedPathsForZoom!.isEmpty
                    
                    // Determine how many boundaries we need to process
                    let boundariesToProcess = useCachedPaths ? cachedPathsForZoom!.count : boundaries.count
                    
                    for polyIndex in 0..<boundariesToProcess {
                        let path: GMSMutablePath
                        let needsPathRebuild: Bool
                        let simplifiedBoundary: [CLLocationCoordinate2D]
                        
                        #if DEBUG
                        let pathStartTime = CFAbsoluteTimeGetCurrent()
                        #endif
                        
                        if useCachedPaths {
                            // Use pre-cached path (Option 1) - much faster!
                            if polyIndex < cachedPathsForZoom!.count && !cachedPathsForZoom![polyIndex].isEmpty {
                                path = cachedPathsForZoom![polyIndex][0] // Use first path from cached array
                                needsPathRebuild = false // Path is already created and simplified
                                // Get simplified boundary for coordinate counting
                                if let simplified = PolygonPathCache.shared.getSimplifiedBoundaries(for: region.id, zoom: currentZoom),
                                   polyIndex < simplified.count {
                                    simplifiedBoundary = simplified[polyIndex]
                                } else {
                                    simplifiedBoundary = [] // Fallback
                                }
                            } else {
                                continue // Skip if cached path not available
                            }
                        } else {
                            // Fallback: create path on the fly (when cache isn't ready yet)
                            let boundary = boundaries[polyIndex]
                            simplifiedBoundary = getSimplifiedBoundary(boundary, zoom: currentZoom)
                            
                            // Skip rendering if boundary is empty (very low zoom)
                            if simplifiedBoundary.isEmpty {
                                #if DEBUG
                                if polyIndex == 0 {
                                    print("⚠️ DEBUG: Region \(region.id) boundary simplified to empty at zoom \(currentZoom)")
                                }
                                #endif
                                // Hide polygon if it exists
                                if polyIndex < regionPolygons.count {
                                    regionPolygons[polyIndex].map = nil
                                }
                                continue
                            }
                            
                            // Create or reuse cached path
                            if polyIndex < regionPaths.count {
                                path = regionPaths[polyIndex]
                                // Only rebuild path if zoom changed significantly (for LOD) or polygon is new
                                needsPathRebuild = needsPathUpdate || polyIndex >= regionPolygons.count
                                if needsPathRebuild {
                                    path.removeAllCoordinates()
                                    for coordinate in simplifiedBoundary {
                                        path.add(coordinate)
                                    }
                                    // Close the path
                                    if !simplifiedBoundary.isEmpty {
                                        path.add(simplifiedBoundary[0])
                                    }
                                }
                            } else {
                                path = GMSMutablePath()
                                for coordinate in simplifiedBoundary {
                                    path.add(coordinate)
                                }
                                // Close the path
                                if !simplifiedBoundary.isEmpty {
                                    path.add(simplifiedBoundary[0])
                                }
                                regionPaths.append(path)
                                needsPathRebuild = true
                            }
                        }
                        
                        #if DEBUG
                        totalCoordinates += simplifiedBoundary.count
                        let pathTime = CFAbsoluteTimeGetCurrent() - pathStartTime
                        totalPathCreationTime += pathTime
                        #endif
                        
                        #if DEBUG
                        let polygonStartTime = CFAbsoluteTimeGetCurrent()
                        #endif
                        
                        // Create or update polygon
                        let polygon: GMSPolygon
                        let isNewPolygon: Bool
                        if polyIndex < regionPolygons.count {
                            polygon = regionPolygons[polyIndex]
                            isNewPolygon = false
                            // Only update path if it was rebuilt
                            if needsPathRebuild {
                                polygon.path = path
                            }
                        } else {
                            polygon = GMSPolygon(path: path)
                            isNewPolygon = true
                            // Set properties once for new polygons
                            polygon.strokeColor = UIColor.white.withAlphaComponent(0.9)
                            polygon.strokeWidth = 2.0
                            polygon.title = region.name
                            polygon.fillColor = fillColor
                            polygon.map = mapView
                            regionPolygons.append(polygon)
                        }
                        
                        // Only update color for existing polygons if found status changed or during rebuilds
                        if !isNewPolygon && (needsNewPolygons || needsPathUpdate || foundStatusChanged) {
                            polygon.fillColor = fillColor
                        }
                        
                        #if DEBUG
                        let polygonTime = CFAbsoluteTimeGetCurrent() - polygonStartTime
                        totalPolygonCreationTime += polygonTime
                        totalPolygons += 1
                        #endif
                    }
                    
                    // Remove any extra polygons/paths if boundaries count decreased
                    if regionPolygons.count > boundaries.count {
                        for i in boundaries.count..<regionPolygons.count {
                            regionPolygons[i].map = nil
                        }
                        regionPolygons.removeSubrange(boundaries.count..<regionPolygons.count)
                        regionPaths.removeSubrange(boundaries.count..<regionPaths.count)
                    }
                    
                    // Store updated arrays
                    polygons[region.id] = regionPolygons
                    cachedPaths[region.id] = regionPaths
                    
                    #if DEBUG
                    let regionTime = CFAbsoluteTimeGetCurrent() - regionStartTime
                    if slowestRegion == nil || regionTime > slowestRegion!.time {
                        slowestRegion = (region.id, regionTime)
                    }
                    #endif
                }
                
                #if DEBUG
                let batchTime = CFAbsoluteTimeGetCurrent() - batchStartTime
                #endif
                
                // Commit batched updates
                CATransaction.commit()
                
                #if DEBUG
                let totalRenderTime = CFAbsoluteTimeGetCurrent() - renderStartTime
                print("""
                    📊 PERFORMANCE: renderRegions
                    ├─ Total time: \(String(format: "%.3f", totalRenderTime * 1000))ms
                    ├─ Viewport filtering: \(String(format: "%.3f", filterTime * 1000))ms
                    ├─ Cleanup: \(String(format: "%.3f", cleanupTime * 1000))ms
                    ├─ Batch operations: \(String(format: "%.3f", batchTime * 1000))ms
                    ├─ Boundary lookups: \(String(format: "%.3f", totalBoundaryLookupTime * 1000))ms (avg: \(String(format: "%.3f", totalBoundaryLookupTime / Double(visibleRegions.count) * 1000))ms per region)
                    ├─ Path creation: \(String(format: "%.3f", totalPathCreationTime * 1000))ms
                    ├─ Polygon creation: \(String(format: "%.3f", totalPolygonCreationTime * 1000))ms
                    ├─ Regions rendered: \(visibleRegions.count) / \(regions.count)
                    ├─ Total polygons: \(totalPolygons)
                    ├─ Total coordinates: \(totalCoordinates) (avg: \(totalPolygons > 0 ? totalCoordinates / totalPolygons : 0) per polygon)
                    └─ Slowest region: \(slowestRegion?.id ?? "none") (\(String(format: "%.3f", (slowestRegion?.time ?? 0) * 1000))ms)
                    """)
                #endif
            } else if foundStatusChanged {
                #if DEBUG
                let colorUpdateStartTime = CFAbsoluteTimeGetCurrent()
                #endif
                
                // Only update colors if found status changed (defer if user is interacting)
                if !isUserInteracting {
                    // Batch color updates
                    CATransaction.begin()
                    CATransaction.setDisableActions(true)
                    
                    for region in visibleRegions {
                        guard let regionPolygons = polygons[region.id] else { continue }
                        let isFound = foundRegionIDs.contains(region.id)
                        let fillColor = isFound ? 
                            UIColor(Color.Theme.accentYellow).withAlphaComponent(0.9) : 
                            UIColor(Color.Theme.primaryBlue).withAlphaComponent(0.9)
                        
                        // Update all polygons for this region
                        for polygon in regionPolygons {
                            polygon.fillColor = fillColor
                        }
                    }
                    
                    CATransaction.commit()
                } else {
                    // Defer color updates until user stops interacting
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                        guard let self = self, !self.isUserInteracting else { return }
                        CATransaction.begin()
                        CATransaction.setDisableActions(true)
                        
                        for region in visibleRegions {
                            guard let regionPolygons = self.polygons[region.id] else { continue }
                            let isFound = foundRegionIDs.contains(region.id)
                            let fillColor = isFound ? 
                                UIColor(Color.Theme.accentYellow).withAlphaComponent(0.9) : 
                                UIColor(Color.Theme.primaryBlue).withAlphaComponent(0.9)
                            
                            for polygon in regionPolygons {
                                polygon.fillColor = fillColor
                            }
                        }
                        
                        CATransaction.commit()
                    }
                }
                
                #if DEBUG
                let colorUpdateTime = CFAbsoluteTimeGetCurrent() - colorUpdateStartTime
                let totalRenderTime = CFAbsoluteTimeGetCurrent() - renderStartTime
                print("📊 PERFORMANCE: Color update only - \(String(format: "%.3f", colorUpdateTime * 1000))ms (total: \(String(format: "%.3f", totalRenderTime * 1000))ms)")
                #endif
            } else {
                #if DEBUG
                let totalRenderTime = CFAbsoluteTimeGetCurrent() - renderStartTime
                if totalRenderTime > 0.016 { // Only log if > 16ms (60fps threshold)
                    print("📊 PERFORMANCE: No changes - \(String(format: "%.3f", totalRenderTime * 1000))ms")
                }
                #endif
            }
            
            // Update tracking sets
            lastFoundRegionIDs = currentFoundSet
            lastRegionIDs = currentRegionSet
            
            // Render country boundaries for map context (only if region borders are enabled)
          // TODO: should this be a different toggle?
            if parent.shouldShowRegionBorders {
           //     renderCountryBoundaries(on: mapView)
            }
        }
        
        /// Clear all polygons from the map (when region borders are disabled)
        func clearAllPolygons(on mapView: GMSMapView) {
            // Remove all game region polygons (iterate through arrays)
            for (_, regionPolygons) in polygons {
                for polygon in regionPolygons {
                    polygon.map = nil
                }
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
            
            for (countryCode, polygons) in countryBoundaries {
                guard !polygons.isEmpty else { continue }
                
                // Skip if already rendered
                if countryPolygons[countryCode] != nil { continue }
                
                // For countries, we'll render the first polygon (most countries are single polygons)
                // If a country has multiple polygons (like islands), we could render all of them
                // For now, we'll use the first one for simplicity
                let coordinates = polygons[0]
                guard !coordinates.isEmpty else { continue }
                
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
        
        // MARK: - Tile Overlay Rendering
        
        /// Render regions using TileOverlay for better performance
        func renderRegionsWithTileOverlay(
            on mapView: GMSMapView,
            regions: [PlateRegion],
            foundRegionIDs: [String]
        ) {
            // Clear custom polygons and GMU renderer when using tile overlay
            if !polygons.isEmpty {
                for (_, regionPolygons) in polygons {
                    for polygon in regionPolygons {
                        polygon.map = nil
                    }
                }
                polygons.removeAll()
            }
            
            if gmuRenderer != nil {
                gmuRenderer?.clear()
                gmuRenderer = nil
                gmuFeatures.removeAll()
                gmuStyles.removeAll()
            }
            
            let currentFoundSet = Set(foundRegionIDs)
            let currentRegionSet = Set(regions.map { $0.id })
            let regionsChanged = currentRegionSet != lastRegionIDs
            let foundStatusChanged = currentFoundSet != lastFoundRegionIDs
            
            // Create or update tile layer
            if tileLayer == nil || regionsChanged {
                // Remove old tile layer
                tileLayer?.map = nil
                
                // Create new tile layer
                tileLayer = RegionTileLayer(regions: regions, foundRegionIDs: foundRegionIDs)
                tileLayer?.map = mapView
                
                #if DEBUG
                print("📊 PERFORMANCE: renderRegions (TileOverlay) - Tile layer created")
                #endif
            } else if foundStatusChanged {
                // Update found regions (colors will change)
                tileLayer?.updateFoundRegions(foundRegionIDs)
                
                #if DEBUG
                print("📊 PERFORMANCE: renderRegions (TileOverlay) - Colors updated")
                #endif
            }
            
            // Update tracking
            lastFoundRegionIDs = currentFoundSet
            lastRegionIDs = currentRegionSet
        }
        
        // MARK: - GMU Rendering
        
        /// Render regions using Google Maps Utils (GMU) for comparison
        /// NOTE: If you see compilation errors, please share them so we can fix the GMU 6.0.0 API usage
        func renderRegionsWithGMU(
            on mapView: GMSMapView,
            regions: [PlateRegion],
            foundRegionIDs: [String]
        ) {
            #if DEBUG
            let renderStartTime = CFAbsoluteTimeGetCurrent()
            #endif
            
            let currentFoundSet = Set(foundRegionIDs)
            let currentRegionSet = Set(regions.map { $0.id })
            let regionsChanged = currentRegionSet != lastRegionIDs
            let foundStatusChanged = currentFoundSet != lastFoundRegionIDs
            
            // Clear custom polygons when using GMU (avoid conflicts)
            if !polygons.isEmpty {
                for (_, regionPolygons) in polygons {
                    for polygon in regionPolygons {
                        polygon.map = nil
                    }
                }
                polygons.removeAll()
                cachedPaths.removeAll()
            }
            
            // Clear existing GMU renderer if regions changed
            if regionsChanged {
                gmuRenderer?.clear()
                gmuRenderer = nil
                gmuFeatures.removeAll()
                gmuStyles.removeAll()
            }
            
            // Create or update GMU renderer
            if gmuRenderer == nil || regionsChanged {
                // Build GeoJSON features from regions
                var features: [GMUFeature] = []
                
                for region in regions {
                    let boundaries = RegionBoundaries.boundaries(for: region.id)
                    guard !boundaries.isEmpty else { continue }
                    
                    let isFound = foundRegionIDs.contains(region.id)
                    let fillColor = isFound ? 
                        UIColor(Color.Theme.accentYellow).withAlphaComponent(0.9) : 
                        UIColor(Color.Theme.primaryBlue).withAlphaComponent(0.9)
                    
                    // Create style for this region
                    // GMUStyle in 6.0.0 requires styleID parameter
                    let styleID = region.id
                    let style = GMUStyle(
                        styleID: styleID,
                        stroke: UIColor.white, // Try without alpha first
                        fill: fillColor,
                        width: 3.0, // Increase stroke width for visibility
                        scale: 1.0,
                        heading: 0,
                        anchor: CGPoint(x: 0.5, y: 0.5),
                        iconUrl: nil,
                        title: nil,
                        hasFill: true,
                        hasStroke: true
                    )
                    gmuStyles[region.id] = style
                    
                    // Create geometry for each boundary (MultiPolygon support)
                    for boundary in boundaries {
                        guard !boundary.isEmpty else { continue }
                        
                        // Create GMUPolygon using initWithPaths: (GMU 6.0.0 API)
                        // GMUPolygon.initWithPaths: expects NSArray<GMSPath *>
                        // Prepare coordinates and close polygon if needed
                        var coords: [CLLocationCoordinate2D] = boundary
                        if !boundary.isEmpty {
                            let first = boundary[0]
                            let last = boundary[boundary.count - 1]
                            // Compare coordinates manually (CLLocationCoordinate2D is not Equatable)
                            if abs(first.latitude - last.latitude) > 0.0001 || abs(first.longitude - last.longitude) > 0.0001 {
                                coords.append(boundary[0])
                            }
                        }
                        
                        // Create GMSPath from coordinates
                        // GMSPath can be created from a GMSMutablePath
                        let mutablePath = GMSMutablePath()
                        for coord in coords {
                            mutablePath.add(coord)
                        }
                        // Create immutable GMSPath from mutable path
                        let gmsPath = GMSPath(path: mutablePath)
                        let pathsArray: [GMSPath] = [gmsPath]
                        
                        // Create GMUPolygon using initWithPaths:
                        let polygon = GMUPolygon(paths: pathsArray)
                        
                        // Create feature with region ID as property
                        // GMUFeature requires [String: NSObject] and boundingBox
                        let properties: [String: NSObject] = [
                            "id": region.id as NSString,
                            "name": region.name as NSString,
                            "found": NSNumber(value: isFound)
                        ]
                        
                        // Calculate bounding box for the polygon
                        var minLat = boundary[0].latitude
                        var maxLat = boundary[0].latitude
                        var minLon = boundary[0].longitude
                        var maxLon = boundary[0].longitude
                        
                        for coord in boundary {
                            minLat = min(minLat, coord.latitude)
                            maxLat = max(maxLat, coord.latitude)
                            minLon = min(minLon, coord.longitude)
                            maxLon = max(maxLon, coord.longitude)
                        }
                        
                        let boundingBox = GMSCoordinateBounds(
                            coordinate: CLLocationCoordinate2D(latitude: minLat, longitude: minLon),
                            coordinate: CLLocationCoordinate2D(latitude: maxLat, longitude: maxLon)
                        )
                        
                        // GMUFeature initializer in 6.0.0
                        let feature = GMUFeature(geometry: polygon, identifier: region.id, properties: properties, boundingBox: boundingBox)
                        
                        // Set style on feature - GMU 6.0.0 might require this
                        // Or set styleID to match the style's styleID
                        if let style = gmuStyles[region.id] {
                            feature.style = style
                            // Also try setting styleID if that property exists
                            // feature.styleID = style.styleID
                        }
                        
                        features.append(feature)
                    }
                }
                
                gmuFeatures = features
                
                // In GMU 6.0.0, ensure all features have their styles set
                // Styles should already be set on features during creation
                // Create unique style array for renderer
                var uniqueStyles: [GMUStyle] = []
                var seenStyleIDs = Set<String>()
                for feature in features {
                    if let style = feature.style,
                       !seenStyleIDs.contains(style.styleID) {
                        uniqueStyles.append(style)
                        seenStyleIDs.insert(style.styleID)
                    }
                }
                
                // If no styles were set on features, fall back to using all styles
                if uniqueStyles.isEmpty {
                    uniqueStyles = Array(gmuStyles.values)
                }
                
                // Create renderer with map, features, and styles array
                // GMUGeometryRenderer in 6.0.0 uses styles array parameter
                gmuRenderer = GMUGeometryRenderer(map: mapView, geometries: features, styles: uniqueStyles)
                
                // Render - GMUGeometryRenderer renders automatically when created
                gmuRenderer?.render()
                
                #if DEBUG
                let totalTime = CFAbsoluteTimeGetCurrent() - renderStartTime
                let featuresWithStyles = features.filter { $0.style != nil }.count
                print("""
                    📊 PERFORMANCE: renderRegions (GMU)
                    ├─ Total time: \(String(format: "%.3f", totalTime * 1000))ms
                    ├─ Regions rendered: \(regions.count)
                    ├─ Features created: \(features.count)
                    ├─ Features with styles: \(featuresWithStyles) / \(features.count)
                    ├─ Unique styles: \(uniqueStyles.count)
                    └─ Renderer: GMUGeometryRenderer
                    """)
                #endif
            } else if foundStatusChanged {
                // Update styles for found status changes
                // In GMU 6.0.0, we need to recreate the renderer with new styles
                var updatedStyles: [GMUStyle] = []
                
                for feature in gmuFeatures {
                    if let regionId = feature.identifier {
                        let isFound = foundRegionIDs.contains(regionId)
                        let fillColor = isFound ? 
                            UIColor(Color.Theme.accentYellow).withAlphaComponent(0.9) : 
                            UIColor(Color.Theme.primaryBlue).withAlphaComponent(0.9)
                        
                        // GMUStyle requires styleID
                        let style = GMUStyle(
                            styleID: regionId,
                            stroke: UIColor.white.withAlphaComponent(0.9),
                            fill: fillColor,
                            width: 2.0,
                            scale: 1.0,
                            heading: 0,
                            anchor: CGPoint(x: 0.5, y: 0.5),
                            iconUrl: nil,
                            title: nil,
                            hasFill: true,
                            hasStroke: true
                        )
                        updatedStyles.append(style)
                        gmuStyles[regionId] = style
                    }
                }
                
                // Recreate renderer with updated styles array
                gmuRenderer?.clear()
                gmuRenderer = GMUGeometryRenderer(map: mapView, geometries: gmuFeatures, styles: updatedStyles)
                gmuRenderer?.render()
                
                #if DEBUG
                let totalTime = CFAbsoluteTimeGetCurrent() - renderStartTime
                print("📊 PERFORMANCE: renderRegions (GMU) - Color update only - \(String(format: "%.3f", totalTime * 1000))ms")
                #endif
            }
            
            // Update tracking
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


//
//  PolygonPathCache.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 12/4/25.
//

import Foundation
import GoogleMaps
import CoreLocation

/// Service to pre-cache simplified boundaries and paths for faster polygon rendering
class PolygonPathCache {
    static let shared = PolygonPathCache()
    
    // Cache simplified boundaries at different zoom levels
    private var simplifiedBoundaries: [String: [Float: [[CLLocationCoordinate2D]]]] = [:]
    
    // Cache pre-created paths (must be created on main thread)
    private var cachedPaths: [String: [Float: [[GMSMutablePath]]]] = [:]
    
    // Common zoom levels to pre-cache
    private let commonZooms: [Float] = [3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0]
    
    private var isPreloading = false
    private var preloadComplete = false
    
    private init() {}
    
    /// Pre-load simplified boundaries and paths for all regions
    /// This should be called during app startup on a background queue
    func preloadPaths(for regions: [PlateRegion]) {
        guard !isPreloading && !preloadComplete else { return }
        isPreloading = true
        
        print("🔄 Starting polygon path pre-loading for \(regions.count) regions...")
        let startTime = Date()
        
        // Pre-simplify boundaries on background queue
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            var simplifiedCount = 0
            for region in regions {
                let boundaries = RegionBoundaries.boundaries(for: region.id)
                guard !boundaries.isEmpty else { continue }
                
                var regionSimplified: [Float: [[CLLocationCoordinate2D]]] = [:]
                
                // Pre-simplify at each zoom level
                for zoom in self.commonZooms {
                    var zoomBoundaries: [[CLLocationCoordinate2D]] = []
                    
                    for boundary in boundaries {
                        let simplified = self.simplifyBoundary(boundary, zoom: zoom)
                        if !simplified.isEmpty {
                            zoomBoundaries.append(simplified)
                        }
                    }
                    
                    if !zoomBoundaries.isEmpty {
                        regionSimplified[zoom] = zoomBoundaries
                    }
                }
                
                if !regionSimplified.isEmpty {
                    self.simplifiedBoundaries[region.id] = regionSimplified
                    simplifiedCount += 1
                }
            }
            
            let simplifyTime = Date().timeIntervalSince(startTime)
            print("✅ Pre-simplified boundaries for \(simplifiedCount) regions in \(String(format: "%.2f", simplifyTime))s")
            
            // Now create paths on main thread (GMSMutablePath must be created on main thread)
            DispatchQueue.main.async {
                self.createPathsOnMainThread()
                let totalTime = Date().timeIntervalSince(startTime)
                print("✅ Polygon path pre-loading complete in \(String(format: "%.2f", totalTime))s")
                self.preloadComplete = true
                self.isPreloading = false
            }
        }
    }
    
    /// Create GMSMutablePath objects on main thread (required for UIKit objects)
    private func createPathsOnMainThread() {
        let startTime = Date()
        var pathCount = 0
        
            for (regionId, zoomBoundaries) in simplifiedBoundaries {
            var regionPaths: [Float: [[GMSMutablePath]]] = [:]
            
            for (zoom, boundaries) in zoomBoundaries {
                var zoomPaths: [[GMSMutablePath]] = []
                
                for boundary in boundaries {
                    // Each boundary becomes one path (for MultiPolygon, each part is a separate boundary)
                    let path = GMSMutablePath()
                    
                    for coord in boundary {
                        path.add(coord)
                    }
                    
                    // Close the path
                    if !boundary.isEmpty {
                        path.add(boundary[0])
                    }
                    
                    // Store as array of paths (one path per boundary part)
                    zoomPaths.append([path])
                    pathCount += 1
                }
                
                regionPaths[zoom] = zoomPaths
            }
            
            cachedPaths[regionId] = regionPaths
        }
        
        let pathTime = Date().timeIntervalSince(startTime)
        print("✅ Created \(pathCount) pre-cached paths in \(String(format: "%.2f", pathTime))s")
    }
    
    /// Get pre-simplified boundaries for a region at a specific zoom level
    func getSimplifiedBoundaries(for regionId: String, zoom: Float) -> [[CLLocationCoordinate2D]]? {
        // Find the closest cached zoom level
        let targetZoom = findClosestZoom(zoom)
        return simplifiedBoundaries[regionId]?[targetZoom]
    }
    
    /// Get pre-created paths for a region at a specific zoom level
    func getCachedPaths(for regionId: String, zoom: Float) -> [[GMSMutablePath]]? {
        // Find the closest cached zoom level
        let targetZoom = findClosestZoom(zoom)
        return cachedPaths[regionId]?[targetZoom]
    }
    
    /// Check if paths are pre-loaded for a region
    func hasCachedPaths(for regionId: String) -> Bool {
        return cachedPaths[regionId] != nil
    }
    
    /// Check if pre-loading is complete
    var isPreloadComplete: Bool {
        return preloadComplete
    }
    
    // MARK: - Helper Methods
    
    /// Find the closest cached zoom level
    private func findClosestZoom(_ zoom: Float) -> Float {
        // If zoom is less than minimum, use minimum
        if zoom < commonZooms.first! {
            return commonZooms.first!
        }
        // If zoom is greater than maximum, use maximum
        if zoom > commonZooms.last! {
            return commonZooms.last!
        }
        // Find closest zoom level
        return commonZooms.min(by: { abs($0 - zoom) < abs($1 - zoom) }) ?? commonZooms.last!
    }
    
    /// Simplify boundary based on zoom level (same logic as GoogleMapView)
    private func simplifyBoundary(_ boundary: [CLLocationCoordinate2D], zoom: Float) -> [CLLocationCoordinate2D] {
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
}


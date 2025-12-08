//
//  RegionTileLayer.swift
//  LicensePlateApp
//
//  Created for TileOverlay polygon rendering
//

import Foundation
import GoogleMaps
import CoreLocation
import UIKit
import SwiftUI

/// Tile layer that renders region boundaries as map tiles
/// This provides much better performance than individual polygons
class RegionTileLayer: GMSTileLayer {
    private let regions: [PlateRegion]
    private var foundRegionIDs: Set<String>
    private var tileCache: [String: UIImage] = [:]
    private var tileAccessOrder: [String] = [] // Track access order for LRU eviction
    private let maxCacheSize = 2000 // Increased cache size for better zoom level support
    private let cacheQueue = DispatchQueue(label: "com.licenseplateapp.tilecache", attributes: .concurrent)
    
    // Track active tile requests to prevent responding to cancelled requests
    private var activeRequests: Set<String> = [] // Set of "zoom_x_y" keys
    private let requestQueue = DispatchQueue(label: "com.licenseplateapp.tilerequests", attributes: .concurrent)
    
    init(regions: [PlateRegion], foundRegionIDs: [String]) {
        self.regions = regions
        self.foundRegionIDs = Set(foundRegionIDs)
        super.init()
    }
    
    // GMSTileLayer requires overriding requestTileFor method
    // The receiver is a GMSTileReceiver object, not a closure
    override func requestTileFor(x: UInt, y: UInt, zoom: UInt, receiver: GMSTileReceiver) {
        let baseTileKey = "\(zoom)_\(x)_\(y)"
        
        #if DEBUG
        print("🔵 Tile requested: \(baseTileKey)")
        #endif
        
        // Capture requestQueue and other values for use in nested functions
        let requestQueue = self.requestQueue
        let capturedReceiver = receiver
        let capturedX = x
        let capturedY = y
        let capturedZoom = zoom
        let capturedBaseTileKey = baseTileKey
        
        // Mark request as active
        requestQueue.async(flags: .barrier) { [weak self] in
            self?.activeRequests.insert(capturedBaseTileKey)
        }
        
        // Helper function to safely respond only if request is still active
        func safeRespond(image: UIImage?) {
            requestQueue.async(flags: .barrier) { [weak self] in
                guard let self = self else { return }
                
                // Check if request is still active
                guard self.activeRequests.contains(capturedBaseTileKey) else {
                    #if DEBUG
                    print("⚠️ Request \(capturedBaseTileKey) was cancelled - not responding")
                    #endif
                    return
                }
                
                // Remove from active requests
                self.activeRequests.remove(capturedBaseTileKey)
                
                // Respond on main thread
                DispatchQueue.main.async {
                    // Double-check map is still attached
                    if self.map != nil {
                        capturedReceiver.receiveTileWith(x: capturedX, y: capturedY, zoom: capturedZoom, image: image)
                    }
                }
            }
        }
        
        // Check cache first
        cacheQueue.async { [weak self] in
            guard let self = self else {
                return
            }
            
            // Get found region IDs that intersect with this tile (for cache key)
            let bounds = self.tileBounds(x: x, y: y, zoom: zoom)
            let intersectingFoundRegions = self.getFoundRegionsIntersectingTile(tileBounds: bounds)
            
            // Create cache key that includes found region state
            let tileKey = self.createCacheKey(
                baseKey: baseTileKey,
                foundRegionIDs: intersectingFoundRegions
            )
            
            // Check in-memory cache first (with found region state)
            if let cachedTile = self.tileCache[tileKey] {
                #if DEBUG
                print("💨 Using cached tile \(baseTileKey) from memory")
                #endif
                // Move to end (most recently used) - LRU tracking
                self.cacheQueue.async(flags: .barrier) {
                    if let index = self.tileAccessOrder.firstIndex(of: tileKey) {
                        self.tileAccessOrder.remove(at: index)
                    }
                    self.tileAccessOrder.append(tileKey)
                }
                safeRespond(image: cachedTile)
                return
            }
            
            // Check for pre-rendered base tile from disk cache
            if TileCacheService.shared.hasCachedTile(zoom: zoom, x: x, y: y) {
                // Load base tile and overlay found regions
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    guard let self = self, self.map != nil else {
                        // Cancel request if tile layer is removed
                        requestQueue.async(flags: .barrier) { [weak self] in
                            self?.activeRequests.remove(capturedBaseTileKey)
                        }
                        return
                    }
                    
                    let loadStartTime = Date()
                    if let baseTile = TileCacheService.shared.loadCachedTile(zoom: zoom, x: x, y: y) {
                        let loadTime = Date().timeIntervalSince(loadStartTime) * 1000 // Convert to ms
                        
                        #if DEBUG
                        print("💾 Loaded pre-rendered tile \(baseTileKey) from disk in \(String(format: "%.2f", loadTime))ms")
                        #endif
                        
                        // If no found regions intersect this tile, use base tile directly
                        let tile: UIImage?
                        if intersectingFoundRegions.isEmpty {
                            tile = baseTile
                            #if DEBUG
                            print("   ✅ Using pre-rendered tile directly (no found regions)")
                            #endif
                        } else {
                            // Overlay found regions on base tile
                            let overlayStartTime = Date()
                            tile = self.overlayFoundRegions(
                                on: baseTile,
                                x: x,
                                y: y,
                                zoom: zoom,
                                intersectingFoundRegionIDs: intersectingFoundRegions
                            )
                            let overlayTime = Date().timeIntervalSince(overlayStartTime) * 1000
                            #if DEBUG
                            print("   🎨 Overlaid \(intersectingFoundRegions.count) found regions in \(String(format: "%.2f", overlayTime))ms")
                            #endif
                        }
                        
                        guard let finalTile = tile else {
                            safeRespond(image: nil)
                            return
                        }
                        
                        // Cache the final tile with found region state in key
                        self.cacheQueue.async(flags: .barrier) {
                            self.tileCache[tileKey] = finalTile
                            if let index = self.tileAccessOrder.firstIndex(of: tileKey) {
                                self.tileAccessOrder.remove(at: index)
                            }
                            self.tileAccessOrder.append(tileKey)
                            
                            // LRU eviction
                            while self.tileCache.count > self.maxCacheSize {
                                if let oldestKey = self.tileAccessOrder.first {
                                    self.tileCache.removeValue(forKey: oldestKey)
                                    self.tileAccessOrder.removeFirst()
                                } else {
                                    break
                                }
                            }
                        }
                        
                        safeRespond(image: finalTile)
                        return
                    }
                }
            }
            
            // Generate tile on background thread (fallback if no cached base tile)
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self, self.map != nil else {
                    // Cancel request if tile layer is removed
                    requestQueue.async(flags: .barrier) { [weak self] in
                        self?.activeRequests.remove(capturedBaseTileKey)
                    }
                    return
                }
                
                let generateStartTime = Date()
                
                // Optimization: If no found regions intersect this tile, try to use pre-rendered base tile
                let tile: UIImage?
                if intersectingFoundRegions.isEmpty {
                    // No found regions - try to load pre-rendered base tile from disk
                    if TileCacheService.shared.hasCachedTile(zoom: zoom, x: x, y: y) {
                        let loadStartTime = Date()
                        if let baseTile = TileCacheService.shared.loadCachedTile(zoom: zoom, x: x, y: y) {
                            let loadTime = Date().timeIntervalSince(loadStartTime) * 1000
                            #if DEBUG
                            print("💾 Loaded pre-rendered tile \(baseTileKey) from disk (fallback path) in \(String(format: "%.2f", loadTime))ms")
                            #endif
                            tile = baseTile
                        } else {
                            // Failed to load - generate base-only tile
                            #if DEBUG
                            print("⚠️ Failed to load pre-rendered tile \(baseTileKey) - generating instead")
                            #endif
                            tile = self.generateTile(x: x, y: y, zoom: zoom, skipFoundRegions: true)
                        }
                    } else {
                        // No cached base tile available - generate base-only tile (skip found region rendering)
                        #if DEBUG
                        print("🔨 Generating tile \(baseTileKey) (no pre-rendered tile available, zoom level \(zoom))")
                        #endif
                        tile = self.generateTile(x: x, y: y, zoom: zoom, skipFoundRegions: true)
                    }
                } else {
                    // Found regions exist - generate full tile with overlays
                    #if DEBUG
                    print("🔨 Generating tile \(baseTileKey) with \(intersectingFoundRegions.count) found regions")
                    #endif
                    tile = self.generateTile(x: x, y: y, zoom: zoom, skipFoundRegions: false)
                }
                
                let generateTime = Date().timeIntervalSince(generateStartTime) * 1000
                #if DEBUG
                if tile != nil {
                    print("   ✅ Tile generation completed in \(String(format: "%.2f", generateTime))ms")
                }
                #endif
                
                // Double-check map is still valid before generating final response
                guard self.map != nil else {
                    #if DEBUG
                    print("⚠️ Tile layer removed during generation - discarding tile \(capturedBaseTileKey)")
                    #endif
                    // Cancel request
                    requestQueue.async(flags: .barrier) { [weak self] in
                        self?.activeRequests.remove(capturedBaseTileKey)
                    }
                    return
                }
                
                guard let finalTile = tile else {
                    safeRespond(image: nil)
                    return
                }
                
                // Cache the tile with LRU eviction (use tileKey that includes found region state)
                self.cacheQueue.async(flags: .barrier) {
                    self.tileCache[tileKey] = finalTile
                    // Add to access order (move to end if already exists)
                    if let index = self.tileAccessOrder.firstIndex(of: tileKey) {
                        self.tileAccessOrder.remove(at: index)
                    }
                    self.tileAccessOrder.append(tileKey)
                    
                    // LRU eviction: remove least recently used tiles
                    while self.tileCache.count > self.maxCacheSize {
                        if let oldestKey = self.tileAccessOrder.first {
                            self.tileCache.removeValue(forKey: oldestKey)
                            self.tileAccessOrder.removeFirst()
                        } else {
                            break
                        }
                    }
                }
                
                safeRespond(image: finalTile)
            }
        }
    }
    
    /// Get found region IDs that intersect with a tile
    /// This is used to create a cache key that includes found region state
    private func getFoundRegionsIntersectingTile(tileBounds: (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double)) -> Set<String> {
        var intersectingRegions: Set<String> = []
        
        for region in regions {
            guard foundRegionIDs.contains(region.id) else { continue }
            
            let boundaries = RegionBoundaries.fullBoundaries(for: region.id)
            guard !boundaries.isEmpty else { continue }
            
            for boundary in boundaries {
                guard !boundary.isEmpty else { continue }
                
                if polygonIntersectsTile(boundary: boundary, tileBounds: tileBounds) {
                    intersectingRegions.insert(region.id)
                    break // Found intersection, no need to check other boundaries
                }
            }
        }
        
        return intersectingRegions
    }
    
    /// Create a cache key that includes found region state
    /// This allows us to cache overlay tiles and reuse them when found regions haven't changed
    private func createCacheKey(baseKey: String, foundRegionIDs: Set<String>) -> String {
        if foundRegionIDs.isEmpty {
            // No found regions in this tile - use base key (base tile is sufficient)
            return baseKey
        }
        
        // Create a hash from sorted found region IDs for consistent cache keys
        let sortedIDs = foundRegionIDs.sorted().joined(separator: ",")
        // Use a short hash to keep key length reasonable
        let hash = sortedIDs.hashValue
        return "\(baseKey)_found:\(hash)"
    }
    
    private func generateTile(x: UInt, y: UInt, zoom: UInt, skipFoundRegions: Bool = false) -> UIImage? {
        // Tile size (Google Maps uses 256x256)
        let tileSize: Int = 256
        
        // Create bitmap context directly with RGBA format
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * tileSize
        let bitsPerComponent = 8
        
        // Allocate memory for the bitmap
        guard let context = CGContext(
            data: nil,
            width: tileSize,
            height: tileSize,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        
        // Flip the coordinate system so (0,0) is at top-left (like UIImage)
        // Core Graphics uses bottom-left origin, but we want top-left for tiles
        context.translateBy(x: 0, y: CGFloat(tileSize))
        context.scaleBy(x: 1.0, y: -1.0)
        
        // Clear to transparent
        context.clear(CGRect(x: 0, y: 0, width: tileSize, height: tileSize))
        
        // Convert tile coordinates to geographic bounds
        let bounds = tileBounds(x: x, y: y, zoom: zoom)
        
        // Render polygons that intersect with this tile
        for region in regions {
            let boundaries = RegionBoundaries.fullBoundaries(for: region.id)
            guard !boundaries.isEmpty else { continue }
            
            // Optimization: Skip found regions if skipFoundRegions is true
            // (This tile has no found regions, so we only need to render unfound regions)
            if skipFoundRegions && foundRegionIDs.contains(region.id) {
                continue
            }
            
            #if DEBUG
            print("🟢 Rendering region \(region.id) for tile \(zoom)_\(x)_\(y)")
            #endif
            
            let isFound = foundRegionIDs.contains(region.id)
            let fillColor = isFound ?
                UIColor(Color.Theme.accentYellow).withAlphaComponent(0.9) :
                UIColor(Color.Theme.primaryBlue).withAlphaComponent(0.9)
            let strokeColor = UIColor.white.withAlphaComponent(0.9)
            
            // Render each boundary (MultiPolygon support)
            for boundary in boundaries {
                guard !boundary.isEmpty else { continue }
                
                // Check if polygon intersects with tile bounds
                if polygonIntersectsTile(boundary: boundary, tileBounds: bounds) {
                    renderPolygon(
                        boundary: boundary,
                        tileBounds: bounds,
                        tileSize: CGFloat(tileSize),
                        fillColor: fillColor,
                        strokeColor: strokeColor,
                        context: context
                    )
                }
            }
        }
        
        // Create UIImage from the bitmap context
        guard let cgImage = context.makeImage() else {
            return nil
        }
        
        return UIImage(cgImage: cgImage)
    }
    
    private func tileBounds(x: UInt, y: UInt, zoom: UInt) -> (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double) {
        let n = pow(2.0, Double(zoom))
        let minLon = (Double(x) / n) * 360.0 - 180.0
        let maxLon = ((Double(x) + 1) / n) * 360.0 - 180.0
        let minLat = atan(sinh(.pi * (1 - 2 * Double(y + 1) / n))) * 180.0 / .pi
        let maxLat = atan(sinh(.pi * (1 - 2 * Double(y) / n))) * 180.0 / .pi
        
        return (minLat: minLat, maxLat: maxLat, minLon: minLon, maxLon: maxLon)
    }
    
    private func polygonIntersectsTile(boundary: [CLLocationCoordinate2D], tileBounds: (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double)) -> Bool {
        // Simple bounding box check
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
        
        // Check if bounding boxes intersect
        return !(maxLat < tileBounds.minLat || minLat > tileBounds.maxLat ||
                 maxLon < tileBounds.minLon || minLon > tileBounds.maxLon)
    }
    
    private func renderPolygon(
        boundary: [CLLocationCoordinate2D],
        tileBounds: (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double),
        tileSize: CGFloat,
        fillColor: UIColor,
        strokeColor: UIColor,
        context: CGContext
    ) {
        guard !boundary.isEmpty else { return }
        
        // Clip drawing to tile bounds to prevent rendering artifacts
        context.saveGState()
        context.clip(to: CGRect(x: 0, y: 0, width: tileSize, height: tileSize))
        
        // Convert geographic coordinates to tile pixel coordinates
        let path = CGMutablePath()
        var firstPoint = true
        
        for coord in boundary {
            let point = coordinateToTilePoint(
                coord: coord,
                tileBounds: tileBounds,
                tileSize: tileSize
            )
            
            // Clamp point to tile bounds to prevent rendering artifacts
            // This ensures points outside the tile don't cause visual glitches
            let clampedPoint = CGPoint(
                x: max(-tileSize * 0.1, min(tileSize * 1.1, point.x)), // Allow slight overflow for smooth edges
                y: max(-tileSize * 0.1, min(tileSize * 1.1, point.y))
            )
            
            if firstPoint {
                path.move(to: clampedPoint)
                firstPoint = false
            } else {
                path.addLine(to: clampedPoint)
            }
        }
        
        // Close path
        if !boundary.isEmpty {
            let firstCoord = boundary[0]
            let firstPoint = coordinateToTilePoint(
                coord: firstCoord,
                tileBounds: tileBounds,
                tileSize: tileSize
            )
            let clampedFirstPoint = CGPoint(
                x: max(-tileSize * 0.1, min(tileSize * 1.1, firstPoint.x)),
                y: max(-tileSize * 0.1, min(tileSize * 1.1, firstPoint.y))
            )
            path.addLine(to: clampedFirstPoint)
        }
        
        // Fill polygon
        context.setFillColor(fillColor.cgColor)
        context.setStrokeColor(strokeColor.cgColor)
        context.setLineWidth(2.0)
        context.setLineCap(.round) // Smoother line endings
        context.setLineJoin(.round) // Smoother line corners
        context.addPath(path)
        context.drawPath(using: .fillStroke)
        
        context.restoreGState()
    }
    
    private func coordinateToTilePoint(
        coord: CLLocationCoordinate2D,
        tileBounds: (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double),
        tileSize: CGFloat
    ) -> CGPoint {
        let latRange = tileBounds.maxLat - tileBounds.minLat
        let lonRange = tileBounds.maxLon - tileBounds.minLon
        
        // Handle edge cases (prevent division by zero)
        guard latRange > 0 && lonRange > 0 else {
            return CGPoint(x: 0, y: 0)
        }
        
        // X coordinate: longitude maps directly (left to right)
        let x = CGFloat((coord.longitude - tileBounds.minLon) / lonRange) * tileSize
        
        // Y coordinate: latitude maps from top (maxLat) to bottom (minLat)
        // With the context flipped, y=0 is at top, so maxLat should map to y=0
        let y = CGFloat((tileBounds.maxLat - coord.latitude) / latRange) * tileSize
        
        return CGPoint(x: x, y: y)
    }
    
    /// Overlay found regions (yellow) on a base tile (blue)
    /// This is much faster than regenerating the entire tile
    /// - Parameter intersectingFoundRegionIDs: Only found region IDs that intersect with this tile (optimization)
    private func overlayFoundRegions(
        on baseTile: UIImage,
        x: UInt,
        y: UInt,
        zoom: UInt,
        intersectingFoundRegionIDs: Set<String>
    ) -> UIImage? {
        // If no regions intersect this tile, return base tile as-is
        guard !intersectingFoundRegionIDs.isEmpty else {
            return baseTile
        }
        
        let tileSize: Int = 256
        let bounds = tileBounds(x: x, y: y, zoom: zoom)
        
        // Use same approach as generateTile for consistency
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * tileSize
        let bitsPerComponent = 8
        
        guard let context = CGContext(
            data: nil,
            width: tileSize,
            height: tileSize,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return baseTile
        }
        
        // Draw base tile first in unflipped coordinate system
        // The base tile UIImage is in top-left origin (correct visual orientation)
        if let cgImage = baseTile.cgImage {
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: tileSize, height: tileSize))
        }
        
        // Now flip coordinate system for polygon rendering
        // This matches how the base tile was originally generated
        // coordinateToTilePoint expects flipped context (y=0 at top)
        context.translateBy(x: 0, y: CGFloat(tileSize))
        context.scaleBy(x: 1.0, y: -1.0)
        
        // Overlay found regions with yellow (using flipped coordinate system, matching base tile generation)
        let fillColor = UIColor(Color.Theme.accentYellow).withAlphaComponent(0.9)
        let strokeColor = UIColor.white.withAlphaComponent(0.9)
        
        // Only process regions that we know intersect with this tile (optimization)
        for region in regions {
            guard intersectingFoundRegionIDs.contains(region.id) else { continue }
            
            let boundaries = RegionBoundaries.fullBoundaries(for: region.id)
            guard !boundaries.isEmpty else { continue }
            
            for boundary in boundaries {
                guard !boundary.isEmpty else { continue }
                
                // Double-check intersection (should always be true, but safety check)
                if polygonIntersectsTile(boundary: boundary, tileBounds: bounds) {
                    renderPolygon(
                        boundary: boundary,
                        tileBounds: bounds,
                        tileSize: CGFloat(tileSize),
                        fillColor: fillColor,
                        strokeColor: strokeColor,
                        context: context
                    )
                }
            }
        }
        
        guard let cgImage = context.makeImage() else {
            return baseTile
        }
        
        return UIImage(cgImage: cgImage)
    }
    
    /// Update found regions (for color changes)
    /// Optimized to only invalidate tiles that actually contain changed regions
    func updateFoundRegions(_ newFoundRegionIDs: [String]) {
        let oldFoundSet = self.foundRegionIDs
        let newFoundSet = Set(newFoundRegionIDs)
        
        // Find regions that changed status (found -> unfound or unfound -> found)
        let newlyFound = newFoundSet.subtracting(oldFoundSet)
        let newlyUnfound = oldFoundSet.subtracting(newFoundSet)
        let changedRegions = newlyFound.union(newlyUnfound)
        
        #if DEBUG
        if !changedRegions.isEmpty {
            print("🔄 Found regions changed: \(changedRegions.count) regions")
            print("   Newly found: \(newlyFound.count), Newly unfound: \(newlyUnfound.count)")
        }
        #endif
        
        // Update the found region set
        self.foundRegionIDs = newFoundSet
        
        // If no regions changed, no need to invalidate anything
        guard !changedRegions.isEmpty else {
            #if DEBUG
            print("✅ No region changes - cache remains valid")
            #endif
            return
        }
        
        // Only invalidate tiles that contain changed regions
        // Tiles that don't contain any changed regions can remain cached
        cacheQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            var tilesToRemove: [String] = []
            
            // Check each cached tile to see if it contains any changed regions
            for (tileKey, _) in self.tileCache {
                // Extract the base key (zoom_x_y) from the cache key
                let baseKey: String
                if tileKey.contains("_found:") {
                    // Extract base key from "zoom_x_y_found:hash" format
                    if let foundIndex = tileKey.range(of: "_found:") {
                        baseKey = String(tileKey[..<foundIndex.lowerBound])
                    } else {
                        baseKey = tileKey
                    }
                } else {
                    baseKey = tileKey
                }
                
                // Parse zoom, x, y from base key
                let components = baseKey.split(separator: "_")
                guard components.count == 3,
                      let zoom = UInt(components[0]),
                      let x = UInt(components[1]),
                      let y = UInt(components[2]) else {
                    // Invalid key format - remove it
                    tilesToRemove.append(tileKey)
                    continue
                }
                
                // Get tile bounds and check if any changed regions intersect
                let bounds = self.tileBounds(x: x, y: y, zoom: zoom)
                var tileContainsChangedRegion = false
                
                for region in self.regions {
                    guard changedRegions.contains(region.id) else { continue }
                    
                    let boundaries = RegionBoundaries.fullBoundaries(for: region.id)
                    for boundary in boundaries {
                        if self.polygonIntersectsTile(boundary: boundary, tileBounds: bounds) {
                            tileContainsChangedRegion = true
                            break
                        }
                    }
                    if tileContainsChangedRegion { break }
                }
                
                // If tile contains a changed region, mark it for removal
                if tileContainsChangedRegion {
                    tilesToRemove.append(tileKey)
                }
            }
            
            // Remove only the affected tiles
            for key in tilesToRemove {
                self.tileCache.removeValue(forKey: key)
                if let index = self.tileAccessOrder.firstIndex(of: key) {
                    self.tileAccessOrder.remove(at: index)
                }
            }
            
            #if DEBUG
            print("🗑️ Invalidated \(tilesToRemove.count) tiles (out of \(self.tileCache.count + tilesToRemove.count) total)")
            print("   Kept \(self.tileCache.count) tiles that don't contain changed regions")
            #endif
        }
        
        // Request tile refresh for visible tiles
        clearTileCache()
    }
    
    /// Clear tile cache and cancel all active requests
    func clearCache() {
        cacheQueue.async(flags: .barrier) {
            self.tileCache.removeAll()
            self.tileAccessOrder.removeAll()
        }
        // Cancel all active requests
        requestQueue.async(flags: .barrier) {
            self.activeRequests.removeAll()
        }
    }
    
    // Override to cancel requests when tile layer is removed
    override var map: GMSMapView? {
        didSet {
            if map == nil {
                // Cancel all active requests when tile layer is removed
                requestQueue.async(flags: .barrier) {
                    self.activeRequests.removeAll()
                }
            }
        }
    }
}


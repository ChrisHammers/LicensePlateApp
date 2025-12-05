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
    private let maxCacheSize = 500 // Increased cache size for better zoom level support
    private let cacheQueue = DispatchQueue(label: "com.licenseplateapp.tilecache", attributes: .concurrent)
    
    init(regions: [PlateRegion], foundRegionIDs: [String]) {
        self.regions = regions
        self.foundRegionIDs = Set(foundRegionIDs)
        super.init()
    }
    
    // GMSTileLayer requires overriding requestTileFor method
    // The receiver is a GMSTileReceiver object, not a closure
    override func requestTileFor(x: UInt, y: UInt, zoom: UInt, receiver: GMSTileReceiver) {
        let tileKey = "\(zoom)_\(x)_\(y)"
        
        #if DEBUG
        print("🔵 Tile requested: \(tileKey)")
        #endif
        
        // Check cache first
        cacheQueue.async { [weak self] in
            guard let self = self else {
              receiver.receiveTileWith(x:x, y:y, zoom:zoom, image:nil)
              return
            }
            
            // Check in-memory cache first
            if let cachedTile = self.tileCache[tileKey] {
                // Move to end (most recently used) - LRU tracking
                self.cacheQueue.async(flags: .barrier) {
                    if let index = self.tileAccessOrder.firstIndex(of: tileKey) {
                        self.tileAccessOrder.remove(at: index)
                    }
                    self.tileAccessOrder.append(tileKey)
                }
                DispatchQueue.main.async {
                    receiver.receiveTileWith(x: x, y: y, zoom: zoom, image: cachedTile)
                }
                return
            }
            
            // Check for pre-rendered base tile from disk cache
            if TileCacheService.shared.hasCachedTile(zoom: zoom, x: x, y: y) {
                // Load base tile and overlay found regions
                DispatchQueue.global(qos: .userInitiated).async {
                    if let baseTile = TileCacheService.shared.loadCachedTile(zoom: zoom, x: x, y: y) {
                        let tile = self.overlayFoundRegions(on: baseTile, x: x, y: y, zoom: zoom)
                        
                        // Cache the final tile
                        self.cacheQueue.async(flags: .barrier) {
                            self.tileCache[tileKey] = tile
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
                        
                        DispatchQueue.main.async {
                            receiver.receiveTileWith(x: x, y: y, zoom: zoom, image: tile)
                        }
                        return
                    }
                }
            }
            
            // Generate tile on background thread (fallback if no cached base tile)
            DispatchQueue.global(qos: .userInitiated).async {
                let tile = self.generateTile(x: x, y: y, zoom: zoom)
                
                // Cache the tile with LRU eviction
                self.cacheQueue.async(flags: .barrier) {
                    self.tileCache[tileKey] = tile
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
                
                DispatchQueue.main.async {
                    receiver.receiveTileWith(x: x, y: y, zoom: zoom, image: tile)
                }
            }
        }
    }
    
    private func generateTile(x: UInt, y: UInt, zoom: UInt) -> UIImage? {
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
            let boundaries = RegionBoundaries.boundaries(for: region.id)
            guard !boundaries.isEmpty else { continue }
            
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
        
        // Convert geographic coordinates to tile pixel coordinates
        let path = CGMutablePath()
        var firstPoint = true
        
        for coord in boundary {
            let point = coordinateToTilePoint(
                coord: coord,
                tileBounds: tileBounds,
                tileSize: tileSize
            )
            
            if firstPoint {
                path.move(to: point)
                firstPoint = false
            } else {
                path.addLine(to: point)
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
            path.addLine(to: firstPoint)
        }
        
        // Fill polygon
        context.setFillColor(fillColor.cgColor)
        context.setStrokeColor(strokeColor.cgColor)
        context.setLineWidth(2.0)
        context.setLineCap(.round) // Smoother line endings
        context.setLineJoin(.round) // Smoother line corners
        context.addPath(path)
        context.drawPath(using: .fillStroke)
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
    private func overlayFoundRegions(on baseTile: UIImage, x: UInt, y: UInt, zoom: UInt) -> UIImage? {
        // If no regions are found, return base tile as-is
        guard !foundRegionIDs.isEmpty else {
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
        
        for region in regions {
            // Only render found regions
            guard foundRegionIDs.contains(region.id) else { continue }
            
            let boundaries = RegionBoundaries.boundaries(for: region.id)
            guard !boundaries.isEmpty else { continue }
            
            for boundary in boundaries {
                guard !boundary.isEmpty else { continue }
                
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
    func updateFoundRegions(_ newFoundRegionIDs: [String]) {
        self.foundRegionIDs = Set(newFoundRegionIDs)
        // Clear cache to force regeneration with new colors
        cacheQueue.async(flags: .barrier) {
            self.tileCache.removeAll()
            self.tileAccessOrder.removeAll()
        }
        // Request tile refresh
        clearTileCache()
    }
    
    /// Clear tile cache
    func clearCache() {
        cacheQueue.async(flags: .barrier) {
            self.tileCache.removeAll()
            self.tileAccessOrder.removeAll()
        }
    }
}


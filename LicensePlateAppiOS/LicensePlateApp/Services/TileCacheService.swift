//
//  TileCacheService.swift
//  LicensePlateApp
//
//  Created for pre-rendering and caching base tiles
//

import Foundation
import CoreLocation
import UIKit
import SwiftUI

/// Service to pre-render and cache base tiles (all regions in unfound/blue color)
/// Tiles are saved to disk and can be loaded quickly, then overlaid with found region colors
class TileCacheService {
    static let shared = TileCacheService()
    
    // Configurable zoom levels to pre-render (default: 4-7)
    var preRenderZoomLevels: [UInt] = [4, 5, 6, 7] {
        didSet {
            // Ensure zoom levels are sorted
            preRenderZoomLevels.sort()
        }
    }
    
    private let cacheDirectory: URL
    private var isPreRendering = false
    private var preRenderComplete = false
    private let preRenderQueue = DispatchQueue(label: "com.licenseplateapp.tilerender", attributes: .concurrent)
    
    private init() {
        // Create cache directory in app's cache directory
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = cacheDir.appendingPathComponent("tiles", isDirectory: true)
        
        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    /// Get file URL for a cached base tile
    private func cacheURL(for zoom: UInt, x: UInt, y: UInt) -> URL {
        let filename = "base_\(zoom)_\(x)_\(y).png"
        return cacheDirectory.appendingPathComponent(filename)
    }
    
    /// Check if a base tile exists in cache
    func hasCachedTile(zoom: UInt, x: UInt, y: UInt) -> Bool {
        let url = cacheURL(for: zoom, x: x, y: y)
        return FileManager.default.fileExists(atPath: url.path)
    }
    
    /// Load a cached base tile from disk
    func loadCachedTile(zoom: UInt, x: UInt, y: UInt) -> UIImage? {
        let url = cacheURL(for: zoom, x: x, y: y)
        guard let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else {
            return nil
        }
        return image
    }
    
    /// Save a base tile to disk
    private func saveTile(_ image: UIImage, zoom: UInt, x: UInt, y: UInt) {
        let url = cacheURL(for: zoom, x: x, y: y)
        guard let data = image.pngData() else { return }
        try? data.write(to: url)
    }
    
    /// Pre-render base tiles for all regions (all unfound/blue color)
    /// This should be called during app startup on a background queue
    func preRenderBaseTiles(for regions: [PlateRegion], progressCallback: ((Double) -> Void)? = nil) {
        guard !isPreRendering && !preRenderComplete else { return }
        isPreRendering = true
        
        print("🔄 Starting tile pre-rendering for zoom levels \(preRenderZoomLevels)...")
        let startTime = Date()
        
        // Calculate total tiles to render
        var totalTiles = 0
        for zoom in preRenderZoomLevels {
            let tilesPerSide = UInt(pow(2.0, Double(zoom)))
            totalTiles += Int(tilesPerSide * tilesPerSide)
        }
        
        print("📊 Total tiles to render: \(totalTiles)")
        
        var tilesRendered = 0
        let progressLock = NSLock()
        
        // Pre-render on background queue
        preRenderQueue.async { [weak self] in
            guard let self = self else { return }
            
            for zoom in self.preRenderZoomLevels {
                let tilesPerSide = UInt(pow(2.0, Double(zoom)))
                print("🎨 Pre-rendering zoom level \(zoom) (\(tilesPerSide)×\(tilesPerSide) = \(tilesPerSide * tilesPerSide) tiles)...")
                
                for x in 0..<tilesPerSide {
                    for y in 0..<tilesPerSide {
                        // Check if tile already exists
                        if self.hasCachedTile(zoom: zoom, x: x, y: y) {
                            progressLock.lock()
                            tilesRendered += 1
                            let progress = Double(tilesRendered) / Double(totalTiles)
                            progressLock.unlock()
                            
                            DispatchQueue.main.async {
                                progressCallback?(progress)
                            }
                            continue
                        }
                        
                        // Generate base tile (all unfound/blue)
                        if let tile = self.generateBaseTile(x: x, y: y, zoom: zoom, regions: regions) {
                            self.saveTile(tile, zoom: zoom, x: x, y: y)
                        }
                        
                        progressLock.lock()
                        tilesRendered += 1
                        let progress = Double(tilesRendered) / Double(totalTiles)
                        progressLock.unlock()
                        
                        // Update progress every 10 tiles
                        if tilesRendered % 10 == 0 {
                            DispatchQueue.main.async {
                                progressCallback?(progress)
                            }
                        }
                    }
                }
                
                let zoomTime = Date().timeIntervalSince(startTime)
                print("✅ Completed zoom level \(zoom) in \(String(format: "%.2f", zoomTime))s")
            }
            
            let totalTime = Date().timeIntervalSince(startTime)
            print("✅ Tile pre-rendering complete: \(tilesRendered) tiles in \(String(format: "%.2f", totalTime))s")
            
            DispatchQueue.main.async {
                progressCallback?(1.0)
                self.preRenderComplete = true
                self.isPreRendering = false
            }
        }
    }
    
    /// Generate a base tile with all regions in unfound/blue color
    private func generateBaseTile(x: UInt, y: UInt, zoom: UInt, regions: [PlateRegion]) -> UIImage? {
        let tileSize: Int = 256
        
        // Create bitmap context
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
            return nil
        }
        
        // Flip coordinate system
        context.translateBy(x: 0, y: CGFloat(tileSize))
        context.scaleBy(x: 1.0, y: -1.0)
        
        // Clear to transparent
        context.clear(CGRect(x: 0, y: 0, width: tileSize, height: tileSize))
        
        // Convert tile coordinates to geographic bounds
        let bounds = tileBounds(x: x, y: y, zoom: zoom)
        
        // Render all regions in unfound/blue color
        let fillColor = UIColor(Color.Theme.primaryBlue).withAlphaComponent(0.9)
        let strokeColor = UIColor.white.withAlphaComponent(0.9)
        
        for region in regions {
            let boundaries = RegionBoundaries.fullBoundaries(for: region.id)
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
            return nil
        }
        
        return UIImage(cgImage: cgImage)
    }
    
    /// Convert tile coordinates to geographic bounds
    private func tileBounds(x: UInt, y: UInt, zoom: UInt) -> (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double) {
        let n = pow(2.0, Double(zoom))
        let minLon = (Double(x) / n) * 360.0 - 180.0
        let maxLon = ((Double(x) + 1) / n) * 360.0 - 180.0
        let minLat = atan(sinh(.pi * (1 - 2 * Double(y + 1) / n))) * 180.0 / .pi
        let maxLat = atan(sinh(.pi * (1 - 2 * Double(y) / n))) * 180.0 / .pi
        
        return (minLat: minLat, maxLat: maxLat, minLon: minLon, maxLon: maxLon)
    }
    
    /// Check if polygon intersects with tile bounds
    private func polygonIntersectsTile(boundary: [CLLocationCoordinate2D], tileBounds: (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double)) -> Bool {
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
        
        return !(maxLat < tileBounds.minLat || minLat > tileBounds.maxLat ||
                 maxLon < tileBounds.minLon || minLon > tileBounds.maxLon)
    }
    
    /// Render a polygon on the tile
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
        
        let path = CGMutablePath()
        var firstPoint = true
        
        for coord in boundary {
            let point = coordinateToTilePoint(
                coord: coord,
                tileBounds: tileBounds,
                tileSize: tileSize
            )
            
            // Clamp point to tile bounds to prevent rendering artifacts
            // Allow slight overflow for smooth edges at tile boundaries
            let clampedPoint = CGPoint(
                x: max(-tileSize * 0.1, min(tileSize * 1.1, point.x)),
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
        
        context.setFillColor(fillColor.cgColor)
        context.setStrokeColor(strokeColor.cgColor)
        context.setLineWidth(2.0)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.addPath(path)
        context.drawPath(using: .fillStroke)
        
        context.restoreGState()
    }
    
    /// Convert coordinate to tile point
    private func coordinateToTilePoint(
        coord: CLLocationCoordinate2D,
        tileBounds: (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double),
        tileSize: CGFloat
    ) -> CGPoint {
        let latRange = tileBounds.maxLat - tileBounds.minLat
        let lonRange = tileBounds.maxLon - tileBounds.minLon
        
        guard latRange > 0 && lonRange > 0 else {
            return CGPoint(x: 0, y: 0)
        }
        
        let x = CGFloat((coord.longitude - tileBounds.minLon) / lonRange) * tileSize
        let y = CGFloat((tileBounds.maxLat - coord.latitude) / latRange) * tileSize
        
        return CGPoint(x: x, y: y)
    }
    
    /// Check if pre-rendering is complete
    var isPreRenderComplete: Bool {
        return preRenderComplete
    }
    
    /// Clear all cached tiles (useful for testing or when boundaries change)
    func clearCache() {
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        preRenderComplete = false
    }
    
    /// Get cache size in bytes
    func getCacheSize() -> Int64 {
        guard let enumerator = FileManager.default.enumerator(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        
        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                totalSize += Int64(fileSize)
            }
        }
        return totalSize
    }
}


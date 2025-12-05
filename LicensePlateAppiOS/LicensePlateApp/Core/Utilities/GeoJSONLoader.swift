//
//  GeoJSONLoader.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//

import Foundation
import CoreLocation

/// Utility for loading and parsing GeoJSON files
struct GeoJSONLoader {
  /// Convert MultiPolygon coordinates from NSArray/Any to Swift [[[[Double]]]]
      /// Handles both NSArray (from JSONSerialization) and Swift arrays
      private static func convertToMultiPolygonArray(_ coordinates: Any) -> [[[[Double]]]]? {
          // Try direct cast first (for Swift arrays)
          if let swiftArray = coordinates as? [[[[Double]]]] {
              return swiftArray
          }
          
          // Handle NSArray from JSONSerialization
          guard let nsArray = coordinates as? NSArray else {
              #if DEBUG
              print("⚠️ DEBUG: convertToMultiPolygonArray - coordinates is not NSArray, type: \(type(of: coordinates))")
              #endif
              return nil
          }
          
          #if DEBUG
          print("🔍 DEBUG: convertToMultiPolygonArray - NSArray count: \(nsArray.count)")
          #endif
          
          var result: [[[[Double]]]] = []
          
          // MultiPolygon structure: [[[[lon, lat], ...], ...], ...]
          // First level: array of polygons
          for (polyIndex, polygonItem) in nsArray.enumerated() {
              guard let polygonArray = polygonItem as? NSArray else {
                  #if DEBUG
                  print("⚠️ DEBUG: convertToMultiPolygonArray - polygon \(polyIndex) is not NSArray, type: \(type(of: polygonItem))")
                  #endif
                  continue
              }
              
              #if DEBUG
              if polyIndex == 0 {
                  print("🔍 DEBUG: convertToMultiPolygonArray - polygon \(polyIndex) has \(polygonArray.count) rings")
              }
              #endif
              
              var polygon: [[[Double]]] = []
              
              // Second level: array of rings (exterior + holes)
              for (ringIndex, ringItem) in polygonArray.enumerated() {
                  guard let ringArray = ringItem as? NSArray else {
                      #if DEBUG
                      if ringIndex == 0 {
                          print("⚠️ DEBUG: convertToMultiPolygonArray - ring \(ringIndex) is not NSArray, type: \(type(of: ringItem))")
                      }
                      #endif
                      continue
                  }
                  
                  var ring: [[Double]] = []
                  
                  // Third level: array of coordinates
                  for (coordIndex, coordItem) in ringArray.enumerated() {
                      guard let coordArray = coordItem as? NSArray,
                            coordArray.count >= 2 else {
                          #if DEBUG
                          if coordIndex == 0 && ringIndex == 0 && polyIndex == 0 {
                              print("⚠️ DEBUG: convertToMultiPolygonArray - coord \(coordIndex) invalid, type: \(type(of: coordItem)), count: \((coordItem as? NSArray)?.count ?? -1)")
                          }
                          #endif
                          continue
                      }
                      
                      // Handle NSNumber (from JSONSerialization) or Double
                      let lon: Double
                      let lat: Double
                      
                      if let lonNum = coordArray[0] as? NSNumber {
                          lon = lonNum.doubleValue
                      } else if let lonDouble = coordArray[0] as? Double {
                          lon = lonDouble
                      } else {
                          #if DEBUG
                          if coordIndex == 0 && ringIndex == 0 && polyIndex == 0 {
                              print("⚠️ DEBUG: convertToMultiPolygonArray - lon type invalid: \(type(of: coordArray[0]))")
                          }
                          #endif
                          continue
                      }
                      
                      if let latNum = coordArray[1] as? NSNumber {
                          lat = latNum.doubleValue
                      } else if let latDouble = coordArray[1] as? Double {
                          lat = latDouble
                      } else {
                          #if DEBUG
                          if coordIndex == 0 && ringIndex == 0 && polyIndex == 0 {
                              print("⚠️ DEBUG: convertToMultiPolygonArray - lat type invalid: \(type(of: coordArray[1]))")
                          }
                          #endif
                          continue
                      }
                      
                      ring.append([lon, lat])
                  }
                  
                  if !ring.isEmpty {
                      polygon.append(ring)
                      #if DEBUG
                      if ringIndex == 0 && polyIndex == 0 {
                          print("🔍 DEBUG: convertToMultiPolygonArray - ring \(ringIndex) has \(ring.count) coordinates")
                      }
                      #endif
                  }
              }
              
              if !polygon.isEmpty {
                  result.append(polygon)
                  #if DEBUG
                  print("🔍 DEBUG: convertToMultiPolygonArray - polygon \(polyIndex) added with \(polygon.count) rings")
                  #endif
              } else {
                  #if DEBUG
                  print("⚠️ DEBUG: convertToMultiPolygonArray - polygon \(polyIndex) is EMPTY after processing")
                  #endif
              }
          }
          
          #if DEBUG
          print("🔍 DEBUG: convertToMultiPolygonArray - returning \(result.count) polygons")
          #endif
          
          return result.isEmpty ? nil : result
      }
  
    /// Load region boundaries from GeoJSON file
    /// Returns a dictionary mapping region ID to array of polygon coordinates (for MultiPolygon support)
    static func loadBoundaries(from filename: String, simplify: Bool = true) -> [String: [[CLLocationCoordinate2D]]] {
        // Try multiple lookup methods
        var url: URL?
        
        // Method 1: Try root bundle (most common)
        url = Bundle.main.url(forResource: filename, withExtension: "geojson")
        
        // Method 2: Try with .json extension (some sources use this)
        if url == nil {
            url = Bundle.main.url(forResource: filename, withExtension: "json")
        }
        
        // Method 3: Try in Resources subdirectory
        if url == nil {
            url = Bundle.main.url(forResource: filename, withExtension: "geojson", subdirectory: "Resources")
        }
        
        // Method 4: Try .json in Resources subdirectory
        if url == nil {
            url = Bundle.main.url(forResource: filename, withExtension: "json", subdirectory: "Resources")
        }
        
        // Method 5: Try finding by path (last resort)
        if url == nil {
            if let resourcePath = Bundle.main.resourcePath {
                let possiblePaths = [
                    "\(resourcePath)/\(filename).geojson",
                    "\(resourcePath)/\(filename).json",
                    "\(resourcePath)/Resources/\(filename).geojson",
                    "\(resourcePath)/Resources/\(filename).json"
                ]
                
                for path in possiblePaths {
                    if FileManager.default.fileExists(atPath: path) {
                        url = URL(fileURLWithPath: path)
                        break
                    }
                }
            }
        }
        
        // Debug: List all bundle resources if file not found
        if url == nil {
            print("⚠️ GeoJSON file not found: \(filename).geojson")
            print("   Attempted locations:")
            print("   - Bundle root: \(filename).geojson")
            print("   - Bundle root: \(filename).json")
            print("   - Resources/: Resources/\(filename).geojson")
            print("   - Resources/: Resources/\(filename).json")
            
            // Debug: List available resources
            if let resourcePath = Bundle.main.resourcePath {
                print("\n   Available resources in bundle:")
                if let contents = try? FileManager.default.contentsOfDirectory(atPath: resourcePath) {
                    let geojsonFiles = contents.filter { $0.hasSuffix(".geojson") || $0.hasSuffix(".json") }
                    if geojsonFiles.isEmpty {
                        print("   ⚠️ No .geojson or .json files found in bundle root")
                    } else {
                        for file in geojsonFiles.sorted() {
                            print("   - \(file)")
                        }
                    }
                    
                    // Check Resources subdirectory
                    let resourcesPath = "\(resourcePath)/Resources"
                    if FileManager.default.fileExists(atPath: resourcesPath),
                       let resourcesContents = try? FileManager.default.contentsOfDirectory(atPath: resourcesPath) {
                        let resourcesGeojson = resourcesContents.filter { $0.hasSuffix(".geojson") || $0.hasSuffix(".json") }
                        if !resourcesGeojson.isEmpty {
                            print("\n   Available resources in Resources/ subdirectory:")
                            for file in resourcesGeojson.sorted() {
                                print("   - Resources/\(file)")
                            }
                        }
                    }
                }
            }
            
            return [:]
        }
        
        print("✅ Found GeoJSON file at: \(url!.path)")
        
        guard let data = try? Data(contentsOf: url!) else {
            print("⚠️ Failed to read data from GeoJSON file: \(url!.path)")
            return [:]
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let features = json["features"] as? [[String: Any]] else {
            print("⚠️ Failed to parse GeoJSON file: \(url!.path)")
            print("   File exists but format is invalid. Expected FeatureCollection with features array.")
            print("   File size: \(data.count) bytes")
            
            // Try to provide more helpful error
            if let jsonDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                print("   Top-level keys found: \(jsonDict.keys.joined(separator: ", "))")
                if jsonDict["type"] != nil {
                    print("   Type: \(jsonDict["type"] ?? "unknown")")
                }
            }
            
            return [:]
        }
        
        var boundaries: [String: [[CLLocationCoordinate2D]]] = [:]
        var skippedCount = 0
        var coordinateSystemWarningShown = false
        
        for feature in features {
            guard let properties = feature["properties"] as? [String: Any],
                  let geometry = feature["geometry"] as? [String: Any],
                  let geometryType = geometry["type"] as? String,
                  let coordinates = geometry["coordinates"] else {
                skippedCount += 1
                continue
            }
            
            // Extract region ID from properties (try multiple property names)
            let regionId = (properties["id"] as? String) ??
                          (properties["region_id"] as? String) ??
                          (properties["STATE_ID"] as? String) ??
                          (properties["STUSPS"] as? String) ?? // US Census format
                          (properties["ISO_A2"] as? String) ?? // For countries
                          (properties["ISO"] as? String) ??
                          (properties["code"] as? String) ??
                          (properties["abbrev"] as? String)
            
            guard let id = regionId else {
                skippedCount += 1
                #if DEBUG
                if let name = properties["name"] as? String {
                    print("⚠️ DEBUG: Skipped feature - no ID found. Name: '\(name)'")
                    print("   Available properties: \(properties.keys.joined(separator: ", "))")
                }
                #endif
                continue
            }
            
            #if DEBUG
            // Log geometry type for debugging
            if id.lowercased() == "us-vi" || id.lowercased() == "us-mp" || id.lowercased() == "us-as" || id.lowercased() == "ca-nu" {
                print("🔍 DEBUG: Processing \(id) - Geometry type: \(geometryType)")
            }
            #endif
            
            // Parse coordinates based on geometry type
            var allPolygonCoordinates: [[CLLocationCoordinate2D]] = []
            
            if geometryType == "Polygon" {
                // Polygon: coordinates is array of rings, first ring is exterior
                if let rings = coordinates as? [[[Double]]], let exteriorRing = rings.first {
                    let polygonCoordinates = parseCoordinateArray(exteriorRing, filename: filename, regionId: id, showWarning: !coordinateSystemWarningShown, simplify: simplify)
                    if !polygonCoordinates.isEmpty {
                        allPolygonCoordinates.append(polygonCoordinates)
                        #if DEBUG
                        print("🔍 DEBUG: \(id) Polygon - parsed \(polygonCoordinates.count) coordinates")
                        #endif
                        if !coordinateSystemWarningShown {
                            coordinateSystemWarningShown = true
                        }
                    } else {
                        #if DEBUG
                        print("⚠️ DEBUG: \(id) Polygon - EMPTY after parsing!")
                        #endif
                    }
                } else {
                    #if DEBUG
                    print("⚠️ DEBUG: \(id) Polygon - FAILED to cast coordinates to [[[Double]]]")
                    print("   Coordinates type: \(type(of: coordinates))")
                    #endif
                }
            } else if geometryType == "MultiPolygon" {
                // MultiPolygon: coordinates is array of polygons, parse ALL polygons
                if let polygons = convertToMultiPolygonArray(coordinates) {
                    #if DEBUG
                    print("🔍 DEBUG: \(id) MultiPolygon - found \(polygons.count) polygons")
                    #endif
                    
                    for (polyIndex, polygon) in polygons.enumerated() {
                        if let exteriorRing = polygon.first {
                            let polygonCoordinates = parseCoordinateArray(exteriorRing, filename: filename, regionId: "\(id)-poly\(polyIndex)", showWarning: !coordinateSystemWarningShown, simplify: simplify)
                            if !polygonCoordinates.isEmpty {
                                allPolygonCoordinates.append(polygonCoordinates)
                                #if DEBUG
                                print("🔍 DEBUG: \(id) polygon \(polyIndex) - parsed \(polygonCoordinates.count) coordinates")
                                #endif
                                if !coordinateSystemWarningShown {
                                    coordinateSystemWarningShown = true
                                }
                            } else {
                                #if DEBUG
                                print("⚠️ DEBUG: \(id) polygon \(polyIndex) - EMPTY after parsing!")
                                #endif
                            }
                        } else {
                            #if DEBUG
                            print("⚠️ DEBUG: \(id) polygon \(polyIndex) - NO EXTERIOR RING!")
                            #endif
                        }
                    }
                } else {
                    #if DEBUG
                    print("⚠️ DEBUG: \(id) MultiPolygon - FAILED to convert coordinates")
                    print("   Coordinates type: \(type(of: coordinates))")
                    #endif
                }
            }
            
            if !allPolygonCoordinates.isEmpty {
                boundaries[id.lowercased()] = allPolygonCoordinates
                #if DEBUG
                print("✅ DEBUG: \(id) stored with \(allPolygonCoordinates.count) polygon(s) under key '\(id.lowercased())'")
                #endif
            } else {
                skippedCount += 1
                #if DEBUG
                print("⚠️ DEBUG: \(id) SKIPPED - no valid polygons! (will use approximate boundary)")
                #endif
            }
        }
        
        if skippedCount > 0 {
            print("⚠️ Skipped \(skippedCount) features (missing ID or invalid geometry)")
        }
        
        print("✅ Loaded \(boundaries.count) regions from \(filename).geojson")
        return boundaries
    }
    
    /// Parse coordinate array from GeoJSON format [lon, lat] to CLLocationCoordinate2D
    /// Validates coordinate ranges and detects coordinate system issues
    private static func parseCoordinateArray(_ coords: [[Double]], filename: String, regionId: String, showWarning: Bool, simplify: Bool = true) -> [CLLocationCoordinate2D] {
        guard !coords.isEmpty else { return [] }
        
        // Sample first few coordinates to detect coordinate system
        let sampleSize = min(10, coords.count)
        var hasInvalidCoordinates = false
        var maxLon: Double = -Double.infinity
        var minLon: Double = Double.infinity
        var maxLat: Double = -Double.infinity
        var minLat: Double = Double.infinity
        
        for i in 0..<sampleSize {
            guard coords[i].count >= 2 else { continue }
            let lon = coords[i][0]
            let lat = coords[i][1]
            
            maxLon = max(maxLon, lon)
            minLon = min(minLon, lon)
            maxLat = max(maxLat, lat)
            minLat = min(minLat, lat)
            
            // Check if coordinates are in valid WGS84 range (degrees)
            // Longitude: -180 to 180, Latitude: -90 to 90
            if abs(lon) > 180 || abs(lat) > 90 {
                hasInvalidCoordinates = true
            }
        }
        
        // If coordinates are out of range, they might be in a different coordinate system
        if hasInvalidCoordinates && showWarning {
            print("⚠️ WARNING: Coordinates in \(filename).geojson appear to be in wrong coordinate system!")
            print("   Region: \(regionId)")
            print("   Coordinate range: lon=[\(minLon), \(maxLon)], lat=[\(minLat), \(maxLat)]")
            print("   Expected: lon=[-180, 180], lat=[-90, 90] (WGS84 degrees)")
            print("   Your file may be in Web Mercator (EPSG:3857) or another projection.")
            print("   Please convert to WGS84 (EPSG:4326) geographic coordinates.")
            print("   You can use tools like: https://mapshaper.org/ or QGIS to reproject.")
        }
        
        // Parse all coordinates
        var parsedCoords: [CLLocationCoordinate2D] = []
        for coord in coords {
            guard coord.count >= 2 else { continue }
            let lon = coord[0]
            let lat = coord[1]
            
            // Only add if coordinates are in valid range (WGS84)
            if abs(lon) <= 180 && abs(lat) <= 90 {
                parsedCoords.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
            } else if hasInvalidCoordinates {
                // If we detected wrong coordinate system, skip this coordinate
                // (don't add invalid coordinates that would make shapes huge)
                continue
            } else {
                // If not detected as wrong system but out of range, add anyway
                // (might be edge cases like dateline crossing)
                parsedCoords.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
            }
        }
        
        // If we filtered out all coordinates due to invalid system, return empty
        if hasInvalidCoordinates && parsedCoords.isEmpty {
            print("⚠️ Skipped all coordinates for \(regionId) - wrong coordinate system")
            #if DEBUG
            print("   DEBUG: Coordinate range was lon=[\(minLon), \(maxLon)], lat=[\(minLat), \(maxLat)]")
            #endif
            return []
        }
        
        #if DEBUG
        if parsedCoords.count != coords.count {
            print("🔍 DEBUG: \(regionId) - filtered \(coords.count - parsedCoords.count) invalid coordinates (kept \(parsedCoords.count)/\(coords.count))")
        }
        #endif
        
        // Simplify coordinates if there are too many (performance optimization)
        // Keep every Nth point if there are more than 500 points (reduced from 1000 for better performance)
        // This just
        if simplify && parsedCoords.count > 500 {
            // For polygons with >2000 points, use more aggressive simplification
            let targetPointCount = parsedCoords.count > 2000 ? 1000 : 500
            let step = max(1, parsedCoords.count / targetPointCount)
            let simplified = stride(from: 0, to: parsedCoords.count, by: step).map { parsedCoords[$0] }
            // Always include first and last point if they're different
            let finalSimplified: [CLLocationCoordinate2D]
            if let lastSimplified = simplified.last,
               let lastOriginal = parsedCoords.last,
               (lastSimplified.latitude != lastOriginal.latitude || lastSimplified.longitude != lastOriginal.longitude) {
                finalSimplified = simplified + [lastOriginal]
            } else {
                finalSimplified = simplified
            }
            #if DEBUG
            print("🔍 DEBUG: \(regionId) - simplified coordinates from \(parsedCoords.count) to \(finalSimplified.count) points")
            #endif
            return finalSimplified
        }
        
        return parsedCoords
    }
    
    /// Load all region boundaries from multiple GeoJSON files
    static func loadAllBoundaries(simplify: Bool = true) -> [String: [[CLLocationCoordinate2D]]] {
        var allBoundaries: [String: [String: [[CLLocationCoordinate2D]]]] = [:]
        
        #if DEBUG
        print("🔍 DEBUG: Starting to load all GeoJSON boundaries (simplify: \(simplify))...")
        #endif
        
        // Load US states
        allBoundaries["us"] = loadBoundaries(from: "us-states", simplify: simplify)
        #if DEBUG
        print("🔍 DEBUG: Loaded \(allBoundaries["us"]?.count ?? 0) US regions")
        #endif
        
        // Load Canadian provinces
        allBoundaries["ca"] = loadBoundaries(from: "ca-provinces", simplify: simplify)
        #if DEBUG
        print("🔍 DEBUG: Loaded \(allBoundaries["ca"]?.count ?? 0) Canadian regions")
        #endif
        
        // Load Mexican states
        allBoundaries["mx"] = loadBoundaries(from: "mx-states", simplify: simplify)
        #if DEBUG
        print("🔍 DEBUG: Loaded \(allBoundaries["mx"]?.count ?? 0) Mexican regions")
        #endif
        
        // Load all countries
        //allBoundaries["countries"] = loadBoundaries(from: "countries")
        
        // Merge all boundaries into single dictionary
        var merged: [String: [[CLLocationCoordinate2D]]] = [:]
        for boundaries in allBoundaries.values {
            for (id, polygons) in boundaries {
                merged[id] = polygons
            }
        }
        
        #if DEBUG
        print("✅ DEBUG: Total regions loaded: \(merged.count)")
        #endif
        
        return merged
    }
}

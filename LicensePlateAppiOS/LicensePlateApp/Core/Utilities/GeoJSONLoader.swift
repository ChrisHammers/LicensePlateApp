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
    /// Load region boundaries from GeoJSON file
    /// Returns a dictionary mapping region ID to polygon coordinates
    static func loadBoundaries(from filename: String) -> [String: [CLLocationCoordinate2D]] {
        guard let url = Bundle.main.url(forResource: filename, withExtension: "geojson"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let features = json["features"] as? [[String: Any]] else {
            print("⚠️ Failed to load GeoJSON file: \(filename).geojson")
            return [:]
        }
        
        var boundaries: [String: [CLLocationCoordinate2D]] = [:]
        
        for feature in features {
            guard let properties = feature["properties"] as? [String: Any],
                  let geometry = feature["geometry"] as? [String: Any],
                  let geometryType = geometry["type"] as? String,
                  let coordinates = geometry["coordinates"] else {
                continue
            }
            
            // Extract region ID from properties
            let regionId = (properties["id"] as? String) ?? 
                          (properties["region_id"] as? String) ??
                          (properties["STATE_ID"] as? String) ??
                          (properties["ISO_A2"] as? String) // For countries
            
            guard let id = regionId else { continue }
            
            // Parse coordinates based on geometry type
            var polygonCoordinates: [CLLocationCoordinate2D] = []
            
            if geometryType == "Polygon" {
                // Polygon: coordinates is array of rings, first ring is exterior
                if let rings = coordinates as? [[[Double]]], let exteriorRing = rings.first {
                    polygonCoordinates = parseCoordinateArray(exteriorRing)
                }
            } else if geometryType == "MultiPolygon" {
                // MultiPolygon: coordinates is array of polygons, use first polygon's exterior
                if let polygons = coordinates as? [[[[Double]]]], 
                   let firstPolygon = polygons.first,
                   let exteriorRing = firstPolygon.first {
                    polygonCoordinates = parseCoordinateArray(exteriorRing)
                }
            }
            
            if !polygonCoordinates.isEmpty {
                boundaries[id.lowercased()] = polygonCoordinates
            }
        }
        
        print("✅ Loaded \(boundaries.count) regions from \(filename).geojson")
        return boundaries
    }
    
    /// Parse coordinate array from GeoJSON format [lon, lat] to CLLocationCoordinate2D
    private static func parseCoordinateArray(_ coords: [[Double]]) -> [CLLocationCoordinate2D] {
        return coords.compactMap { coord in
            guard coord.count >= 2 else { return nil }
            // GeoJSON uses [longitude, latitude] format
            return CLLocationCoordinate2D(latitude: coord[1], longitude: coord[0])
        }
    }
    
    /// Load all region boundaries from multiple GeoJSON files
    static func loadAllBoundaries() -> [String: [CLLocationCoordinate2D]] {
        var allBoundaries: [String: [String: [CLLocationCoordinate2D]]] = [:]
        
        // Load US states
        allBoundaries["us"] = loadBoundaries(from: "us-states")
        
        // Load Canadian provinces
        allBoundaries["ca"] = loadBoundaries(from: "ca-provinces")
        
        // Load Mexican states
        allBoundaries["mx"] = loadBoundaries(from: "mx-states")
        
        // Load all countries
        allBoundaries["countries"] = loadBoundaries(from: "countries")
        
        // Merge all boundaries into single dictionary
        var merged: [String: [CLLocationCoordinate2D]] = [:]
        for boundaries in allBoundaries.values {
            for (id, coords) in boundaries {
                merged[id] = coords
            }
        }
        
        return merged
    }
}


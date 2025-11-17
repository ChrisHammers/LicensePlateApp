//
//  Trip.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//

import Foundation
import SwiftData
import CoreLocation

/// Codable location data extracted from CLLocation
struct LocationData: Codable {
    var latitude: Double
    var longitude: Double
    var altitude: Double
    var horizontalAccuracy: Double
    var verticalAccuracy: Double
    var timestamp: Date
    
    init(from location: CLLocation) {
        self.latitude = location.coordinate.latitude
        self.longitude = location.coordinate.longitude
        self.altitude = location.altitude
        self.horizontalAccuracy = location.horizontalAccuracy
        self.verticalAccuracy = location.verticalAccuracy
        self.timestamp = location.timestamp
    }
    
    /// Convert back to CLLocation
    func toCLLocation() -> CLLocation {
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        return CLLocation(
            coordinate: coordinate,
            altitude: altitude,
            horizontalAccuracy: horizontalAccuracy,
            verticalAccuracy: verticalAccuracy,
            timestamp: timestamp
        )
    }
}

/// Metadata for a found region, tracking when, how, and who found it
struct FoundRegion: Codable, Identifiable {
    var id: String { regionID } // Use regionID as the identifier
    var regionID: String
    var foundAt: Date
    var inputMethod: InputMethod
    var foundBy: String? // User ID - will be used for shared trips
    var foundAtLocation: LocationData? // Location where the region was found
    
    enum InputMethod: String, Codable, CaseIterable {
        case list
        case voice
    }
    
    init(
        regionID: String,
        foundAt: Date = .now,
        inputMethod: InputMethod,
        foundBy: String? = nil,
        foundAtLocation: LocationData? = nil
    ) {
        self.regionID = regionID
        self.foundAt = foundAt
        self.inputMethod = inputMethod
        self.foundBy = foundBy
        self.foundAtLocation = foundAtLocation
    }
}

@Model
final class Trip {
  
    enum inputUsedToFindRegion: CaseIterable, Identifiable {
        var id: Self { self }
        
        case list
        case voice
        
        /// Convert to FoundRegion.InputMethod
        var asFoundRegionMethod: FoundRegion.InputMethod {
            switch self {
            case .list: return .list
            case .voice: return .voice
            }
        }
    }
    
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var lastUpdated: Date
    var name: String
    
    // Store found regions with metadata
    var foundRegions: [FoundRegion] = []
    
    // Trip-specific voice settings (optional for backward compatibility)
    var skipVoiceConfirmation: Bool = false
    var holdToTalk: Bool = true

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        lastUpdated: Date = .now,
        name: String,
        foundRegions: [FoundRegion] = [],
        skipVoiceConfirmation: Bool = false,
        holdToTalk: Bool = true
    ) {
        self.id = id
        self.createdAt = createdAt
        self.name = name
        self.foundRegions = foundRegions
        self.skipVoiceConfirmation = skipVoiceConfirmation
        self.holdToTalk = holdToTalk
        self.lastUpdated = lastUpdated
    }
    
    // MARK: - Computed Properties for Backward Compatibility
    
    /// Get array of region IDs (for backward compatibility)
    var foundRegionIDs: [String] {
        foundRegions.map { $0.regionID }
    }
    
    // MARK: - Region Management Methods
    
    func toggle(regionID: String,
                usingTab: inputUsedToFindRegion,
                foundBy: String? = nil,
                location: CLLocation? = nil
    ) {
        lastUpdated = Date.now
      print("Toggle of Region: \(regionID), from screen: \(usingTab) at \(lastUpdated) by User: \(foundBy) at: \(location)")
        
        if let index = foundRegions.firstIndex(where: { $0.regionID == regionID }) {
            foundRegions.remove(at: index)
        } else {
            // Default to list input method for toggle (manual selection)
            let locationData = location.map { LocationData(from: $0) }
            foundRegions.append(FoundRegion(
                regionID: regionID,
                foundAt: lastUpdated,
                inputMethod: .list,
                foundBy: nil,
                foundAtLocation: locationData
            ))
        }
    }
  
    /// Set a region as found with metadata
    func setFound(
        regionID: String,
        usingTab: inputUsedToFindRegion,
        foundBy: String? = nil,
        location: CLLocation? = nil
    ) {
        lastUpdated = Date.now
        print("Setting Region Found: \(regionID), from screen: \(usingTab) at \(lastUpdated) by User: \(foundBy) at: \(location)")
        
        let locationData = location.map { LocationData(from: $0) }
        
        // Check if already found
        if foundRegions.contains(where: { $0.regionID == regionID }) {
            print("Region \(regionID) already found.")
            // Update the existing entry with new metadata (in case method changed)
//            if let index = foundRegions.firstIndex(where: { $0.regionID == regionID }) {
//                foundRegions[index].inputMethod = usingTab.asFoundRegionMethod
//                foundRegions[index].foundAt = lastUpdated
//                if let foundBy = foundBy {
//                    foundRegions[index].foundBy = foundBy
//                }
//                if let locationData = locationData {
//                    foundRegions[index].foundAtLocation = locationData
//                }
//            }
        } else {
            // Add new found region with metadata
            foundRegions.append(FoundRegion(
                regionID: regionID,
                foundAt: lastUpdated,
                inputMethod: usingTab.asFoundRegionMethod,
                foundBy: foundBy,
                foundAtLocation: locationData
            ))
        }
    }
  
    /// Set a region as not found
    func setNotFound(regionID: String,
                     usingTab: inputUsedToFindRegion,
                     foundBy: String? = nil,
                     location: CLLocation? = nil
                 ) {
        lastUpdated = Date.now
        print("Setting Region Not Found: \(regionID), from screen: \(usingTab) at \(lastUpdated) by User: \(foundBy) at: \(location)")
        
        if let index = foundRegions.firstIndex(where: { $0.regionID == regionID }) {
            foundRegions.remove(at: index)
        } else {
            print("Region \(regionID) already not found.")
        }
    }

    /// Check if a region has been found
    func hasFound(regionID: String) -> Bool {
        foundRegions.contains(where: { $0.regionID == regionID })
    }
    
    /// Get metadata for a found region
    func getFoundRegion(regionID: String) -> FoundRegion? {
        foundRegions.first(where: { $0.regionID == regionID })
    }
    
    /// Get all regions found via a specific input method
    func regionsFoundVia(_ method: inputUsedToFindRegion) -> [FoundRegion] {
        foundRegions.filter { $0.inputMethod == method.asFoundRegionMethod }
    }
    
    /// Get all regions found by a specific user (for shared trips)
    func regionsFoundBy(userID: String) -> [FoundRegion] {
        foundRegions.filter { $0.foundBy == userID }
    }
}

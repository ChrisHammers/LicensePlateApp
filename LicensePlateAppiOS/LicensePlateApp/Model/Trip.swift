//
//  Trip.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//

import Foundation
import SwiftData

@Model
final class Trip {
  
  enum inputUsedToFindRegion: CaseIterable, Identifiable {
    var id: Self { self }
    
    case list
    case voice
    
  }
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var lastUpdated: Date
    var name: String
  // var voiceRecordedRegionsFound: a Dictionary of the regionID and the date found, so we can log it later.
    var foundRegionIDs: [String] // Do we want to include the list of countries & states/provinces involved?  If new terrorities are added to canada, we can not break this game, and then we show a checkbox on what countries to include?  NOT MVP
    
    // Trip-specific voice settings (optional for backward compatibility)
    var skipVoiceConfirmation: Bool = false
    var holdToTalk: Bool = true

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        lastUpdated: Date = .now,
        name: String,
        foundRegionIDs: [String] = [],
        skipVoiceConfirmation: Bool = false,
        holdToTalk: Bool = true
    ) {
        self.id = id
        self.createdAt = createdAt
        self.name = name
        self.foundRegionIDs = foundRegionIDs
        self.skipVoiceConfirmation = skipVoiceConfirmation
        self.holdToTalk = holdToTalk
        self.lastUpdated = lastUpdated
    }

    func toggle(regionID: String) {
      lastUpdated = Date.now
      print("Toggle of Region: \(regionID) at \(lastUpdated)")
      
      if let index = foundRegionIDs.firstIndex(of: regionID) {
            foundRegionIDs.remove(at: index)
        } else {
            foundRegionIDs.append(regionID)
        }
      
    }
  
  //The UI currently stops this from being needed, as it doens't run toggle when getting a confirmation etc.  But it makes sense to have this so we can track that data.
  func setFound(regionID: String, usingTab: inputUsedToFindRegion) {
    lastUpdated = Date.now
    print("Setting Region Found: \(regionID), from screen: \(usingTab) at \(lastUpdated)")
    
     if let _ = foundRegionIDs.firstIndex(of: regionID) {
        print("Region \(regionID) already found.")
      } else {
          foundRegionIDs.append(regionID)
      }
  }
  
  func setNotFound(regionID: String, usingTab: inputUsedToFindRegion) {
    lastUpdated = Date.now
    print("Setting Region Found: \(regionID), from screen: \(usingTab) at \(lastUpdated)")
    
     if let index = foundRegionIDs.firstIndex(of: regionID) {
          foundRegionIDs.remove(at: index)
      } else {
           print("Region \(regionID) already not found.")
      }
  }

    func hasFound(regionID: String) -> Bool {
        foundRegionIDs.contains(regionID)
    }
}

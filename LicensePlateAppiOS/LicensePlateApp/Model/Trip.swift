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
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    //var lastEditedAt: Date
    var name: String
  // var voiceRecordedRegionsFound: a Dictionary of the regionID and the date found, so we can log it later.
    var foundRegionIDs: [String] // Do we want to include the list of countries & states/provinces involved?  If new terrorities are added to canada, we can not break this game, and then we show a checkbox on what countries to include?  NOT MVP

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
     //   lastEditedAt: Date = .now,
        name: String,
        foundRegionIDs: [String] = []
    ) {
        self.id = id
        self.createdAt = createdAt
        self.name = name
        self.foundRegionIDs = foundRegionIDs
    //    self.lastEditedAt = lastEditedAt
    }

    func toggle(regionID: String) {
        if let index = foundRegionIDs.firstIndex(of: regionID) {
            foundRegionIDs.remove(at: index)
        } else {
            foundRegionIDs.append(regionID)
        }
    }

    func hasFound(regionID: String) -> Bool {
        foundRegionIDs.contains(regionID)
    }
}

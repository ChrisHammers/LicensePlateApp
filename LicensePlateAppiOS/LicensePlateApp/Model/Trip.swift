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
    var foundRegionIDs: [String]

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

//
//  User.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//

import Foundation
import SwiftData

@Model
final class AppUser {
    @Attribute(.unique) var id: String // Firebase UID or local UUID
    var userName: String
    var email: String?
    var createdAt: Date
    var lastUpdated: Date
    
    // Platform linking (structure for future implementation)
    var linkedPlatforms: [LinkedPlatform]
    
    init(
        id: String = UUID().uuidString,
        userName: String = "User",
        email: String? = nil,
        createdAt: Date = .now,
        lastUpdated: Date = .now,
        linkedPlatforms: [LinkedPlatform] = []
    ) {
        self.id = id
        self.userName = userName
        self.email = email
        self.createdAt = createdAt
        self.lastUpdated = lastUpdated
        self.linkedPlatforms = linkedPlatforms
    }
    
    func updateUserName(_ newName: String) {
        self.userName = newName
        self.lastUpdated = .now
    }
}

// Platform linking structure
struct LinkedPlatform: Codable {
    var platform: PlatformType
    var platformUserId: String
    var linkedAt: Date
    
    enum PlatformType: String, Codable {
        case google = "Google"
        case apple = "Apple"
        case facebook = "Facebook"
        case twitter = "Twitter"
        case instagram = "Instagram"
        // Add more platforms as needed
    }
}


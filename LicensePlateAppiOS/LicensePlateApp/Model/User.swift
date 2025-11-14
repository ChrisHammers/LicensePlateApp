//
//  User.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//

import Foundation
import SwiftData

// Avatar color enum
enum AvatarColor: String, Codable, CaseIterable {
    case red = "red"
    case green = "green"
    case blue = "blue"
    case orange = "orange"
    case purple = "purple"
    case yellow = "yellow"
    case white = "white"
    case black = "black"
    
    static func random() -> AvatarColor {
        AvatarColor.allCases.randomElement() ?? .blue
    }
}

// Avatar type enum
enum AvatarType: String, Codable, CaseIterable {
    case woman = "woman"
    case man = "man"
    case dog = "dog"
    case cat = "cat"
    case bird = "bird"
    case car = "car"
    case building = "building"
    
    static func random() -> AvatarType {
        AvatarType.allCases.randomElement() ?? .man
    }
}

@Model
final class AppUser {
    @Attribute(.unique) var id: String // Firebase UID or local UUID
    var userName: String
    var email: String?
    var createdAt: Date
    var lastUpdated: Date
    var avatarColor: AvatarColor
    var avatarType: AvatarType
    
    // Platform linking (structure for future implementation)
    var linkedPlatforms: [LinkedPlatform]
    
    init(
        id: String = UUID().uuidString,
        userName: String = "User",
        email: String? = nil,
        createdAt: Date = .now,
        lastUpdated: Date = .now,
        avatarColor: AvatarColor? = nil,
        avatarType: AvatarType? = nil,
        linkedPlatforms: [LinkedPlatform] = []
    ) {
        self.id = id
        self.userName = userName
        self.email = email
        self.createdAt = createdAt
        self.lastUpdated = lastUpdated
        self.avatarColor = avatarColor ?? AvatarColor.random()
        self.avatarType = avatarType ?? AvatarType.random()
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


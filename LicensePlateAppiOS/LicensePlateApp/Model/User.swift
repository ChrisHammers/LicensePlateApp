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
    @Attribute(.unique) var id: String // Primary ID - Firebase UID if authenticated, local UUID if not
    var userName: String
    var email: String?
    var phoneNumber: String?
    var createdAt: Date
    var lastUpdated: Date
    var avatarColor: AvatarColor
    var avatarType: AvatarType
    
    // Device identifier for default username generation
    var deviceIdentifier: String?
    
    // Track if username was manually changed by user
    var isUsernameManuallyChanged: Bool = false
    
    // Privacy settings for public profile
    var isEmailPublic: Bool = false
    var isPhonePublic: Bool = false
    
    // Platform linking
    var linkedPlatforms: [LinkedPlatform]
    
    // Firebase sync tracking (offline-first)
    var firebaseUID: String? // Firebase Authentication UID (nil if local-only)
    var lastSyncedToFirebase: Date? // Last successful sync to Firestore
    var needsSync: Bool = false // Flag to sync when online
    var localIDBeforeFirebase: String? // Original local ID before Firebase migration
    
    init(
        id: String = UUID().uuidString,
        userName: String = "User",
        email: String? = nil,
        phoneNumber: String? = nil,
        createdAt: Date = .now,
        lastUpdated: Date = .now,
        avatarColor: AvatarColor? = nil,
        avatarType: AvatarType? = nil,
        deviceIdentifier: String? = nil,
        isUsernameManuallyChanged: Bool = false,
        isEmailPublic: Bool = false,
        isPhonePublic: Bool = false,
        linkedPlatforms: [LinkedPlatform] = [],
        firebaseUID: String? = nil,
        lastSyncedToFirebase: Date? = nil,
        needsSync: Bool = false,
        localIDBeforeFirebase: String? = nil
    ) {
        self.id = id
        self.userName = userName
        self.email = email
        self.phoneNumber = phoneNumber
        self.createdAt = createdAt
        self.lastUpdated = lastUpdated
        self.avatarColor = avatarColor ?? AvatarColor.random()
        self.avatarType = avatarType ?? AvatarType.random()
        self.deviceIdentifier = deviceIdentifier
        self.isUsernameManuallyChanged = isUsernameManuallyChanged
        self.isEmailPublic = isEmailPublic
        self.isPhonePublic = isPhonePublic
        self.linkedPlatforms = linkedPlatforms
        self.firebaseUID = firebaseUID
        self.lastSyncedToFirebase = lastSyncedToFirebase
        self.needsSync = needsSync
        self.localIDBeforeFirebase = localIDBeforeFirebase
    }
    
    /// Check if user is authenticated with Firebase
    var isFirebaseAuthenticated: Bool {
        firebaseUID != nil
    }
    
    func updateUserName(_ newName: String, isManual: Bool = true) {
        self.userName = newName
        self.lastUpdated = .now
        if isManual {
            self.isUsernameManuallyChanged = true
        }
    }
}

// Platform linking structure
struct LinkedPlatform: Codable {
    var platform: PlatformType
    var platformUserId: String
    var linkedAt: Date
    var email: String?
    var phoneNumber: String?
    var displayName: String?
    
    enum PlatformType: String, Codable, CaseIterable {
        case google = "Google"
        case apple = "Apple"
        case facebook = "Facebook"
        case twitter = "Twitter"
        case instagram = "Instagram"
        case yahoo = "Yahoo"
        case microsoft = "Microsoft"
        // Add more platforms as needed
    }
}


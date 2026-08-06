//
//  User.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//

import Foundation
import SwiftData

// Login location structure
struct LoginLocation: Codable {
    var latitude: Double
    var longitude: Double
    var timestamp: Date
    
    init(latitude: Double, longitude: Double, timestamp: Date = .now) {
        self.latitude = latitude
        self.longitude = longitude
        self.timestamp = timestamp
    }
}

@Model
final class AppUser {
    @Attribute(.unique) var id: String // Primary ID - Firebase UID if authenticated, local UUID if not
    var userName: String
    var firstName: String?
    var lastName: String?
    var email: String?
    var phoneNumber: String?
    var createdAt: Date
    var lastUpdated: Date
    
    // User image - Firebase Storage URL (nil means use default asset) //TODO: remove.
    var userImageURL: String?
    
    // Device identifier for default username generation
    var deviceIdentifier: String?
    
    // Track if username was manually changed by user
    var isUsernameManuallyChanged: Bool = false
    
    // Privacy settings for public profile
    var isEmailPublic: Bool = false
    var isPhonePublic: Bool = false
    
    // Avatar & Badge (MVP Identity)
    var avatarId: String? // Catalog avatar ID (source of truth for display)
    var equippedBadgeId: String? // MVP: one equipped badge slot
    var equippedLicenseCosmeticId: String? // Catalog Explorers license skin id (public profile)
    var wasEverInFamily: Bool = false // Keeps family unlocks after leaving
    
    // Friends & Family fields
    var isRetiredGeneral: Bool = false // Global constraint - can be in multiple families
    var activeFamilyId: String? // Only for non-retired users (0 or 1 active family)
    var friendCount: Int = 0 // Denormalized count for cap enforcement
    
    // Platform linking
    var linkedPlatforms: [LinkedPlatform]
    
    // Firebase sync tracking (offline-first)
    var firebaseUID: String? // Firebase Authentication UID (nil if local-only)
    var lastSyncedToFirebase: Date? // Last successful sync to Firestore
    var needsSync: Bool = false // Flag to sync when online
    var localIDBeforeFirebase: String? // Original local ID before Firebase migration
    
    // Login tracking
    var lastDateLoggedIn: Date?
    var lastLoginLocation: [LoginLocation] // Array of last 5 login locations
    
    init(
        id: String = UUID().uuidString,
        userName: String = "User",
        firstName: String? = nil,
        lastName: String? = nil,
        email: String? = nil,
        phoneNumber: String? = nil,
        createdAt: Date = .now,
        lastUpdated: Date = .now,
        userImageURL: String? = nil,
        deviceIdentifier: String? = nil,
        isUsernameManuallyChanged: Bool = false,
        isEmailPublic: Bool = false,
        isPhonePublic: Bool = false,
        avatarId: String? = nil,
        equippedBadgeId: String? = nil,
        equippedLicenseCosmeticId: String? = nil,
        wasEverInFamily: Bool = false,
        isRetiredGeneral: Bool = false,
        activeFamilyId: String? = nil,
        friendCount: Int = 0,
        linkedPlatforms: [LinkedPlatform] = [],
        firebaseUID: String? = nil,
        lastSyncedToFirebase: Date? = nil,
        needsSync: Bool = false,
        localIDBeforeFirebase: String? = nil,
        lastDateLoggedIn: Date? = nil,
        lastLoginLocation: [LoginLocation] = []
    ) {
        self.id = id
        self.userName = userName
        self.firstName = firstName
        self.lastName = lastName
        self.email = email
        self.phoneNumber = phoneNumber
        self.createdAt = createdAt
        self.lastUpdated = lastUpdated
        self.userImageURL = userImageURL
        self.deviceIdentifier = deviceIdentifier
        self.isUsernameManuallyChanged = isUsernameManuallyChanged
        self.isEmailPublic = isEmailPublic
        self.isPhonePublic = isPhonePublic
        self.avatarId = avatarId
        self.equippedBadgeId = equippedBadgeId
        self.equippedLicenseCosmeticId = equippedLicenseCosmeticId
        self.wasEverInFamily = wasEverInFamily
        self.isRetiredGeneral = isRetiredGeneral
        self.activeFamilyId = activeFamilyId
        self.friendCount = friendCount
        self.linkedPlatforms = linkedPlatforms
        self.firebaseUID = firebaseUID
        self.lastSyncedToFirebase = lastSyncedToFirebase
        self.needsSync = needsSync
        self.localIDBeforeFirebase = localIDBeforeFirebase
        self.lastDateLoggedIn = lastDateLoggedIn
        self.lastLoginLocation = lastLoginLocation
    }
    
    func updateUserName(_ newName: String, isManual: Bool = true) {
        self.userName = newName
        self.lastUpdated = .now
        if isManual {
            self.isUsernameManuallyChanged = true
        }
    }
    
    /// Get display name (firstName + lastName, or userName as fallback)
    var displayName: String {
        if let firstName = firstName, let lastName = lastName, !firstName.isEmpty, !lastName.isEmpty {
            return "\(firstName) \(lastName)"
        } else if let firstName = firstName, !firstName.isEmpty {
            return firstName
        } else if let lastName = lastName, !lastName.isEmpty {
            return lastName
        }
        return userName
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

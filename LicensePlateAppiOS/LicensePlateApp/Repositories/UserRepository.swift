//
//  UserRepository.swift
//  LicensePlateApp
//
//  Created for Friends & Family MVP
//

import Foundation
import SwiftData
import FirebaseFirestore
import Combine

@MainActor
class UserRepository: ObservableObject {
    private let db = Firestore.firestore()
    private var modelContext: ModelContext?
    
    @Published var searchResults: [AppUser] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    init(modelContext: ModelContext? = nil) {
        self.modelContext = modelContext
    }
    
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }
    
    // MARK: - User Search
    
    /// Search users by username (always searchable)
    func searchByUsername(_ username: String) async throws -> [AppUser] {
        isLoading = true
        defer { isLoading = false }
        
        // Search in usernames index collection (lowercase)
        let usernameLower = username.lowercased()
        let usernameDoc = try await db.collection("usernames").document(usernameLower).getDocument()
        
        guard usernameDoc.exists,
              let data = usernameDoc.data(),
              let uid = data["uid"] as? String else {
            return []
        }
        
        // Fetch user document
        let userDoc = try await db.collection("users").document(uid).getDocument()
        
        guard let userData = userDoc.data() else {
            return []
        }
        
        return [try await userFromFirestoreData(userData, id: uid)]
    }
    
    /// Search users by email (only if emailSearchable is true)
    func searchByEmail(_ email: String) async throws -> [AppUser] {
        isLoading = true
        defer { isLoading = false }
        
        // Query users where email matches and emailSearchable is true
        let query = db.collection("users")
            .whereField("email", isEqualTo: email.lowercased())
        
        let snapshot = try await query.getDocuments()
        var results: [AppUser] = []
        
        for document in snapshot.documents {
            let data = document.data()
            
            // Check privacy setting
            let privacy = data["privacy"] as? [String: Any] ?? [:]
            let emailSearchable = privacy["emailSearchable"] as? Bool ?? false
            
            if emailSearchable {
                results.append(try await userFromFirestoreData(data, id: document.documentID))
            }
        }
        
        return results
    }
    
    /// Search users by phone (only if phoneSearchable is true)
    func searchByPhone(_ phone: String) async throws -> [AppUser] {
        isLoading = true
        defer { isLoading = false }
        
        // Query users where phone matches and phoneSearchable is true
        let query = db.collection("users")
            .whereField("phone", isEqualTo: phone)
        
        let snapshot = try await query.getDocuments()
        var results: [AppUser] = []
        
        for document in snapshot.documents {
            let data = document.data()
            
            // Check privacy setting
            let privacy = data["privacy"] as? [String: Any] ?? [:]
            let phoneSearchable = privacy["phoneSearchable"] as? Bool ?? false
            
            if phoneSearchable {
                results.append(try await userFromFirestoreData(data, id: document.documentID))
            }
        }
        
        return results
    }
    
    /// Combined search: username (always), email/phone (if searchable)
    func searchUsers(query: String, searchType: SearchType) async throws -> [AppUser] {
        var results: [AppUser] = []
        
        switch searchType {
        case .username:
            results = try await searchByUsername(query)
        case .email:
            results = try await searchByEmail(query)
        case .phone:
            results = try await searchByPhone(query)
        case .all:
            // Try username first (always searchable)
            results = try await searchByUsername(query)
            
            // Try email if no results
            if results.isEmpty {
                results = try await searchByEmail(query)
            }
            
            // Try phone if still no results
            if results.isEmpty {
                results = try await searchByPhone(query)
            }
        }
        
        // Cache results in SwiftData
        cacheUsers(results)
        
        searchResults = results
        return results
    }
    
    enum SearchType {
        case username
        case email
        case phone
        case all
    }
    
    // MARK: - User Data Conversion
    
    private func userFromFirestoreData(_ data: [String: Any], id: String) async throws -> AppUser {
        guard let userName = data["username"] as? String else {
            throw NSError(domain: "UserRepository", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid user data"])
        }
        
        let privacy = data["privacy"] as? [String: Any] ?? [:]
        
        let user = AppUser(
            id: id,
            userName: userName,
            firstName: data["firstName"] as? String,
            lastName: data["lastName"] as? String,
            email: data["email"] as? String,
            phoneNumber: data["phone"] as? String,
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? .now,
            lastUpdated: (data["updatedAt"] as? Timestamp)?.dateValue() ?? .now,
            isEmailPublic: privacy["emailSearchable"] as? Bool ?? false,
            isPhonePublic: privacy["phoneSearchable"] as? Bool ?? false,
            isRetiredGeneral: data["isRetiredGeneral"] as? Bool ?? false,
            activeFamilyId: data["activeFamilyId"] as? String,
            friendCount: data["friendCount"] as? Int ?? 0,
            firebaseUID: id
        )
        
        // Set avatar if available
        if let avatarColorString = data["avatarColor"] as? String,
           let avatarColor = AvatarColor(rawValue: avatarColorString) {
            user.avatarColor = avatarColor
        }
        if let avatarTypeString = data["avatarType"] as? String,
           let avatarType = AvatarType(rawValue: avatarTypeString) {
            user.avatarType = avatarType
        }
        
        return user
    }
    
    /// Cache users in SwiftData for offline access
    private func cacheUsers(_ users: [AppUser]) {
        guard let modelContext = modelContext else { return }
        
        for user in users {
            let searchUserId = user.id
            let descriptor = FetchDescriptor<AppUser>(
                predicate: #Predicate<AppUser> { u in
                    u.id == searchUserId
                }
            )
            
            if let existing = try? modelContext.fetch(descriptor).first {
                // Update existing
                existing.userName = user.userName
                existing.firstName = user.firstName
                existing.lastName = user.lastName
                existing.email = user.email
                existing.phoneNumber = user.phoneNumber
                existing.isEmailPublic = user.isEmailPublic
                existing.isPhonePublic = user.isPhonePublic
                existing.isRetiredGeneral = user.isRetiredGeneral
                existing.activeFamilyId = user.activeFamilyId
                existing.friendCount = user.friendCount
                existing.avatarColor = user.avatarColor
                existing.avatarType = user.avatarType
            } else {
                // Insert new
                modelContext.insert(user)
            }
        }
        
        try? modelContext.save()
    }
    
    /// Get user by ID (from SwiftData cache or Firestore)
    func getUser(userId: String) async throws -> AppUser? {
        // First check SwiftData cache
        if let modelContext = modelContext {
            let searchUserId = userId
            let descriptor = FetchDescriptor<AppUser>(
                predicate: #Predicate<AppUser> { user in
                    user.id == searchUserId
                }
            )
            
            if let cached = try? modelContext.fetch(descriptor).first {
                return cached
            }
        }
        
        // Fetch from Firestore
        let userDoc = try await db.collection("users").document(userId).getDocument()
        
        guard let data = userDoc.data() else {
            return nil
        }
        
        let user = try await userFromFirestoreData(data, id: userId)
        cacheUsers([user])
        
        return user
    }
}


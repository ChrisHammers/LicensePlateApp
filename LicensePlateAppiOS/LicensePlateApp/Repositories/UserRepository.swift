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
    /// Supports exact match, prefix matching, and contains matching
    func searchByUsername(_ username: String) async throws -> [AppUser] {
        isLoading = true
        defer { isLoading = false }
        
        let usernameLower = username.lowercased()
        print("🔍 Searching for username: '\(usernameLower)'")
        
        var results: [AppUser] = []
        
        // First try exact match in users collection (case-insensitive)
        // Try both lowercase and original case
        let searchVariants = [usernameLower, username] // Try lowercase and original
        
        for searchTerm in searchVariants {
            do {
                print("🔍 Trying exact match search for: '\(searchTerm)'")
                let exactQuery = db.collection("users")
                    .whereField("userName", isEqualTo: searchTerm)
                    .limit(to: 1)
                
                let exactSnapshot = try await exactQuery.getDocuments()
                print("📊 Exact match found \(exactSnapshot.documents.count) documents")
                
                for document in exactSnapshot.documents {
                    let data = document.data()
                    if let foundUsername = data["userName"] as? String {
                        let user = try await userFromFirestoreData(data, id: document.documentID)
                        // Avoid duplicates
                        if !results.contains(where: { $0.id == user.id }) {
                            results.append(user)
                            print("✅ Added exact match user: \(user.userName)")
                        }
                    }
                }
            } catch {
                print("⚠️ Exact match search failed for '\(searchTerm)': \(error.localizedDescription)")
            }
        }
        
        // If we found exact matches, return them
        if !results.isEmpty {
            return results
        }
        
        // Try prefix search in users collection
        // Since usernames may be stored with mixed case, we need to search a broader range
        // We'll search from the lowercase query to cover both cases
        let queryStart = usernameLower
        let queryEnd = usernameLower + "\u{f8ff}" // Unicode character for range query
        
        // Also try uppercase variant for case-insensitive search
        let queryStartUpper = username.prefix(1).uppercased() + usernameLower.dropFirst()
        let queryEndUpper = queryStartUpper + "\u{f8ff}"
        
        let searchRanges = [(queryStart, queryEnd), (queryStartUpper, queryEndUpper)]
        
        for (start, end) in searchRanges {
            do {
                print("🔍 Trying prefix search: '\(start)' to '\(end)'")
                // Firestore field is "userName" (camelCase)
                let query = db.collection("users")
                    .whereField("userName", isGreaterThanOrEqualTo: start)
                    .whereField("userName", isLessThan: end)
                    .limit(to: 50) // Get more results for contains filtering
                
                let snapshot = try await query.getDocuments()
                print("📊 Found \(snapshot.documents.count) documents in prefix range")
                
                for document in snapshot.documents {
                    let data = document.data()
                    // Firestore field is "userName" (camelCase)
                    if let foundUsername = data["userName"] as? String {
                        let foundUsernameLower = foundUsername.lowercased()
                        print("  - Checking username: '\(foundUsername)' (lowercase: '\(foundUsernameLower)') contains '\(usernameLower)'? \(foundUsernameLower.contains(usernameLower))")
                        // Check if username contains the search query (case-insensitive)
                        if foundUsernameLower.contains(usernameLower) {
                            let user = try await userFromFirestoreData(data, id: document.documentID)
                            // Avoid duplicates
                            if !results.contains(where: { $0.id == user.id }) {
                                results.append(user)
                                print("  ✅ Added user: \(user.userName)")
                            }
                        }
                    } else {
                        print("  ⚠️ Document \(document.documentID) has no userName field. Available fields: \(data.keys.joined(separator: ", "))")
                    }
                }
                
                print("📊 Total results after filtering: \(results.count)")
                // If we found results, return them (limit to 10)
                if results.count >= 10 {
                    return Array(results.prefix(10))
                }
            } catch {
                // If index doesn't exist, log the error
                print("❌ Username prefix search failed for range '\(start)'-'\(end)': \(error.localizedDescription)")
                if let nsError = error as NSError? {
                    print("   Domain: \(nsError.domain), Code: \(nsError.code)")
                }
            }
        }
        
        // If prefix search didn't work (possibly due to case sensitivity),
        // try a fallback: fetch a limited set and filter client-side
        // This is less efficient but works when usernames have mixed case
        if results.isEmpty && usernameLower.count >= 3 {
            do {
                print("🔍 Fallback: Fetching users for client-side filtering")
                // Fetch a reasonable number of users (limit to avoid performance issues)
                // Note: This is a workaround for case-sensitivity issues
                let fallbackQuery = db.collection("users")
                    .limit(to: 100) // Limit to 100 for performance
                
                let fallbackSnapshot = try await fallbackQuery.getDocuments()
                print("📊 Fetched \(fallbackSnapshot.documents.count) users for filtering")
                
                for document in fallbackSnapshot.documents {
                    let data = document.data()
                    if let foundUsername = data["userName"] as? String {
                        let foundUsernameLower = foundUsername.lowercased()
                        // Case-insensitive contains check
                        if foundUsernameLower.contains(usernameLower) {
                            let user = try await userFromFirestoreData(data, id: document.documentID)
                            results.append(user)
                            print("  ✅ Added user via fallback: \(user.userName)")
                            
                            // Limit to 10 results
                            if results.count >= 10 {
                                break
                            }
                        }
                    }
                }
                
                print("📊 Fallback search found \(results.count) results")
            } catch {
                print("❌ Fallback search failed: \(error.localizedDescription)")
            }
        }
        
        print("⚠️ Final result count: \(results.count) for username: '\(usernameLower)'")
        return results
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
        // Firestore field is "userName" (camelCase), not "username"
        guard let userName = data["userName"] as? String else {
            print("⚠️ User document \(id) missing userName field. Available fields: \(data.keys.joined(separator: ", "))")
            throw NSError(domain: "UserRepository", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid user data: missing userName"])
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


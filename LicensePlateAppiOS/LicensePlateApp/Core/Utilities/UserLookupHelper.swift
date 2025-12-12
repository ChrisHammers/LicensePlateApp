//
//  UserLookupHelper.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//

import Foundation
import SwiftData
import FirebaseFirestore

/// Helper functions for looking up user information from SwiftData and Firestore
enum UserLookupHelper {
    private static let db = Firestore.firestore()
    
    // MARK: - Async Methods (Online-First)
    
    /// Get userName for a given userID, checking Firestore first (if online), then local cache
    /// Returns nil if user not found anywhere
    static func getUserName(for userID: String, in modelContext: ModelContext) async -> String? {
        // Check if online
        if FirebaseFamilySyncService.shared.isOnline {
            // Try Firestore first
            if let userName = await fetchUserNameFromFirestore(userID: userID, modelContext: modelContext) {
                return userName
            }
        }
        
        // Fall back to local SwiftData
        return getUserNameSync(for: userID, in: modelContext)
    }
    
    /// Batch lookup userNames for multiple userIDs
    /// Returns dictionary mapping userID -> userName
    static func getUserNames(for userIDs: [String], in modelContext: ModelContext) async -> [String: String] {
        var result: [String: String] = [:]
        
        // Check if online
        if FirebaseFamilySyncService.shared.isOnline {
            // Batch fetch from Firestore
            let firestoreResults = await batchFetchUserNamesFromFirestore(userIDs: userIDs, modelContext: modelContext)
            result.merge(firestoreResults) { (_, new) in new } // Prefer Firestore results
        }
        
        // Fill in any missing from local cache
        for userID in userIDs {
            if result[userID] == nil {
                if let userName = getUserNameSync(for: userID, in: modelContext) {
                    result[userID] = userName
                }
            }
        }
        
        return result
    }
    
    // MARK: - Sync Methods (Local Only - Backward Compatibility)
    
    /// Get userName for a given userID from SwiftData (local only)
    /// Returns nil if user not found (works offline with local data)
    static func getUserNameSync(for userID: String, in modelContext: ModelContext) -> String? {
        let descriptor = FetchDescriptor<AppUser>(predicate: #Predicate<AppUser> {
            $0.id == userID
        })
        return try? modelContext.fetch(descriptor).first?.userName
    }
    
    /// Get AppUser for a given userID from SwiftData (local only)
    /// Returns nil if user not found (works offline with local data)
    static func getUser(for userID: String, in modelContext: ModelContext) -> AppUser? {
        let descriptor = FetchDescriptor<AppUser>(predicate: #Predicate<AppUser> {
            $0.id == userID
        })
        return try? modelContext.fetch(descriptor).first
    }
    
    // MARK: - Private Firestore Methods
    
    /// Fetch userName from Firestore and cache it in SwiftData
    private static func fetchUserNameFromFirestore(userID: String, modelContext: ModelContext) async -> String? {
        do {
            let docRef = db.collection("users").document(userID)
            let document = try await docRef.getDocument()
            
            guard document.exists, let data = document.data(),
                  let userName = data["userName"] as? String else {
                return nil
            }
            
            // Cache in SwiftData (minimal record)
            cacheUserInSwiftData(userID: userID, userName: userName, modelContext: modelContext)
            
            return userName
        } catch {
            print("⚠️ Error fetching user from Firestore: \(error)")
            return nil
        }
    }
    
    /// Batch fetch userNames from Firestore and cache them in SwiftData
    private static func batchFetchUserNamesFromFirestore(userIDs: [String], modelContext: ModelContext) async -> [String: String] {
        guard !userIDs.isEmpty else { return [:] }
        
        var result: [String: String] = [:]
        
        // Fetch all documents in parallel using TaskGroup
        await withTaskGroup(of: (String, String?).self) { group in
            for userID in userIDs {
                group.addTask {
                    do {
                        let docRef = db.collection("users").document(userID)
                        let document = try await docRef.getDocument()
                        
                        guard document.exists, let data = document.data(),
                              let userName = data["userName"] as? String else {
                            return (userID, nil)
                        }
                        
                        // Cache in SwiftData (minimal record)
                        cacheUserInSwiftData(userID: userID, userName: userName, modelContext: modelContext)
                        
                        return (userID, userName)
                    } catch {
                        print("⚠️ Error fetching user \(userID) from Firestore: \(error)")
                        return (userID, nil)
                    }
                }
            }
            
            // Collect results
            for await (userID, userName) in group {
                if let userName = userName {
                    result[userID] = userName
                }
            }
        }
        
        return result
    }
    
    /// Create or update minimal AppUser record in SwiftData
    /// Public method to allow caching users from search results
    static func cacheUserInSwiftData(userID: String, userName: String, modelContext: ModelContext) {
        // Check if user already exists
        let descriptor = FetchDescriptor<AppUser>(predicate: #Predicate<AppUser> {
            $0.id == userID
        })
        
        if let existingUser = try? modelContext.fetch(descriptor).first {
            // Update existing user's userName
            existingUser.userName = userName
            existingUser.lastUpdated = .now
        } else {
            // Create minimal AppUser record
            let cachedUser = AppUser(
                id: userID,
                userName: userName,
                createdAt: .now,
                lastUpdated: .now
            )
            modelContext.insert(cachedUser)
        }
        
        // Save context (non-blocking, errors are ignored)
        try? modelContext.save()
    }
}


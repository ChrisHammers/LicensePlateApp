//
//  UserLookupHelper.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//

import Foundation
import SwiftData

/// Helper functions for looking up user information from SwiftData
enum UserLookupHelper {
    /// Get userName for a given userID from SwiftData
    /// Returns nil if user not found (works offline with local data)
    static func getUserName(for userID: String, in modelContext: ModelContext) -> String? {
        let descriptor = FetchDescriptor<AppUser>(predicate: #Predicate<AppUser> {
            $0.id == userID
        })
        return try? modelContext.fetch(descriptor).first?.userName
    }
    
    /// Get AppUser for a given userID from SwiftData
    /// Returns nil if user not found (works offline with local data)
    static func getUser(for userID: String, in modelContext: ModelContext) -> AppUser? {
        let descriptor = FetchDescriptor<AppUser>(predicate: #Predicate<AppUser> {
            $0.id == userID
        })
        return try? modelContext.fetch(descriptor).first
    }
}


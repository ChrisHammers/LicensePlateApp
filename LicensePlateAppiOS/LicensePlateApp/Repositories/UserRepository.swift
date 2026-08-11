//
//  UserRepository.swift
//  LicensePlateApp
//
//  Created for Friends & Family MVP
//

import Foundation
import SwiftData
import FirebaseFirestore
import FirebaseFunctions
import FirebaseAuth
import Combine

extension Notification.Name {
    /// Posted after `UserRepository` merges one or more remote `users/{id}` payloads into SwiftData (`userIds` array in `userInfo`).
    static let userProfilesMerged = Notification.Name("UserRepository.userProfilesMerged")
}

@MainActor
class UserRepository: ObservableObject {
    static let shared = UserRepository()
    
    private let db = Firestore.firestore()
    private var modelContext: ModelContext?
    private var entitlementTagsByUserId: [String: Set<String>] = [:]
    private let friendsFamilyAccessPolicy: FriendsFamilyAccessPolicy
    
    @Published var searchResults: [AppUser] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    /// Missing `isRegistered` is treated as registered (legacy users).
    static func isRegisteredForSearch(_ data: [String: Any]) -> Bool {
        (data["isRegistered"] as? Bool) ?? true
    }
    
    init(friendsFamilyAccessPolicy: FriendsFamilyAccessPolicy = .shared) {
        self.friendsFamilyAccessPolicy = friendsFamilyAccessPolicy
    }

    struct UserIdentitySnapshot: Sendable {
        var userId: String
        var displayName: String
        var avatarId: String?
        var legacyFallbackImageName: String?
    }
    
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    func entitlementTags(for userId: String) -> Set<String> {
        entitlementTagsByUserId[userId] ?? []
    }

    func ingestEntitlementTags(userId: String, tags: Set<String>) {
        entitlementTagsByUserId[userId] = tags
    }

    func clearEntitlementTags(for userId: String? = nil) {
        if let userId, !userId.isEmpty {
            entitlementTagsByUserId.removeValue(forKey: userId)
        } else {
            entitlementTagsByUserId.removeAll()
        }
    }

    /// Hard sign-out: delete all local AppUser rows (self + peer cache).
    func deleteAllLocalUsers() throws {
        guard let modelContext else { return }
        try modelContext.delete(model: AppUser.self)
        try modelContext.save()
        clearInMemoryState()
    }

    func clearInMemoryState() {
        entitlementTagsByUserId.removeAll()
        searchResults = []
        errorMessage = nil
        isLoading = false
    }

    static func parseEntitlementTags(from data: [String: Any]) -> Set<String> {
        guard let raw = data["entitlementTags"] as? [Any] else { return [] }
        return Set(raw.compactMap { value in
            guard let tag = value as? String, !tag.isEmpty else { return nil }
            return tag
        })
    }

    /// Returns a dictionary of userId -> userName for the given IDs. Missing or failed lookups fall back to the id as the value.
    func displayNames(forUserIds ids: Set<String>) async -> [String: String] {
        var result: [String: String] = [:]
        for id in ids {
            if let user = try? await getUser(userId: id) {
                result[id] = user.userName
            } else {
                result[id] = id
            }
        }
        return result
    }

    /// SwiftData-only lookup used for fast UI hydration. Missing users are omitted.
    func cachedIdentityMap(forUserIds ids: Set<String>) -> [String: UserIdentitySnapshot] {
        guard let modelContext, !ids.isEmpty else { return [:] }
        var result: [String: UserIdentitySnapshot] = [:]
        for id in ids {
            let searchUserId = id
            let descriptor = FetchDescriptor<AppUser>(
                predicate: #Predicate<AppUser> { user in
                    user.id == searchUserId || user.firebaseUID == searchUserId
                }
            )
            if let user = try? modelContext.fetch(descriptor).first {
                result[id] = UserIdentitySnapshot(
                    userId: id,
                    displayName: user.displayName,
                    avatarId: user.avatarId,
                    legacyFallbackImageName: nil
                )
            }
        }
        return result
    }

    /// Cache-aware identity map with Firestore fallback for richer avatar/name rows.
    func identityMap(forUserIds ids: Set<String>) async -> [String: UserIdentitySnapshot] {
        var result = cachedIdentityMap(forUserIds: ids)
        let missing = ids.subtracting(Set(result.keys))
        guard !missing.isEmpty else { return result }

        for id in missing {
            if let user = try? await getUser(userId: id) {
                result[id] = UserIdentitySnapshot(
                    userId: id,
                    displayName: user.displayName,
                    avatarId: user.avatarId,
                    legacyFallbackImageName: nil
                )
            } else {
                result[id] = UserIdentitySnapshot(
                    userId: id,
                    displayName: id,
                    avatarId: nil,
                    legacyFallbackImageName: nil
                )
            }
        }
        return result
    }

    /// Merges latest `users/{userId}` documents into SwiftData so finder UI can escape stale local cache.
    /// - Note: Does not delete local rows when remote doc is missing (offline / permissions).
    /// Posts a single `Notification.Name.userProfilesMerged` with all successfully merged ids.
    func refreshUsersFromFirestoreIfPresent(userIds: Set<String>) async {
        guard !userIds.isEmpty else { return }
        var mergedIds: [String] = []
        for userId in userIds {
            do {
                let userDoc = try await db.collection("users").document(userId).getDocument()
                guard userDoc.exists, let data = userDoc.data() else { continue }
                try await mergeRemoteProfileIntoCache(userId: userId, data: data)
                mergedIds.append(userId)
            } catch {
                #if DEBUG
                print("UserRepository.refreshUsersFromFirestoreIfPresent failed for \(userId): \(error)")
                #endif
            }
        }
        postUserProfilesMergedIfNeeded(mergedIds)
    }

    /// Merges a Firestore `users/{userId}` snapshot into SwiftData (shared path for explicit fetch + pinned listeners).
    func mergeRemoteUserDocument(userId: String, data: [String: Any]) async throws {
        try await mergeRemoteProfileIntoCache(userId: userId, data: data)
        postUserProfilesMergedIfNeeded([userId])
    }

    private func mergeRemoteProfileIntoCache(userId: String, data: [String: Any]) async throws {
        ingestEntitlementTags(userId: userId, tags: Self.parseEntitlementTags(from: data))
        let user = try await userFromFirestoreData(data, id: userId)
        cacheUsers([user])
    }

    private func postUserProfilesMergedIfNeeded(_ userIds: [String]) {
        guard !userIds.isEmpty else { return }
        NotificationCenter.default.post(
            name: .userProfilesMerged,
            object: nil,
            userInfo: ["userIds": userIds]
        )
    }

    // MARK: - Child registration declaration (COPPA F-6, FR-27)

    /// Declares the current auth account as an under-13 registration BEFORE its first
    /// `users/{uid}` profile write. The server sets `isChildAccount = true` (never
    /// false) and records the uid-only DECLARED lifecycle row. Callable from an
    /// anonymous uid; idempotent, protective direction only.
    func declareChildRegistration() async throws {
        try await AppCheckReadiness.ensureCallablePrerequisites()
        let fn = Functions.functions().httpsCallable("declareChildRegistration")
        _ = try await fn.call(([:] as [String: Any]).addingClientMetadata())
    }

    // MARK: - User Search

    /// Search users by username (always searchable)
    /// Supports exact match, prefix matching, and contains matching
    /// - Note: Unused by live `searchUsers` (Cloud Function). Kept for emergency rollback only.
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
                    guard Self.isRegisteredForSearch(data) else { continue }
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
                    guard Self.isRegisteredForSearch(data) else { continue }
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
                    guard Self.isRegisteredForSearch(data) else { continue }
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
    /// - Note: Unused by live `searchUsers` (Cloud Function). Kept for emergency rollback only.
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
            guard Self.isRegisteredForSearch(data) else { continue }
            
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
    /// - Note: Unused by live `searchUsers` (Cloud Function). Kept for emergency rollback only.
    func searchByPhone(_ phone: String) async throws -> [AppUser] {
        isLoading = true
        defer { isLoading = false }
        
        // Query users where phone matches and phoneSearchable is true
        let query = db.collection("users")
            .whereField("phoneNumber", isEqualTo: phone)
        
        let snapshot = try await query.getDocuments()
        var results: [AppUser] = []
        
        for document in snapshot.documents {
            let data = document.data()
            guard Self.isRegisteredForSearch(data) else { continue }
            
            // Check privacy setting
            let privacy = data["privacy"] as? [String: Any] ?? [:]
            let phoneSearchable = privacy["phoneSearchable"] as? Bool ?? false
            
            if phoneSearchable {
                results.append(try await userFromFirestoreData(data, id: document.documentID))
            }
        }
        
        return results
    }
    
    // MARK: - Contains Search Methods
    
    /// Search users by username with contains matching (case-insensitive)
    func searchByUsernameContains(_ query: String) async throws -> [AppUser] {
        isLoading = true
        defer { isLoading = false }
        
        let queryLower = query.lowercased()
        var results: [AppUser] = []
        
        // Fetch a reasonable number of users and filter client-side
        // This is necessary for true "contains" matching
        do {
            let snapshot = try await db.collection("users")
                .limit(to: 100)
                .getDocuments()
            
            for document in snapshot.documents {
                let data = document.data()
                guard Self.isRegisteredForSearch(data) else { continue }
                if let userName = data["userName"] as? String {
                    let userNameLower = userName.lowercased()
                    // Case-insensitive contains check
                    if userNameLower.contains(queryLower) {
                        let user = try await userFromFirestoreData(data, id: document.documentID)
                        if !results.contains(where: { $0.id == user.id }) {
                            results.append(user)
                        }
                        
                        // Limit to 20 results for performance
                        if results.count >= 20 {
                            break
                        }
                    }
                }
            }
        } catch {
            print("❌ Username contains search failed: \(error.localizedDescription)")
            throw error
        }
        
        return results
    }
    
    /// Search users by email with contains matching (only if emailSearchable is true)
    func searchByEmailContains(_ query: String) async throws -> [AppUser] {
        isLoading = true
        defer { isLoading = false }
        
        let queryLower = query.lowercased()
        var results: [AppUser] = []
        
        // Fetch users and filter for public email and contains match
        do {
            let snapshot = try await db.collection("users")
                .limit(to: 100)
                .getDocuments()
            
            for document in snapshot.documents {
                let data = document.data()
                guard Self.isRegisteredForSearch(data) else { continue }
                
                // Check privacy setting
                let privacy = data["privacy"] as? [String: Any] ?? [:]
                let emailSearchable = privacy["emailSearchable"] as? Bool ?? false
                
                if emailSearchable, let email = data["email"] as? String {
                    let emailLower = email.lowercased()
                    // Case-insensitive contains check
                    if emailLower.contains(queryLower) {
                        let user = try await userFromFirestoreData(data, id: document.documentID)
                        if !results.contains(where: { $0.id == user.id }) {
                            results.append(user)
                        }
                        
                        // Limit to 20 results for performance
                        if results.count >= 20 {
                            break
                        }
                    }
                }
            }
        } catch {
            print("❌ Email contains search failed: \(error.localizedDescription)")
            throw error
        }
        
        return results
    }
    
    /// Search users by phone with contains matching (only if phoneSearchable is true)
    func searchByPhoneContains(_ query: String) async throws -> [AppUser] {
        isLoading = true
        defer { isLoading = false }
        
        // Remove non-numeric characters for phone search
        let phoneQuery = query.filter { $0.isNumber }
        var results: [AppUser] = []
        
        if phoneQuery.isEmpty {
            return results
        }
        
        // Fetch users and filter for public phone and contains match
        do {
            let snapshot = try await db.collection("users")
                .limit(to: 100)
                .getDocuments()
            
            for document in snapshot.documents {
                let data = document.data()
                guard Self.isRegisteredForSearch(data) else { continue }
                
                // Check privacy setting
                let privacy = data["privacy"] as? [String: Any] ?? [:]
                let phoneSearchable = privacy["phoneSearchable"] as? Bool ?? false
                
                if phoneSearchable, let phone = data["phoneNumber"] as? String {
                    let phoneNumbers = phone.filter { $0.isNumber }
                    // Contains check on numeric characters only
                    if phoneNumbers.contains(phoneQuery) {
                        let user = try await userFromFirestoreData(data, id: document.documentID)
                        if !results.contains(where: { $0.id == user.id }) {
                            results.append(user)
                        }
                        
                        // Limit to 20 results for performance
                        if results.count >= 20 {
                            break
                        }
                    }
                }
            }
        } catch {
            print("❌ Phone contains search failed: \(error.localizedDescription)")
            throw error
        }
        
        return results
    }
    
    /// Combined search via `searchUsers` Cloud Function (public DTO only).
    /// - Parameters:
    ///   - query: Search query string
    ///   - searchType: Retained for analytics; server classifies email/phone/username from the query
    ///   - excludeUserId: Optional user ID to exclude from results (typically current user)
    func searchUsers(query: String, searchType: SearchType, excludeUserId: String? = nil, searchingUser: AppUser? = nil) async throws -> [UserSearchResult] {
        guard friendsFamilyAccessPolicy.canUseFriendsAndFamily(for: searchingUser) else {
            return []
        }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else {
            return []
        }

        try FriendsFamilyAccessPolicy.shared.validateFriendsFamilyCallableAccess(for: searchingUser)
        try await AppCheckReadiness.ensureCallablePrerequisites()

        let fn = Functions.functions().httpsCallable("searchUsers")
        let result: HTTPSCallableResult
        do {
            result = try await fn.call(([
                "query": trimmed,
            ] as [String: Any]).addingClientMetadata())
        } catch {
            throw Self.userFacingSearchCallableError(error)
        }

        guard let response = result.data as? [String: Any],
              let rawResults = response["results"] as? [[String: Any]] else {
            throw NSError(
                domain: "UserRepository",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid response from searchUsers".localized]
            )
        }

        var results: [UserSearchResult] = []
        var seen = Set<String>()

        for item in rawResults {
            guard let hit = PublicUserSearchHit(firestoreValue: item) else { continue }
            if let excludeUserId, hit.userId == excludeUserId { continue }
            if seen.contains(hit.userId) { continue }
            seen.insert(hit.userId)

            let user = AppUser(
                id: hit.userId,
                userName: hit.userName,
                avatarId: hit.avatarId,
                firebaseUID: hit.userId
            )
            results.append(UserSearchResult(user: user, matchedField: hit.matchedField))
        }

        // Cache public identity only (no email/phone on search hits)
        cacheUsers(results.map(\.user))
        searchResults = results.map(\.user)

        // searchType retained for callers/analytics; classification is server-side
        _ = searchType

        return results
    }

    private static func userFacingSearchCallableError(_ error: Error) -> Error {
        let nsError = error as NSError
        guard nsError.domain == FunctionsErrorDomain,
              let code = FunctionsErrorCode(rawValue: nsError.code) else {
            return error
        }
        let message: String
        switch code {
        case .unauthenticated:
            message = Auth.auth().currentUser?.isAnonymous == true
                ? FriendsFamilyCallableErrors.guestBlockedMessage
                : "You are not signed in. Sign in and try again.".localized
        case .failedPrecondition:
            message = FriendsFamilyCallableErrors.guestBlockedMessage
        case .unavailable:
            message = "Requires network connection".localized
        default:
            message = (nsError.userInfo[NSLocalizedDescriptionKey] as? String)
                ?? error.localizedDescription
        }
        return NSError(
            domain: "UserRepository",
            code: nsError.code,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
    
    /// Legacy method for backward compatibility - returns just users
    func searchUsersLegacy(query: String, searchType: SearchType) async throws -> [AppUser] {
        let results = try await searchUsers(query: query, searchType: searchType)
        return results.map { $0.user }
    }
    
    enum SearchType {
        case username
        case email
        case phone
        case all
    }
    
    // MARK: - Search Result Model
    
    struct UserSearchResult {
        let user: AppUser
        let matchedField: MatchField
        
        enum MatchField {
            case username
            case email
            case phone
            
            var displayName: String {
                switch self {
                case .username: return "Username".localized
                case .email: return "Email".localized
                case .phone: return "Phone".localized
                }
            }

            /// Invite method for Cloud Functions. Always `"search"` so email/phone
            /// discovery does not re-trigger opt-in privacy gates or break InviteMethod parsing.
            var inviteMethod: String { "search" }
        }
    }

    /// Public-only hit from `searchUsers` callable (never includes email/phone).
    struct PublicUserSearchHit {
        let userId: String
        let userName: String
        let displayName: String
        let avatarId: String?
        let matchedField: UserSearchResult.MatchField

        init?(firestoreValue data: [String: Any]) {
            guard let userId = data["userId"] as? String, !userId.isEmpty,
                  let userName = data["userName"] as? String, !userName.isEmpty else {
                return nil
            }
            self.userId = userId
            self.userName = userName
            self.displayName = (data["displayName"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? userName
            self.avatarId = data["avatarId"] as? String
            let raw = data["matchedField"] as? String ?? "username"
            switch raw {
            case "email": self.matchedField = .email
            case "phone": self.matchedField = .phone
            default: self.matchedField = .username
            }
        }

    }
    
    // MARK: - User Data Conversion
    
    private func userFromFirestoreData(_ data: [String: Any], id: String) async throws -> AppUser {
        // Canonical field is `userName`; some paths historically wrote `username`.
        guard let userName = (data["userName"] as? String) ?? (data["username"] as? String), !userName.isEmpty else {
            print("⚠️ User document \(id) missing userName field. Available fields: \(data.keys.joined(separator: ", "))")
            throw NSError(domain: "UserRepository", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid user data: missing userName"])
        }
        
        let privacyFlags = UserPrivacyFirestore.decode(from: data)

        // Peer-readable docs no longer carry contact identifiers (FR-43); these stay only to
        // read legacy docs that have not been migrated by a profile sync yet. `cacheUsers`
        // therefore never clears a locally known email/phone from a nil remote value.
        let user = AppUser(
            id: id,
            userName: userName,
            email: data["email"] as? String,
            phoneNumber: data["phoneNumber"] as? String,
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? .now,
            lastUpdated: (data["updatedAt"] as? Timestamp)?.dateValue() ?? .now,
            isEmailPublic: privacyFlags.isEmailPublic,
            isPhonePublic: privacyFlags.isPhonePublic,
            isRetiredGeneral: data["isRetiredGeneral"] as? Bool ?? false,
            activeFamilyId: data["activeFamilyId"] as? String,
            friendCount: data["friendCount"] as? Int ?? 0,
            firebaseUID: id
        )
        
        user.avatarId = data["avatarId"] as? String
        user.equippedBadgeId = data["equippedBadgeId"] as? String
        user.equippedLicenseCosmeticId = data["equippedLicenseCosmeticId"] as? String
        user.wasEverInFamily = data["wasEverInFamily"] as? Bool ?? false
        
        return user
    }
    
    /// Cache users in SwiftData for offline access
    private func cacheUsers(_ users: [AppUser]) {
        guard let modelContext = modelContext else { return }
        
        for user in users {
            let searchId = user.id
            let searchFirebase = user.firebaseUID ?? ""
            let idDescriptor = FetchDescriptor<AppUser>(
                predicate: #Predicate<AppUser> { u in
                    u.id == searchId
                }
            )
            let firebaseDescriptor = FetchDescriptor<AppUser>(
                predicate: #Predicate<AppUser> { u in
                    u.firebaseUID == searchFirebase
                }
            )

            let existingById = try? modelContext.fetch(idDescriptor).first
            let existingByFirebase: AppUser? = {
                guard !searchFirebase.isEmpty else { return nil }
                return try? modelContext.fetch(firebaseDescriptor).first
            }()

            if let existing = existingById ?? existingByFirebase {
                // Update existing (names are never stored — F-6 rework)
                existing.userName = user.userName
                // Contact is owner-only (private/contact); a peer doc never supplies it, so
                // only overwrite when the remote actually carried a value (FR-43).
                if let email = user.email, !email.isEmpty {
                    existing.email = email
                }
                if let phoneNumber = user.phoneNumber, !phoneNumber.isEmpty {
                    existing.phoneNumber = phoneNumber
                }
                existing.isEmailPublic = user.isEmailPublic
                existing.isPhonePublic = user.isPhonePublic
                existing.isRetiredGeneral = user.isRetiredGeneral
                existing.activeFamilyId = user.activeFamilyId
                existing.friendCount = user.friendCount
                existing.avatarId = user.avatarId
                existing.equippedBadgeId = user.equippedBadgeId
                existing.equippedLicenseCosmeticId = user.equippedLicenseCosmeticId
                existing.wasEverInFamily = user.wasEverInFamily
                if existing.firebaseUID == nil, let f = user.firebaseUID {
                    existing.firebaseUID = f
                }
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

    func clearActiveFamilyIdFromServer(firebaseUID: String) async throws {
        try await db.collection("users").document(firebaseUID).updateData([
            "activeFamilyId": FieldValue.delete()
        ])
    }

    // MARK: - Push routing token (owner-only)

    /// Push token doc. `users/{uid}` is peer-readable and Firestore reads are document-level,
    /// so the token must live off it entirely (FR-43 / audit E1). Cloud Functions read it
    /// with the Admin SDK; the account-deletion sweep of `users/{uid}/private/*` covers it.
    private func privateFCMTokenRef(userId: String) -> DocumentReference {
        db.collection("users").document(userId).collection("private").document("fcm")
    }

    func updateFCMToken(userId: String, token: String) async throws {
        try await privateFCMTokenRef(userId: userId).setData([
            "token": token,
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
        await purgeLegacyPublicFCMToken(userId: userId)
    }

    /// Removes push routing for this user (hard sign-out). Call while Auth still matches `userId`.
    func clearFCMToken(userId: String) async throws {
        try await privateFCMTokenRef(userId: userId).delete()
        await purgeLegacyPublicFCMToken(userId: userId)
    }

    /// Migration: drops the pre-FR-43 top-level `fcmToken` from the peer-readable profile doc.
    /// Best effort — a missing doc or a rules rejection must not fail token registration/sign-out.
    private func purgeLegacyPublicFCMToken(userId: String) async {
        try? await db.collection("users").document(userId).updateData([
            "fcmToken": FieldValue.delete(),
            "fcmTokenUpdatedAt": FieldValue.delete()
        ])
    }

    // MARK: - Notification preferences (Firestore-only; server gates FCM)

    /// Account-level push prefs. Missing fields default to enabled on the server (promotions default off).
    struct NotificationPrefs: Equatable, Sendable {
        var friend: Bool
        var family: Bool
        var tripInvite: Bool
        var tripEnded: Bool
        var plateFoundByOpponent: Bool
        var plateFoundByCoPilots: Bool
        var inactiveTripReminder: Bool
        var returnStreakReminder: Bool
        var promotionsAndNews: Bool

        static let `default` = NotificationPrefs(
            friend: true,
            family: true,
            tripInvite: true,
            tripEnded: true,
            plateFoundByOpponent: true,
            plateFoundByCoPilots: true,
            inactiveTripReminder: true,
            returnStreakReminder: true,
            promotionsAndNews: false
        )

        /// Parse Firestore map; missing keys use `default` semantics.
        static func fromFirestoreMap(_ raw: [String: Any]?) -> NotificationPrefs {
            let d = NotificationPrefs.default
            guard let raw else { return d }
            return NotificationPrefs(
                friend: (raw["friend"] as? Bool) ?? d.friend,
                family: (raw["family"] as? Bool) ?? d.family,
                tripInvite: (raw["tripInvite"] as? Bool) ?? d.tripInvite,
                tripEnded: (raw["tripEnded"] as? Bool) ?? d.tripEnded,
                plateFoundByOpponent: (raw["plateFoundByOpponent"] as? Bool) ?? d.plateFoundByOpponent,
                plateFoundByCoPilots: (raw["plateFoundByCoPilots"] as? Bool) ?? d.plateFoundByCoPilots,
                inactiveTripReminder: (raw["inactiveTripReminder"] as? Bool) ?? d.inactiveTripReminder,
                returnStreakReminder: (raw["returnStreakReminder"] as? Bool) ?? d.returnStreakReminder,
                promotionsAndNews: (raw["promotionsAndNews"] as? Bool) ?? d.promotionsAndNews
            )
        }

        /// Full map so merge does not wipe sibling preferences.
        var firestoreMap: [String: Bool] {
            [
                "friend": friend,
                "family": family,
                "tripInvite": tripInvite,
                "tripEnded": tripEnded,
                "plateFoundByOpponent": plateFoundByOpponent,
                "plateFoundByCoPilots": plateFoundByCoPilots,
                "inactiveTripReminder": inactiveTripReminder,
                "returnStreakReminder": returnStreakReminder,
                "promotionsAndNews": promotionsAndNews
            ]
        }

        func isEnabled(for kind: NotificationEligibilityKind) -> Bool {
            switch kind {
            case .tripInvite: return tripInvite
            case .friendInvite: return friend
            case .familyInvite: return family
            case .inactiveActiveTripReminder: return inactiveTripReminder
            case .returnStreakReminder: return returnStreakReminder
            case .milestone: return true
            }
        }
    }

    func fetchNotificationPrefs(userId: String) async throws -> NotificationPrefs {
        let snapshot = try await db.collection("users").document(userId).getDocument()
        let raw = snapshot.data()?["notificationPrefs"] as? [String: Any]
        return NotificationPrefs.fromFirestoreMap(raw)
    }

    /// Writes all keys together so merge does not wipe sibling preferences.
    func updateNotificationPrefs(userId: String, prefs: NotificationPrefs) async throws {
        try await db.collection("users").document(userId).setData([
            "notificationPrefs": prefs.firestoreMap
        ], merge: true)
    }

    // MARK: - Game defaults (Firestore account prefs; UserDefaults is local cache)

    /// Account-level new-trip / game defaults that sync across devices.
    /// Missing fields default to enabled (`true`), matching factory New Trip Defaults.
    struct GameDefaults: Equatable, Sendable {
        var includeUS: Bool
        var includeCanada: Bool
        var includeMexico: Bool
        var startTripRightAway: Bool

        static let `default` = GameDefaults(
            includeUS: true,
            includeCanada: true,
            includeMexico: true,
            startTripRightAway: true
        )

        /// Parse Firestore map; missing keys use `default` semantics.
        static func fromFirestoreMap(_ raw: [String: Any]?) -> GameDefaults {
            let d = GameDefaults.default
            guard let raw else { return d }
            return GameDefaults(
                includeUS: (raw["includeUS"] as? Bool) ?? d.includeUS,
                includeCanada: (raw["includeCanada"] as? Bool) ?? d.includeCanada,
                includeMexico: (raw["includeMexico"] as? Bool) ?? d.includeMexico,
                startTripRightAway: (raw["startTripRightAway"] as? Bool) ?? d.startTripRightAway
            )
        }

        /// Full map so merge does not wipe sibling keys inside `gameDefaults`.
        var firestoreMap: [String: Bool] {
            [
                "includeUS": includeUS,
                "includeCanada": includeCanada,
                "includeMexico": includeMexico,
                "startTripRightAway": startTripRightAway
            ]
        }
    }

    /// Result of reading `appPrefs.gameDefaults`. `cloudMapPresent` is false when the nested map was never written (migrate-from-local opportunity).
    struct GameDefaultsFetchResult: Equatable, Sendable {
        var defaults: GameDefaults
        var cloudMapPresent: Bool
    }

    func fetchGameDefaults(userId: String) async throws -> GameDefaultsFetchResult {
        let snapshot = try await db.collection("users").document(userId).getDocument()
        let appPrefs = snapshot.data()?["appPrefs"] as? [String: Any]
        let raw = appPrefs?["gameDefaults"] as? [String: Any]
        return GameDefaultsFetchResult(
            defaults: GameDefaults.fromFirestoreMap(raw),
            cloudMapPresent: raw != nil
        )
    }

    /// Writes all keys under `appPrefs.gameDefaults` via dotted-path merge so sibling `appPrefs` fields survive.
    func updateGameDefaults(userId: String, defaults: GameDefaults) async throws {
        try await db.collection("users").document(userId).setData([
            "appPrefs.gameDefaults": defaults.firestoreMap
        ], merge: true)
    }

    // MARK: - Participation defaults (account seed for per-trip participant prefs)

    struct ParticipationDefaultsFetchResult: Equatable, Sendable {
        var defaults: ParticipationDefaults
        var cloudMapPresent: Bool
    }

    func fetchParticipationDefaults(userId: String) async throws -> ParticipationDefaultsFetchResult {
        let snapshot = try await db.collection("users").document(userId).getDocument()
        let appPrefs = snapshot.data()?["appPrefs"] as? [String: Any]
        let raw = appPrefs?["participationDefaults"] as? [String: Any]
        return ParticipationDefaultsFetchResult(
            defaults: ParticipationDefaults.fromFirestoreMap(raw),
            cloudMapPresent: raw != nil
        )
    }

    func updateParticipationDefaults(userId: String, defaults: ParticipationDefaults) async throws {
        try await db.collection("users").document(userId).setData([
            "appPrefs.participationDefaults": defaults.firestoreMap
        ], merge: true)
    }
}


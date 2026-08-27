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
    /// COPPA §7.1 projection: in-memory mirror of `users/{uid}.isChildAccount`
    /// (server-owned; never persisted to SwiftData — same pattern as
    /// `entitlementTagsByUserId`). An entry exists only after THIS session freshly
    /// read the user doc; sign-out clears it.
    private var childResolutionByUserId: [String: ChildAccountResolution] = [:]
    /// COPPA FR-88 projection: whether `users/{uid}` carried `pendingFamilyRequest` in a
    /// server-resolved snapshot. Server-owned, Firestore-only, never persisted to SwiftData
    /// (§7.4) — same pattern as the two dictionaries above. An entry exists only after THIS
    /// session freshly read the doc, which is exactly what makes ABSENCE meaningful.
    private var pendingFamilyRequestByUserId: [String: Bool] = [:]
    private let friendsFamilyAccessPolicy: FriendsFamilyAccessPolicy
    
    @Published var searchResults: [AppUser] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

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

    // MARK: - Child-account projection (COPPA F-7, SRS §7.1)

    /// One resolution of `users/{uid}.isChildAccount`, carrying BOTH the effective
    /// value and whether the document literally contained the key.
    ///
    /// Two bits, not one, because the two consumers need different things and
    /// collapsing them is what made an absent field dangerous:
    /// - **Gating** (posture, ads) uses `isChild`, where §4's "an existing doc without
    ///   the flag means not-a-child" is correct and necessary — a legitimate adult
    ///   document never carries the key, and treating that as unresolved would hold
    ///   every adult account forever.
    /// - **The destructive F-8 manager-correction path** uses `isServerExplicit`, and
    ///   accepts ONLY a key the server actually wrote. An absent key is the *absence of
    ///   evidence*, never a manager's decision to un-child an account.
    struct ChildAccountResolution: Equatable, Sendable {
        /// §4 effective value: absent key resolves to `false`.
        var isChild: Bool
        /// True only when the resolved document actually contained `isChildAccount`.
        var isServerExplicit: Bool
    }

    /// Tri-state read of the server flag as freshly resolved THIS session:
    /// - `true` / `false` — this session read `users/{userId}` and resolved the flag.
    /// - `nil` — not resolved yet. nil is NEVER treated as "not child" for gating
    ///   (FR-19: an unresolved current uid keeps the ads/posture hold).
    func isChildAccount(for userId: String) -> Bool? {
        guard !userId.isEmpty else { return nil }
        return childResolutionByUserId[userId]?.isChild
    }

    /// Whether this session's resolution of `userId` came from a document that
    /// EXPLICITLY carried `isChildAccount`. False when unresolved or when the key was
    /// absent. Only an explicit value may authorize retiring a child's lineage.
    func isChildAccountFlagExplicit(for userId: String) -> Bool {
        guard !userId.isEmpty else { return false }
        return childResolutionByUserId[userId]?.isServerExplicit ?? false
    }

    /// Ingest requires stating provenance, so no call site can record a resolution
    /// without saying whether the server actually wrote the key.
    func ingestChildAccountResolution(userId: String, _ resolution: ChildAccountResolution) {
        guard !userId.isEmpty else { return }
        childResolutionByUserId[userId] = resolution
    }

    /// Distinguishes "explicitly `false`" from "key absent" — the distinction the
    /// correction gate turns on. Both resolve `isChild == false` for gating.
    static func parseChildAccountResolution(from data: [String: Any]) -> ChildAccountResolution {
        guard let explicit = data["isChildAccount"] as? Bool else {
            return ChildAccountResolution(isChild: false, isServerExplicit: false)
        }
        return ChildAccountResolution(isChild: explicit, isServerExplicit: true)
    }

    /// §4 semantics: on an EXISTING doc, a missing flag means "not a child". The
    /// tri-state nil case is "no fresh doc data", handled by the accessor above.
    static func parseIsChildAccount(from data: [String: Any]) -> Bool {
        parseChildAccountResolution(from: data).isChild
    }

    // MARK: - Pending family request projection (COPPA FR-88)

    /// Tri-state read of `users/{userId}.pendingFamilyRequest` as freshly resolved THIS
    /// session:
    /// - `true` — the server says a family is holding an undecided join request.
    /// - `false` — a SERVER-RESOLVED snapshot carried no such field, so nobody is deciding.
    ///   This is the half that matters: it is what lets a device discover that the request it
    ///   still believes is outstanding was declined, and unstick itself.
    /// - `nil` — unresolved this session (offline, or no server read yet). Callers fall back
    ///   to the device's optimistic flag rather than guessing.
    ///
    /// Presence is the entire signal; the payload is never read. The field is server-written
    /// only (`firestore.rules` diff-guard), so `true` cannot be forged and `false` cannot be
    /// manufactured by a client clearing it.
    func hasPendingFamilyRequest(for userId: String) -> Bool? {
        guard !userId.isEmpty else { return nil }
        return pendingFamilyRequestByUserId[userId]
    }

    /// Ingest is FR-19-gated at every call site (`ChildFlagIngestPolicy`): a cached or
    /// latency-compensated snapshot must never record `false`, because for a doc whose stamp
    /// the server wrote moments ago the local cache legitimately does not have it yet.
    func ingestPendingFamilyRequest(userId: String, isPresent: Bool) {
        guard !userId.isEmpty else { return }
        pendingFamilyRequestByUserId[userId] = isPresent
    }

    /// Presence only — a malformed or non-map value still means "the server put something
    /// here", which is the conservative reading (keeps the child's "waiting" state up rather
    /// than silently retiring a live request).
    static func parsePendingFamilyRequestPresence(from data: [String: Any]) -> Bool {
        data["pendingFamilyRequest"] != nil
    }

    /// COPPA F-8 (FR-1/FR-25): fresh read of ANOTHER user's child flag for the manager
    /// approval surface. Returns `nil` when the doc cannot be read — which is expected,
    /// not exceptional: FR-12 denies peer reads of a child's `users/{uid}` doc to anyone
    /// outside the child's family, and a pending join requester is not a member yet.
    /// Callers MUST treat `nil` as "unresolved" and demand an explicit declaration —
    /// never as "not a child".
    func fetchIsChildAccount(userId: String) async -> Bool? {
        guard !userId.isEmpty else { return nil }
        do {
            let document = try await db.collection("users").document(userId).getDocument()
            guard let data = document.data() else { return nil }
            // FR-19 (GAP 2): the same snapshot-provenance gate every other ingest path
            // applies. A cached or pending-write snapshot is not a fresh server read, so
            // it neither resolves the shared projection nor answers the manager's
            // approval question — both fail closed to "unresolved".
            guard ChildFlagIngestPolicy.mayIngest(
                isFromCache: document.metadata.isFromCache,
                hasPendingWrites: document.metadata.hasPendingWrites
            ) else { return nil }
            let resolution = Self.parseChildAccountResolution(from: data)
            ingestChildAccountResolution(userId: userId, resolution)
            return resolution.isChild
        } catch {
            #if DEBUG
            print("UserRepository.fetchIsChildAccount unreadable for \(userId): \(error.localizedDescription)")
            #endif
            return nil
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
        childResolutionByUserId.removeAll()
        pendingFamilyRequestByUserId.removeAll()
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
                try await mergeRemoteProfileIntoCache(
                    userId: userId,
                    data: data,
                    isServerResolved: ChildFlagIngestPolicy.mayIngest(
                        isFromCache: userDoc.metadata.isFromCache,
                        hasPendingWrites: userDoc.metadata.hasPendingWrites
                    )
                )
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
    /// - Parameter isServerResolved: FR-19 — whether the snapshot is this session's
    ///   fresh SERVER read (see `ChildFlagIngestPolicy`). Only then may it resolve the
    ///   child projection; profile fields merge either way.
    func mergeRemoteUserDocument(userId: String, data: [String: Any], isServerResolved: Bool) async throws {
        try await mergeRemoteProfileIntoCache(userId: userId, data: data, isServerResolved: isServerResolved)
        postUserProfilesMergedIfNeeded([userId])
    }

    private func mergeRemoteProfileIntoCache(
        userId: String,
        data: [String: Any],
        isServerResolved: Bool
    ) async throws {
        ingestEntitlementTags(userId: userId, tags: Self.parseEntitlementTags(from: data))
        // COPPA §7.1: projection only — the flag never reaches the AppUser model or
        // any SwiftData row (§7.4). Propagates via the `.userProfilesMerged` post.
        // FR-19: a cached / latency-compensated snapshot never confirms not-child.
        if isServerResolved {
            ingestChildAccountResolution(userId: userId, Self.parseChildAccountResolution(from: data))
            // FR-88: same gate, same reason, other field. A cached snapshot that has not
            // caught up with the server's stamp would report "no request pending" and clear a
            // child's waiting state out from under a captain who is still deciding.
            ingestPendingFamilyRequest(
                userId: userId,
                isPresent: Self.parsePendingFamilyRequestPresence(from: data)
            )
        }
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
        // Same hold as the user-doc writers: after remove-and-delete, the child device's
        // token re-registration would otherwise recreate `private/fcm` under the dead uid
        // (setData(merge:) creates) — the last resurrection path W3-B's sweep found.
        try assertMayWriteUserDocument(userId: userId)
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
        try assertMayWriteUserDocument(userId: userId)
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
        try assertMayWriteUserDocument(userId: userId)
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
        try assertMayWriteUserDocument(userId: userId)
        try await db.collection("users").document(userId).setData([
            "appPrefs.participationDefaults": defaults.firestoreMap
        ], merge: true)
    }

    // MARK: - users/{uid} write guard (COPPA FR-27 ordering)

    /// Gate for every `users/{uid}` writer in this repository. All of them use
    /// `setData(merge: true)`, which CREATES the document when it is absent — so any of
    /// them can provision a brand-new account's `users/{uid}` with no `isChildAccount`
    /// on it, ahead of the declaration.
    ///
    /// Concrete path this closes: `ContentView.handleHomeOnAppear` → `AppPrefsStore.load`
    /// → (cloud map absent for a brand-new uid) → `updateGameDefaults`, which fires
    /// unconditionally on the first Home-tab appearance. For a child mid-registration
    /// that wrote a flagless doc that reads back as not-a-child.
    ///
    /// Only the declare-before-write choke point may bring the document into existence.
    ///
    /// FR-60(c) second half: the same `setData(merge: true)` create is also how a DELETED
    /// child's document came back — a decline or remove-and-delete removes the Auth user and
    /// `users/{uid}`, but the device kept the uid and kept writing to it. The
    /// pending-declaration hold could never cover that (it releases once a declaration
    /// lands, and a deleted account's had), so detached uids are held here too.
    ///
    /// FR-60(b)/(d) third hold (device pass 2026-08-17, bug 2): an unconsented child with no
    /// family deciding about them has no sanctioned server footprint at all, so none of these
    /// writers may address their uid either — prefs, game defaults, participation defaults,
    /// and `private/fcm` (which FR-73's provisional-token guard independently wants closed for
    /// exactly this population). The two uid-set holds above cannot express it: this child's
    /// declaration LANDED and their account is very much alive.
    private func assertMayWriteUserDocument(userId: String) throws {
        if UnconsentedChildCloudWritePolicy.isWriteHeld(
            isUnconsentedChild: ChildRestrictedModeService.shared.isRestrictedUnconsentedChild,
            isFamilyApprovalPending: ChildRestrictedModeService.shared.isFamilyApprovalPending,
            // Was hardcoded `false`, on the reasoning that nothing in this repository
            // participates in FR-60(b)'s PROVISIONING sequence. True, and beside the point:
            // the window is not about provisioning, it is about a child pursuing admission
            // (FR-26), and while that attempt is in flight this repository's writers are as
            // sanctioned as the profile write. `AgeGateStore` owns the window so every hold
            // reads one answer.
            isSeekingConsentNow: AgeGateStore.shared.isSeekingConsent(userId: userId)
        ) {
            throw UserDocumentWriteHeldError(userId: userId)
        }
        guard UserDocumentWritePolicy.isWriteHeld(
            userId: userId,
            pendingDeclarationUserIds: AgeGateStore.shared.pendingDeclarationUserIds,
            detachedIdentityUserIds: AgeGateStore.shared.detachedIdentityUserIds
        ) else { return }
        throw UserDocumentWriteHeldError(userId: userId)
    }
}


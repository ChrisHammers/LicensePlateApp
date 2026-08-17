//
//  FamilyRepository.swift
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

@MainActor
class FamilyRepository: ObservableObject, FamilyChildStatusManaging {
    static let shared = FamilyRepository()
    
    private let db = Firestore.firestore()
    private var modelContext: ModelContext?
    nonisolated(unsafe) private var listeners: [ListenerRegistration] = []
    nonisolated(unsafe) private var isListening = false
    nonisolated(unsafe) private var currentFamilyId: String?
    
    @Published var families: [Family] = []
    @Published var familyMembers: [String: [FamilyMember]] = [:] // familyId -> members
    @Published var pendingRequests: [String: [PendingJoinRequest]] = [:] // familyId -> requests
    /// COPPA §7.2 projection: `families/{familyId}/members/{uid}.isChild`, server-written
    /// and read-only here. Deliberately NOT a `FamilyMember` stored property — the
    /// SwiftData schema is frozen (§7.4) — so it lives beside the model rows exactly the
    /// way `UserRepository.entitlementTagsByUserId` does. familyId -> (userId -> isChild).
    @Published private(set) var childMemberFlags: [String: [String: Bool]] = [:]
    /// FR-86 identity stamps for pending rows — familyId -> (requestId -> stamp). Same
    /// arrangement as `childMemberFlags` and for the same reason: `PendingJoinRequest` sits
    /// in the frozen V1 schema, so the stamp cannot be a stored property, and (device pass
    /// 2026-08-17) it cannot be a `@Transient` one either — the rows the UI renders come back
    /// out of SwiftData via `getPendingRequests`, where a transient is nil by definition.
    /// Parsed at decode, published beside the rows, keyed by the id the views already have.
    @Published private(set) var pendingIdentityStamps: [String: [String: PendingIdentityStamp]] = [:]
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    /// `shared` is the app-wide instance. The initializer stays internal so tests can
    /// build an isolated repository instead of mutating shared state.
    init() {}
    
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }
    
    // MARK: - Sync from Firestore
    
    /// Start listening to a family and its members
    func startListening(familyId: String) {
        // Don't restart if already listening to the same family
        if isListening && currentFamilyId == familyId {
            return
        }
        
        stopListening()
        
        currentFamilyId = familyId
        isListening = true
        
        // Listen to family document
        let familyListener = db.collection("families").document(familyId)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    self?.handleFamilySnapshot(snapshot: snapshot, error: error)
                }
            }
        
        listeners.append(familyListener)
        
        // Listen to members subcollection
        let membersListener = db.collection("families").document(familyId)
            .collection("members")
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    self?.handleMembersSnapshot(snapshot: snapshot, error: error, familyId: familyId)
                }
            }
        
        listeners.append(membersListener)
        
        // Listen to pending requests subcollection
        let pendingListener = db.collection("families").document(familyId)
            .collection("pending")
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    self?.handlePendingSnapshot(snapshot: snapshot, error: error, familyId: familyId)
                }
            }
        
        listeners.append(pendingListener)
    }
    
    /// Start listening to all families for a user (via activeFamilyId)
    func startListeningForUser(userId: String) {
        // First get user's activeFamilyId
        let userDoc = db.collection("users").document(userId)
        userDoc.getDocument { [weak self] snapshot, error in
            Task { @MainActor in
                if let data = snapshot?.data(),
                   let activeFamilyId = data["activeFamilyId"] as? String {
                    self?.startListening(familyId: activeFamilyId)
                }
            }
        }
    }
    
    private func handleFamilySnapshot(snapshot: DocumentSnapshot?, error: Error?) {
        if let error = error {
            // Check if it's a permission error - if so, stop listening
            let nsError = error as NSError
            if nsError.domain == "FIRFirestoreErrorDomain" && (nsError.code == 7 || nsError.code == 3) {
                // Permission denied or not found - stop listening
                Task { @MainActor in
                    self.stopListening()
                }
                return
            }
            // Don't set error message for permission errors to avoid UI flashing
            return
        }
        
        guard let snapshot = snapshot, snapshot.exists,
              let modelContext = modelContext,
              let family = Family(from: snapshot) else {
            // Family doesn't exist - stop listening
            Task { @MainActor in
                self.stopListening()
            }
            return
        }
        
        // Check if family is inactive - if so, stop listening
        if family.statusEnum == .inactive {
            Task { @MainActor in
                self.stopListening()
            }
            return
        }
        
        // Sync to SwiftData
        let searchFamilyId = family.familyId
        let descriptor = FetchDescriptor<Family>(
            predicate: #Predicate<Family> { f in
                f.familyId == searchFamilyId
            }
        )
        
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.name = family.name
            existing.creatorId = family.creatorId
            existing.status = family.status
            existing.createdAt = family.createdAt
            existing.updatedAt = family.updatedAt
        } else {
            modelContext.insert(family)
        }
        
        // Update published array
        let allDescriptor = FetchDescriptor<Family>()
        if let allFamilies = try? modelContext.fetch(allDescriptor) {
            families = allFamilies
        }
        
        try? modelContext.save()
    }
    
    private func handleMembersSnapshot(snapshot: QuerySnapshot?, error: Error?, familyId: String) {
        if let error = error {
            // Check if it's a permission error - if so, stop listening
            let nsError = error as NSError
            if nsError.domain == "FIRFirestoreErrorDomain" && (nsError.code == 7 || nsError.code == 3) {
                // Permission denied or not found - stop listening
                Task { @MainActor in
                    self.stopListening()
                }
                return
            }
            // Don't set error message for permission errors to avoid UI flashing
            return
        }
        
        guard let snapshot = snapshot, let modelContext = modelContext else { return }

        var members: [FamilyMember] = []
        var userIdsToFetch: [String] = []

        for document in snapshot.documents {
            if let member = FamilyMember(from: document, familyId: familyId) {
                members.append(member)
                userIdsToFetch.append(member.userId)
            }
        }
        applyChildMemberFlags(Self.parseChildMemberFlags(documents: snapshot.documents), familyId: familyId)

        // Sync members to SwiftData
        for member in members {
            let searchMemberId = member.id
            let descriptor = FetchDescriptor<FamilyMember>(
                predicate: #Predicate<FamilyMember> { m in
                    m.id == searchMemberId
                }
            )

            if let existing = try? modelContext.fetch(descriptor).first {
                existing.familyId = member.familyId
                existing.userId = member.userId
                existing.role = member.role
                existing.canInvite = member.canInvite
                existing.canEditSettings = member.canEditSettings
                existing.joinedAt = member.joinedAt
                existing.updatedAt = member.updatedAt
            } else {
                modelContext.insert(member)
            }
        }
        // A member doc that vanished from the snapshot was REMOVED. Without this the
        // local row survives forever and the roster shows a ghost member whose every
        // server action then fails with "Member not found".
        pruneLocalMembers(familyId: familyId, keepingUserIds: Set(members.map(\.userId)))

        try? modelContext.save()

        // Publish SwiftData members immediately, then hydrate user links and republish.
        familyMembers[familyId] = getMembers(familyId: familyId)
        Task {
            await self.fetchAndCacheUsers(userIds: userIdsToFetch, familyId: familyId)
            self.republishLinkedMembersAndPending(familyId: familyId)
        }
    }
    
    private func handlePendingSnapshot(snapshot: QuerySnapshot?, error: Error?, familyId: String) {
        if let error = error {
            // Check if it's a permission error - if so, stop listening
            let nsError = error as NSError
            if nsError.domain == "FIRFirestoreErrorDomain" && (nsError.code == 7 || nsError.code == 3) {
                // Permission denied or not found - stop listening
                Task { @MainActor in
                    self.stopListening()
                }
                return
            }
            // Don't set error message for permission errors to avoid UI flashing
            return
        }
        
        guard let snapshot = snapshot, let modelContext = modelContext else { return }

        var requests: [PendingJoinRequest] = []
        var userIdsToFetch: [String] = []
        var stampSources: [(requestId: String, data: [String: Any])] = []

        for document in snapshot.documents {
            if let request = PendingJoinRequest(from: document, familyId: familyId) {
                requests.append(request)
                userIdsToFetch.append(request.userId)
                // FR-86: read the stamp off the RAW doc, here, while we still have it. It
                // never reaches the SwiftData row (frozen schema), so this is its only
                // capture point.
                stampSources.append((requestId: request.requestId, data: document.data()))
            }
        }
        applyPendingIdentityStamps(
            Self.parsePendingIdentityStamps(documents: stampSources),
            familyId: familyId
        )

        // Cache complete AppUser data for pending users — deferred until after SwiftData sync
        // Sync requests to SwiftData
        for request in requests {
            let searchRequestId = request.requestId
            let descriptor = FetchDescriptor<PendingJoinRequest>(
                predicate: #Predicate<PendingJoinRequest> { r in
                    r.requestId == searchRequestId
                }
            )
            
            if let existing = try? modelContext.fetch(descriptor).first {
                existing.familyId = request.familyId
                existing.userId = request.userId
                existing.requestedBy = request.requestedBy
                existing.method = request.method
                existing.status = request.status
                existing.createdAt = request.createdAt
                existing.resolvedAt = request.resolvedAt
            } else {
                modelContext.insert(request)
            }
        }
        
        try? modelContext.save()
        
        pendingRequests[familyId] = getPendingRequests(familyId: familyId)
        Task {
            await self.fetchAndCacheUsers(userIds: userIdsToFetch, familyId: familyId)
            self.republishLinkedMembersAndPending(familyId: familyId)
        }
    }
    
    /// Fetch and cache complete AppUser data for family members / pending users.
    /// Links `user` relationships on SwiftData entities before returning.
    private func fetchAndCacheUsers(userIds: [String], familyId: String) async {
        guard let modelContext = modelContext else { return }

        // Keep UserRepository on the same store so getUser cache + Firestore merge land here.
        UserRepository.shared.setModelContext(modelContext)

        let uniqueIds = Array(Set(userIds)).filter { !$0.isEmpty }
        for userId in uniqueIds {
            do {
                if try await UserRepository.shared.getUser(userId: userId) != nil {
                    linkUserToMembers(userId: userId, familyId: familyId)
                } else {
                    #if DEBUG
                    print("⚠️ FamilyRepository.fetchAndCacheUsers: getUser returned nil for \(userId)")
                    #endif
                }
            } catch {
                #if DEBUG
                print("⚠️ FamilyRepository.fetchAndCacheUsers: getUser failed for \(userId): \(error.localizedDescription)")
                #endif
            }
        }
    }
    
    /// Republish members and pending from SwiftData so UI sees linked `user` relationships.
    private func republishLinkedMembersAndPending(familyId: String) {
        familyMembers[familyId] = getMembers(familyId: familyId)
        pendingRequests[familyId] = getPendingRequests(familyId: familyId)
    }
    
    /// Link cached AppUser to FamilyMember and PendingJoinRequest.
    /// Internal for unit tests that verify post-cache linking.
    func linkUserToMembers(userId: String, familyId: String) {
        guard let modelContext = modelContext else { return }
        
        let searchUserId = userId
        let userDescriptor = FetchDescriptor<AppUser>(
            predicate: #Predicate<AppUser> { user in
                user.id == searchUserId || user.firebaseUID == searchUserId
            }
        )
        
        guard let user = try? modelContext.fetch(userDescriptor).first else { return }
        
        // Link to FamilyMember
        let searchFamilyId = familyId
        let memberDescriptor = FetchDescriptor<FamilyMember>(
            predicate: #Predicate<FamilyMember> { member in
                member.familyId == searchFamilyId && member.userId == searchUserId
            }
        )
        
        if let member = try? modelContext.fetch(memberDescriptor).first {
            member.user = user
        }
        
        // Link to PendingJoinRequest
        let requestDescriptor = FetchDescriptor<PendingJoinRequest>(
            predicate: #Predicate<PendingJoinRequest> { request in
                request.familyId == searchFamilyId && request.userId == searchUserId
            }
        )
        
        if let request = try? modelContext.fetch(requestDescriptor).first {
            request.user = user
        }
        
        try? modelContext.save()
    }
    
    /// Stop listening to Firestore updates
    nonisolated func stopListening() {
        for listener in listeners {
            listener.remove()
        }
        listeners.removeAll()
        isListening = false
        currentFamilyId = nil
    }

    /// Hard sign-out: wipe family social cache tables and published state.
    func deleteAllLocal() throws {
        stopListening()
        guard let modelContext else {
            families = []
            familyMembers = [:]
            pendingRequests = [:]
            childMemberFlags = [:]
            errorMessage = nil
            return
        }
        try modelContext.delete(model: PendingJoinRequest.self)
        try modelContext.delete(model: FamilyMember.self)
        try modelContext.delete(model: Family.self)
        try modelContext.delete(model: ShareCode.self)
        try modelContext.save()
        families = []
        familyMembers = [:]
        pendingRequests = [:]
        childMemberFlags = [:]
        errorMessage = nil
    }

    // MARK: - Local Queries
    
    /// Get family by ID (from SwiftData)
    func getFamily(familyId: String) -> Family? {
        guard let modelContext = modelContext else { return nil }
        
        let searchFamilyId = familyId
        let descriptor = FetchDescriptor<Family>(
            predicate: #Predicate<Family> { family in
                family.familyId == searchFamilyId
            }
        )
        
        return try? modelContext.fetch(descriptor).first
    }
    
    /// Get members for a family (from SwiftData)
    func getMembers(familyId: String) -> [FamilyMember] {
        guard let modelContext = modelContext else { return [] }
        
        let searchFamilyId = familyId
        let descriptor = FetchDescriptor<FamilyMember>(
            predicate: #Predicate<FamilyMember> { member in
                member.familyId == searchFamilyId
            }
        )
        
        return (try? modelContext.fetch(descriptor)) ?? []
    }
    
    /// Get pending requests for a family (from SwiftData)
    func getPendingRequests(familyId: String) -> [PendingJoinRequest] {
        guard let modelContext = modelContext else { return [] }
        
        let searchFamilyId = familyId
        let pendingStatus = "pending"
        let descriptor = FetchDescriptor<PendingJoinRequest>(
            predicate: #Predicate<PendingJoinRequest> { request in
                request.familyId == searchFamilyId && request.status == pendingStatus
            }
        )
        
        return (try? modelContext.fetch(descriptor)) ?? []
    }
    
    // MARK: - Firestore Fetch (Online Priority)
    
    /// Fetch family directly from Firestore (prioritizes online data)
    func fetchFamily(familyId: String) async throws -> Family? {
        guard let modelContext = modelContext else {
            throw NSError(domain: "FamilyRepository", code: -1, userInfo: [NSLocalizedDescriptionKey: "Model context not set"])
        }
        
        let doc = try await db.collection("families").document(familyId).getDocument()
        
        guard doc.exists else {
            return nil
        }
        
        guard let family = Family(from: doc) else {
            return nil
        }
        
        // Sync to SwiftData
        let searchFamilyId = family.familyId
        let descriptor = FetchDescriptor<Family>(
            predicate: #Predicate<Family> { f in
                f.familyId == searchFamilyId
            }
        )
        
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.name = family.name
            existing.creatorId = family.creatorId
            existing.status = family.status
            existing.createdAt = family.createdAt
            existing.updatedAt = family.updatedAt
        } else {
            modelContext.insert(family)
        }
        
        try? modelContext.save()
        
        // Update published array
        let allDescriptor = FetchDescriptor<Family>()
        if let allFamilies = try? modelContext.fetch(allDescriptor) {
            families = allFamilies
        }
        
        return family
    }
    
    /// Fetch members directly from Firestore (prioritizes online data)
    func fetchMembers(familyId: String) async throws -> [FamilyMember] {
        guard let modelContext = modelContext else {
            throw NSError(domain: "FamilyRepository", code: -1, userInfo: [NSLocalizedDescriptionKey: "Model context not set"])
        }
        
        let snapshot = try await db.collection("families").document(familyId)
            .collection("members")
            .getDocuments()
        
        var members: [FamilyMember] = []
        var userIdsToFetch: [String] = []
        
        for document in snapshot.documents {
            if let member = FamilyMember(from: document, familyId: familyId) {
                members.append(member)
                userIdsToFetch.append(member.userId)
            }
        }
        applyChildMemberFlags(Self.parseChildMemberFlags(documents: snapshot.documents), familyId: familyId)

        // Sync members to SwiftData
        for member in members {
            let searchMemberId = member.id
            let descriptor = FetchDescriptor<FamilyMember>(
                predicate: #Predicate<FamilyMember> { m in
                    m.id == searchMemberId
                }
            )

            if let existing = try? modelContext.fetch(descriptor).first {
                existing.familyId = member.familyId
                existing.userId = member.userId
                existing.role = member.role
                existing.canInvite = member.canInvite
                existing.canEditSettings = member.canEditSettings
                existing.joinedAt = member.joinedAt
                existing.updatedAt = member.updatedAt
            } else {
                modelContext.insert(member)
            }
        }
        pruneLocalMembers(familyId: familyId, keepingUserIds: Set(members.map(\.userId)))

        try? modelContext.save()

        await fetchAndCacheUsers(userIds: userIdsToFetch, familyId: familyId)
        republishLinkedMembersAndPending(familyId: familyId)

        return getMembers(familyId: familyId)
    }

    // MARK: - Roster reconciliation

    /// Deletes cached members of `familyId` that the server no longer lists. The members
    /// snapshot/fetch is authoritative for the whole subcollection, so anything missing
    /// from it has been removed. Internal so tests can drive it with an id set instead of
    /// a `QuerySnapshot`.
    func pruneLocalMembers(familyId: String, keepingUserIds: Set<String>) {
        guard let modelContext else { return }
        let searchFamilyId = familyId
        let descriptor = FetchDescriptor<FamilyMember>(
            predicate: #Predicate<FamilyMember> { $0.familyId == searchFamilyId }
        )
        guard let cached = try? modelContext.fetch(descriptor) else { return }
        for member in cached where !keepingUserIds.contains(member.userId) {
            modelContext.delete(member)
        }
    }

    /// Immediate local reconciliation for a membership the CALLER just ended. The
    /// snapshot follows within a round trip, but the roster must not show a member the
    /// server has already deleted — every retry against that ghost fails server-side.
    func removeLocalMember(familyId: String, memberUserId: String) {
        if var flags = childMemberFlags[familyId] {
            flags.removeValue(forKey: memberUserId)
            childMemberFlags[familyId] = flags
        }
        guard let modelContext else { return }
        let searchFamilyId = familyId
        let searchUserId = memberUserId
        let descriptor = FetchDescriptor<FamilyMember>(
            predicate: #Predicate<FamilyMember> { member in
                member.familyId == searchFamilyId && member.userId == searchUserId
            }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            modelContext.delete(existing)
            try? modelContext.save()
        }
        familyMembers[familyId] = getMembers(familyId: familyId)
    }

    // MARK: - Child-member projection (COPPA §7.2, FR-20)

    /// Member-doc `isChild` mirror. §4 convention: a missing key means NOT a child.
    /// Only `true` values are retained so the map stays small and unambiguous.
    static func parseChildMemberFlags(documents: [QueryDocumentSnapshot]) -> [String: Bool] {
        var flags: [String: Bool] = [:]
        for document in documents where (document.data()["isChild"] as? Bool) == true {
            flags[document.documentID] = true
        }
        return flags
    }

    /// Publishes a parsed projection for one family. The snapshot handlers are the
    /// production callers; keeping it a named method (rather than an inline assignment)
    /// gives the projection a single write point.
    func applyChildMemberFlags(_ flags: [String: Bool], familyId: String) {
        childMemberFlags[familyId] = flags
    }

    /// Child user ids in a family — the badge/manage surfaces' single source. View
    /// models mirror this set; views render the mirror and never derive child status.
    func childMemberIds(familyId: String) -> Set<String> {
        Set((childMemberFlags[familyId] ?? [:]).filter { $0.value }.keys)
    }
    
    /// Fetch pending requests directly from Firestore (prioritizes online data)
    func fetchPendingRequests(familyId: String) async throws -> [PendingJoinRequest] {
        guard let modelContext = modelContext else {
            throw NSError(domain: "FamilyRepository", code: -1, userInfo: [NSLocalizedDescriptionKey: "Model context not set"])
        }
        
        let snapshot = try await db.collection("families").document(familyId)
            .collection("pending")
            .whereField("status", isEqualTo: "pending")
            .getDocuments()
        
        var requests: [PendingJoinRequest] = []
        var userIdsToFetch: [String] = []
        var stampSources: [(requestId: String, data: [String: Any])] = []

        for document in snapshot.documents {
            if let request = PendingJoinRequest(from: document, familyId: familyId) {
                requests.append(request)
                userIdsToFetch.append(request.userId)
                // FR-86: same capture point as the listener path. This is the one that runs
                // on a cold store after a reinstall, which is the case the device pass caught.
                stampSources.append((requestId: request.requestId, data: document.data()))
            }
        }
        applyPendingIdentityStamps(
            Self.parsePendingIdentityStamps(documents: stampSources),
            familyId: familyId
        )

        // Sync requests to SwiftData
        for request in requests {
            let searchRequestId = request.requestId
            let descriptor = FetchDescriptor<PendingJoinRequest>(
                predicate: #Predicate<PendingJoinRequest> { r in
                    r.requestId == searchRequestId
                }
            )

            if let existing = try? modelContext.fetch(descriptor).first {
                existing.familyId = request.familyId
                existing.userId = request.userId
                existing.requestedBy = request.requestedBy
                existing.method = request.method
                existing.status = request.status
                existing.createdAt = request.createdAt
                existing.resolvedAt = request.resolvedAt
            } else {
                modelContext.insert(request)
            }
        }

        try? modelContext.save()

        await fetchAndCacheUsers(userIds: userIdsToFetch, familyId: familyId)
        republishLinkedMembersAndPending(familyId: familyId)

        return getPendingRequests(familyId: familyId)
    }

    /// FR-86 render projection: the stamped identity for one pending row, or `nil` when the
    /// server stamped nothing (or the rows came from the SwiftData cache without a decode
    /// this session). Consumers keep their "Pending User" + placeholder fallback for `nil`.
    func pendingIdentityStamp(familyId: String, requestId: String) -> PendingIdentityStamp? {
        pendingIdentityStamps[familyId]?[requestId]
    }

    /// Test seam mirroring `applyChildMemberFlags`: gives the projection a single write point
    /// that does not require a live Firestore snapshot.
    func applyPendingIdentityStamps(_ stamps: [String: PendingIdentityStamp], familyId: String) {
        pendingIdentityStamps[familyId] = stamps
    }

    /// Parses the FR-86 stamps out of a raw pending-collection snapshot. Split out so the
    /// decode is testable without the network — the reinstall shape (cold store, fresh
    /// decode) is exactly what this has to get right.
    static func parsePendingIdentityStamps(
        documents: [(requestId: String, data: [String: Any])]
    ) -> [String: PendingIdentityStamp] {
        var stamps: [String: PendingIdentityStamp] = [:]
        for document in documents {
            stamps[document.requestId] = PendingIdentityStamp(firestoreData: document.data)
        }
        return stamps
    }
    
    // MARK: - Cloud Functions

    private func requireRegisteredAccount() throws {
        try FriendsFamilyAccessPolicy.shared.validateFriendsFamilyCallableAccess(for: nil)
    }

    /// COPPA F-18 (FR-60(b)): the consent exits also admit a declared child's anonymous
    /// session. See `FriendsFamilyAccessPolicy.validateConsentExitCallableAccess`.
    private func requireRegisteredAccountOrDeclaredChild() throws {
        try FriendsFamilyAccessPolicy.shared.validateConsentExitCallableAccess(for: nil)
    }
    
    /// Create a new family
    func createFamily(name: String) async throws -> String {
        try requireRegisteredAccount()
        
        let functions = Functions.functions()
        let createFamilyFunction = functions.httpsCallable("createFamily")
        
        let result: HTTPSCallableResult
        do {
            result = try await createFamilyFunction.call(([
                "name": name
            ] as [String: Any]).addingClientMetadata())
        } catch {
            throw Self.userFacingCallableError(error)
        }
        
        guard let data = result.data as? [String: Any],
              let familyId = data["familyId"] as? String else {
            throw NSError(domain: "FamilyRepository", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response from createFamily"])
        }
        
        return familyId
    }
    
    /// Redeem a share code on a specific surface.
    ///
    /// COPPA FR-67: `expectedType` names the screen doing the redeeming, and the server
    /// refuses a code of the other kind — a friend code fed to the join-a-family flow used
    /// to mint a stranger→child friend invite that was only blocked later, at accept. It is
    /// REQUIRED server-side, so it can never be dropped to skip the check.
    func redeemShareCode(
        code: String,
        expectedType: ShareCode.ShareCodeType
    ) async throws -> String {
        // COPPA FR-60(b): a child provisioned at share-code entry is still anonymous here.
        // The caller runs the mint → bind → declare sequence before this point; this gate
        // stops an ordinary anonymous guest while letting the declared child through, and
        // the server's `assertRegisteredAccountOrDeclaredChild` remains the authority.
        try requireRegisteredAccountOrDeclaredChild()

        let functions = Functions.functions()
        let redeemCodeFunction = functions.httpsCallable("redeemShareCode")

        let result: HTTPSCallableResult
        do {
            result = try await redeemCodeFunction.call(([
                "code": code,
                "expectedType": expectedType.rawValue
            ] as [String: Any]).addingClientMetadata())
        } catch {
            throw Self.userFacingCallableError(error)
        }
        
        guard let data = result.data as? [String: Any],
              let inviteId = data["inviteId"] as? String else {
            throw NSError(domain: "FamilyRepository", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response from redeemShareCode"])
        }

        // F-8 device testing (2026-08-15): every family-code redemption call site (join
        // sheet, onboarding join view) funnels through here, so this is the one place to
        // mark the FR-28 home banner's "waiting for approval" state. Friend-code
        // redemptions never touch family membership and are excluded; an already-
        // consented (or adult) caller is excluded too — the banner never shows for them.
        if expectedType == .family, ChildRestrictedModeService.shared.isRestrictedUnconsentedChild {
            ChildRestrictedModeService.shared.markFamilyApprovalPending()
        }

        return inviteId
    }
    
    /// Send a family invite to a user
    func sendFamilyInvite(toUserId: String, familyId: String, method: String = "search") async throws -> String {
        // COPPA FR-41: same guest gate its sibling callables use; the server remains the backstop.
        try requireRegisteredAccount()

        let functions = Functions.functions()
        let sendInviteFunction = functions.httpsCallable("sendFamilyInvite")
        
        let result = try await sendInviteFunction.call(([
            "toUserId": toUserId,
            "familyId": familyId,
            "method": method
        ] as [String: Any]).addingClientMetadata())
        
        guard let data = result.data as? [String: Any],
              let inviteId = data["inviteId"] as? String else {
            throw NSError(domain: "FamilyRepository", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response from sendFamilyInvite"])
        }
        
        return inviteId
    }
    
    /// Respond to a family invite (user step)
    func respondToFamilyInvite(inviteId: String, accept: Bool) async throws {
        guard Auth.auth().currentUser != nil else {
            throw NSError(domain: "FamilyRepository", code: 401, userInfo: [NSLocalizedDescriptionKey: "User must be authenticated"])
        }
        
        let functions = Functions.functions()
        let respondFunction = functions.httpsCallable("respondToFamilyInvite_UserStep")
        
        _ = try await respondFunction.call(([
            "inviteId": inviteId,
            "response": accept ? "accept" : "decline"
        ] as [String: Any]).addingClientMetadata())
    }
    
    /// Get familyId from an invite
    func getFamilyIdFromInvite(inviteId: String) async throws -> String? {
        let inviteDoc = try await db.collection("invites").document(inviteId).getDocument()
        guard let data = inviteDoc.data() else { return nil }
        return data["familyId"] as? String
    }
    
    /// Create a share code (friend or family type)
    func createShareCode(type: String, familyId: String? = nil) async throws -> (codeId: String, code: String, expiresAt: Date) {
        try requireRegisteredAccount()

        let functions = Functions.functions()
        let createCodeFunction = functions.httpsCallable("createShareCode")

        var data: [String: Any] = ["type": type]
        if let familyId = familyId {
            data["familyId"] = familyId
        }

        let result: HTTPSCallableResult
        do {
            result = try await createCodeFunction.call(data.addingClientMetadata())
        } catch {
            throw Self.userFacingCallableError(error)
        }
        
        guard let resultData = result.data as? [String: Any],
              let codeId = resultData["codeId"] as? String,
              let code = resultData["code"] as? String,
              let expiresAtString = resultData["expiresAt"] as? String else {
            throw NSError(domain: "FamilyRepository", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response from createShareCode"])
        }
        
        let formatter = ISO8601DateFormatter()
        let expiresAt = formatter.date(from: expiresAtString) ?? Date().addingTimeInterval(15 * 60)
        
        return (codeId: codeId, code: code, expiresAt: expiresAt)
    }
    
    /// Revoke a share code
    func revokeShareCode(codeId: String) async throws {
        guard Auth.auth().currentUser != nil else {
            throw NSError(domain: "FamilyRepository", code: 401, userInfo: [NSLocalizedDescriptionKey: "User must be authenticated"])
        }
        
        try await db.collection("share_codes").document(codeId).updateData([
            "isRevoked": true
        ])
    }
    
    /// Approve or decline a pending join request.
    ///
    /// COPPA FR-1/FR-25: an approval may carry the manager's child declaration. For a
    /// target the server already sees as a child the declaration is MANDATORY — the
    /// callable rejects a silent approval so a flag can never be laundered through
    /// re-admission. The UI resolves that state before enabling Approve.
    func respondToPendingRequest(
        familyId: String,
        requestId: String,
        approve: Bool,
        childDeclaration: ChildApprovalDraft? = nil
    ) async throws {
        guard Auth.auth().currentUser != nil else {
            throw NSError(domain: "FamilyRepository", code: 401, userInfo: [NSLocalizedDescriptionKey: "User must be authenticated"])
        }

        let functions = Functions.functions()
        let respondFunction = functions.httpsCallable("approveFamilyJoinRequest_CaptainStep")

        let payload = FamilyChildStatusPayload.respondToPendingRequest(
            familyId: familyId,
            requestId: requestId,
            approve: approve,
            declaration: childDeclaration
        )
        _ = try await respondFunction.call(payload.addingClientMetadata())
    }

    // MARK: - Child status callables (COPPA F-8: FR-2, FR-29, FR-30)

    /// FR-2/FR-4/FR-5: creator/captain sets a member's child status, or clears it as a
    /// CORRECTION (`correctionReason` required). Consent withdrawal is never expressed
    /// here — that is removal (FR-6) or `requestChildDataDeletion` (FR-30).
    func setChildStatus(
        familyId: String,
        memberUserId: String,
        isChild: Bool,
        consentAcknowledged: Bool = false,
        guardianAffirmed: Bool = false,
        correctionReason: ChildStatusCorrectionReason? = nil,
        expectedAgeOutYear: Int? = nil
    ) async throws {
        try requireRegisteredAccount()

        let payload: [String: Any]
        if isChild {
            payload = FamilyChildStatusPayload.setChild(
                familyId: familyId,
                memberUserId: memberUserId,
                consent: ChildConsentDraft(
                    consentAcknowledged: consentAcknowledged,
                    guardianAffirmed: guardianAffirmed,
                    expectedAgeOutYear: expectedAgeOutYear
                )
            )
        } else {
            guard let correctionReason else {
                throw NSError(
                    domain: "FamilyRepository",
                    code: 400,
                    userInfo: [NSLocalizedDescriptionKey: "family.child.error.correction_reason_required".localized]
                )
            }
            payload = FamilyChildStatusPayload.clearChild(
                familyId: familyId,
                memberUserId: memberUserId,
                correctionReason: correctionReason
            )
        }

        let respondFunction = Functions.functions().httpsCallable("setFamilyMemberChildStatus")
        do {
            _ = try await respondFunction.call(payload.addingClientMetadata())
        } catch {
            throw Self.childStatusCallableError(error)
        }
    }

    /// FR-30: manager-gated "remove and delete child's data". The server removes the
    /// membership (REVOKED `parent_requested_deletion`) and runs the full account
    /// deletion machinery against the child uid.
    func requestChildDataDeletion(familyId: String, childUserId: String) async throws {
        try requireRegisteredAccount()

        let payload = FamilyChildStatusPayload.requestChildDataDeletion(
            familyId: familyId,
            childUserId: childUserId
        )
        let deleteFunction = Functions.functions().httpsCallable("requestChildDataDeletion")
        do {
            _ = try await deleteFunction.call(payload.addingClientMetadata())
        } catch {
            throw Self.childStatusCallableError(error)
        }
    }

    /// FR-29 (SHOULD): manager-gated consent history. `audit_logs` stays client-
    /// inaccessible; the callable returns curated, uid-free rows.
    func getParentalConsentStatus(familyId: String, childUserId: String) async throws -> ParentalConsentStatus {
        try requireRegisteredAccount()

        let payload = FamilyChildStatusPayload.parentalConsentStatus(
            familyId: familyId,
            childUserId: childUserId
        )
        let statusFunction = Functions.functions().httpsCallable("getParentalConsentStatus")
        do {
            let result = try await statusFunction.call(payload.addingClientMetadata())
            return ParentalConsentStatus.parse(result.data)
        } catch {
            throw Self.childStatusCallableError(error)
        }
    }

    /// Localized, non-leaky mapping for the child-status callables. The server's own
    /// messages are English-only and describe states this UI already prevents, so they
    /// are replaced rather than surfaced.
    static func childStatusCallableError(_ error: Error) -> Error {
        let nsError = error as NSError
        guard nsError.domain == FunctionsErrorDomain,
              let code = FunctionsErrorCode(rawValue: nsError.code) else {
            return error
        }

        let message: String
        switch code {
        case .permissionDenied:
            message = "family.child.error.permission_denied".localized
        case .notFound:
            // The caller reconciles this one (FamilyMembershipRecoveryPolicy); the text
            // only shows if it ever reaches an alert.
            message = "family.child.error.already_removed".localized
        case .failedPrecondition:
            message = "family.child.error.not_allowed".localized
        case .invalidArgument:
            message = "family.child.error.invalid".localized
        case .unavailable, .deadlineExceeded:
            message = "family.child.error.unavailable".localized
        case .unauthenticated:
            message = "family.child.error.signed_out".localized
        default:
            message = "family.child.error.server".localized
        }

        return NSError(
            domain: nsError.domain,
            code: nsError.code,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
    
    /// Rename family via direct Firestore write (captain/creator). Rules allow only `name` + `updatedAt`.
    func updateFamilyName(familyId: String, name: String) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw NSError(
                domain: "FamilyRepository",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Enter family name".localized]
            )
        }
        guard trimmed.count <= 80 else {
            throw NSError(
                domain: "FamilyRepository",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Enter family name".localized]
            )
        }
        guard Auth.auth().currentUser != nil else {
            throw NSError(
                domain: "FamilyRepository",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "User not authenticated".localized]
            )
        }
        guard let modelContext else {
            throw NSError(
                domain: "FamilyRepository",
                code: 500,
                userInfo: [NSLocalizedDescriptionKey: "Unknown error".localized]
            )
        }

        let now = Date()
        try await db.collection("families").document(familyId).updateData([
            "name": trimmed,
            "updatedAt": Timestamp(date: now)
        ])

        let searchFamilyId = familyId
        let descriptor = FetchDescriptor<Family>(
            predicate: #Predicate<Family> { f in
                f.familyId == searchFamilyId
            }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.name = trimmed
            existing.updatedAt = now
        }
        let allDescriptor = FetchDescriptor<Family>()
        if let allFamilies = try? modelContext.fetch(allDescriptor) {
            families = allFamilies
        }
        try? modelContext.save()
    }

    /// Leave family (remove current user from family)
    func leaveFamily(familyId: String) async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "FamilyRepository", code: 401, userInfo: [NSLocalizedDescriptionKey: "User must be authenticated"])
        }
        
        // Use removeFamilyMember function; server allows non-creator self-leave
        let functions = Functions.functions()
        let removeFunction = functions.httpsCallable("removeFamilyMember")
        
        _ = try await removeFunction.call(([
            "familyId": familyId,
            "memberId": userId
        ] as [String: Any]).addingClientMetadata())
    }

    /// Remove another family member (creator/captain; UI gates to creator)
    func removeMember(familyId: String, memberId: String) async throws {
        guard Auth.auth().currentUser != nil else {
            throw NSError(domain: "FamilyRepository", code: 401, userInfo: [NSLocalizedDescriptionKey: "User must be authenticated"])
        }

        let functions = Functions.functions()
        let removeFunction = functions.httpsCallable("removeFamilyMember")

        _ = try await removeFunction.call(([
            "familyId": familyId,
            "memberId": memberId
        ] as [String: Any]).addingClientMetadata())
    }
    
    /// Delete/Inactivate family (creator only) - uses Cloud Function
    func deleteFamily(familyId: String) async throws {
        guard let userId = Auth.auth().currentUser?.uid,
              let modelContext = modelContext else {
            throw NSError(domain: "FamilyRepository", code: 401, userInfo: [NSLocalizedDescriptionKey: "User must be authenticated"])
        }
        
        // Stop listening BEFORE deletion to prevent permission errors
        // Once family is inactive, user loses access and listeners will fail
        stopListening()
        
        // Use Cloud Function to delete family (handles permissions server-side)
        let functions = Functions.functions()
        let deleteFunction = functions.httpsCallable("inactivateFamily")
        
        _ = try await deleteFunction.call(([
            "familyId": familyId
        ] as [String: Any]).addingClientMetadata())
        
        // Manually update local SwiftData cache since listeners are stopped
        // Mark family as inactive
        let familyDescriptor = FetchDescriptor<Family>(
            predicate: #Predicate<Family> { $0.familyId == familyId }
        )
        if let family = try? modelContext.fetch(familyDescriptor).first {
            family.status = "inactive"
        }
        
        // Remove all members for this family
        let membersDescriptor = FetchDescriptor<FamilyMember>(
            predicate: #Predicate<FamilyMember> { $0.familyId == familyId }
        )
        if let members = try? modelContext.fetch(membersDescriptor) {
            for member in members {
                modelContext.delete(member)
            }
        }
        
        // Clear activeFamilyId for current user if not retired general;
        // sticky-flag locally so unlocks remain until hydrate.
        let userDescriptor = FetchDescriptor<AppUser>(
            predicate: #Predicate<AppUser> { $0.firebaseUID == userId || $0.id == userId }
        )
        if let user = try? modelContext.fetch(userDescriptor).first {
            user.wasEverInFamily = true
            if !user.isRetiredGeneral {
                user.activeFamilyId = nil
            }
        }
        
        // Update published arrays
        let allFamiliesDescriptor = FetchDescriptor<Family>()
        if let allFamilies = try? modelContext.fetch(allFamiliesDescriptor) {
            families = allFamilies
        }
        familyMembers[familyId] = []
        pendingRequests[familyId] = []
        childMemberFlags[familyId] = [:]
        
        try? modelContext.save()
    }
    
    /// Get active share code for a family (non-expired, non-revoked)
    func getActiveShareCode(familyId: String) async throws -> ShareCode? {
        guard Auth.auth().currentUser != nil else {
            throw NSError(domain: "FamilyRepository", code: 401, userInfo: [NSLocalizedDescriptionKey: "User must be authenticated"])
        }
        
        let now = Date()
        
        // Query only by familyId to avoid composite index requirement
        // Filter isRevoked and expiresAt client-side
        let query = db.collection("share_codes")
            .whereField("familyId", isEqualTo: familyId)
            .limit(to: 50) // Get recent codes (shouldn't be many active at once)
        
        let snapshot = try await query.getDocuments()
        
        // Filter client-side: not revoked, not expired, then sort by createdAt descending
        let activeCodes = snapshot.documents
            .compactMap { ShareCode(from: $0) }
            .filter { !$0.isRevoked && $0.expiresAt > now }
            .sorted { $0.createdAt > $1.createdAt }
        
        return activeCodes.first
    }
    
    /// Clear family data from SwiftData cache (marks as inactive, removes members)
    func clearFamilyFromCache(familyId: String) {
        guard let modelContext = modelContext else { return }
        
        // Mark family as inactive in cache
        let familyDescriptor = FetchDescriptor<Family>(
            predicate: #Predicate<Family> { $0.familyId == familyId }
        )
        if let family = try? modelContext.fetch(familyDescriptor).first {
            family.status = "inactive"
        }
        
        // Remove all members
        let membersDescriptor = FetchDescriptor<FamilyMember>(
            predicate: #Predicate<FamilyMember> { $0.familyId == familyId }
        )
        if let members = try? modelContext.fetch(membersDescriptor) {
            for member in members {
                modelContext.delete(member)
            }
        }
        
        // Remove pending requests
        let pendingDescriptor = FetchDescriptor<PendingJoinRequest>(
            predicate: #Predicate<PendingJoinRequest> { $0.familyId == familyId }
        )
        if let pending = try? modelContext.fetch(pendingDescriptor) {
            for request in pending {
                modelContext.delete(request)
            }
        }
        
        try? modelContext.save()
        
        // Update published arrays
        let allFamiliesDescriptor = FetchDescriptor<Family>()
        if let allFamilies = try? modelContext.fetch(allFamiliesDescriptor) {
            families = allFamilies
        }
        familyMembers[familyId] = []
        pendingRequests[familyId] = []
        childMemberFlags[familyId] = [:]
    }
    
    deinit {
        stopListening()
    }

    private static func userFacingCallableError(_ error: Error) -> Error {
        let nsError = error as NSError
        guard nsError.domain == FunctionsErrorDomain,
              let code = FunctionsErrorCode(rawValue: nsError.code) else {
            return error
        }

        // F-6 (FR-28): child-restriction rejections get the non-punitive family copy,
        // never the guest/registration framing.
        if ChildRestrictedModeService.isChildRestrictionRejection(error) {
            return NSError(
                domain: nsError.domain,
                code: nsError.code,
                userInfo: [NSLocalizedDescriptionKey: FriendsFamilyCallableErrors.childRestrictionMessage]
            )
        }

        let message: String
        switch code {
        case .unauthenticated:
            if Auth.auth().currentUser == nil {
                message = "You are not signed in. Sign in and try again."
            } else if Auth.auth().currentUser?.isAnonymous == true {
                message = "Create an account to use Friends & Family features."
            } else {
                message = "The server rejected this request. Sign in and try again."
            }
        case .failedPrecondition:
            // FR-24 keeps the SERVER's refusal byte-identical for "unregistered" and
            // "child not admitted", so the client cannot tell them apart from the error —
            // but it can tell them apart from the SESSION. Telling a child on a child
            // device to "create an account" is both wrong (FR-60(e): they have no account
            // to create) and the exact misdirection reported when a declined child's uid
            // had been deleted underneath them.
            message = ChildRestrictedModeService.shared.isChildAccountSession
                ? FriendsFamilyCallableErrors.childRestrictionMessage
                : "Create an account to use Friends & Family features."
        case .permissionDenied:
            message = "You do not have permission to create this share code."
        case .unavailable:
            message = "The server is temporarily unavailable. Try again shortly."
        case .internal:
            message = "The server encountered an error while creating the share code. Try again in a moment."
        default:
            return error
        }

        return NSError(
            domain: nsError.domain,
            code: nsError.code,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}


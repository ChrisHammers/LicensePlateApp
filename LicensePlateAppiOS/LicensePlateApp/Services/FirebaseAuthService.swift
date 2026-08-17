//
//  FirebaseAuthService.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//

import Foundation
import Combine
import SwiftData
import UIKit
import FirebaseAuth
import FirebaseFirestore
import FirebaseCore
import FirebaseFunctions
import FirebaseAnalytics
import AuthenticationServices
import GoogleSignIn
import Network
import CryptoKit

/// Network monitoring for offline detection
@MainActor
class NetworkMonitor: ObservableObject {
    @Published var isConnected = true
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            // Read `path` only inside the handler (NWPath lifetime).
            let satisfied = path.status == .satisfied
            Task { @MainActor in
                self?.isConnected = satisfied
            }
        }
        monitor.start(queue: queue)
    }
}

/// Firebase Authentication Service - Simplified flow
/// 1. On app startup: Create default user, sign in anonymously if online
/// 2. User can upgrade anonymous account by linking credentials (email/password, OAuth)
@MainActor
class FirebaseAuthService: ObservableObject {
    @Published var currentUser: AppUser?
    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showUsernameConflictDialog = false
    
    // Track active linking operations to prevent multiple simultaneous calls
    private var isLinking = false
    @Published var conflictDialogMessage = ""
    @Published var conflictDialogNewUsername = ""
    @Published var showSignInSheet = false
    
    // Callback for username conflict resolution
    var usernameConflictResolver: ((String?) -> Void)?
    
    // Firebase instances
    private let auth = Auth.auth()
    private let db = Firestore.firestore()
    
    private var modelContext: ModelContext?
    private weak var syncCoordinator: SyncCoordinatorProtocol?
    private var authStateListener: AuthStateDidChangeListenerHandle?
    private let networkMonitor = NetworkMonitor()
    private var networkReachabilityCancellables = Set<AnyCancellable>()
    private var progressionBootstrapAttemptedUserIds: Set<String> = []
    private var founderEntitlementAttemptedUserIds: Set<String> = []
    /// When false, unsatisfied→satisfied transitions do not schedule gameplay sync (avoids flushing before `RootView` wires repos + `setSyncCoordinator`).
    private var gameplaySyncFlushOnReachabilityRegainedEnabled = false

    /// Published mirror of reachability so SwiftUI can react when connectivity returns.
    @Published private(set) var isNetworkReachable: Bool

    // Track last login tracking time to prevent duplicates
    private var lastLoginTrackingTime: Date?

    /// F-6 (FR-27, identity-epoch rule): true when the CURRENT identity is an
    /// unprovisioned guest with no age answer for this identity epoch. Sign-out and
    /// account deletion clear the epoch — no NEW anonymous uid is ever provisioned
    /// unanswered, and a stored answer never carries across identities. The age
    /// question is ASKED at exactly two moments (genuine first launch; sign-up with an
    /// unanswered epoch); a post-sign-out reborn guest is never prompted — it stays a
    /// restricted local guest (option B). Signed-in sessions (uid exists) never gate.
    var requiresAgeGateForGuestProvisioning: Bool {
        guard let user = currentUser else { return false }
        return GuestProvisioningPolicy.requiresAgeGate(
            hasFirebaseUid: user.firebaseUID != nil,
            isResolved: AgeGateStore.shared.isResolved
        )
    }
    
    init() {
        isNetworkReachable = networkMonitor.isConnected
        // Observe auth state changes
        authStateListener = auth.addStateDidChangeListener { [weak self] auth, user in
            Task { @MainActor in
                await self?.handleAuthStateChange(user)
            }
        }
        networkMonitor.$isConnected
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] connected in
                guard let self else { return }
                let wasReachable = self.isNetworkReachable
                self.isNetworkReachable = connected
                guard self.gameplaySyncFlushOnReachabilityRegainedEnabled else { return }
                if !wasReachable && connected {
                    SyncCoordinator.shared.scheduleDebouncedGameplaySyncFlushIfOnline()
                }
            }
            .store(in: &networkReachabilityCancellables)
    }
    
    deinit {
        if let listener = authStateListener {
            auth.removeStateDidChangeListener(listener)
        }
    }
    
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    func setSyncCoordinator(_ coordinator: SyncCoordinatorProtocol) {
        self.syncCoordinator = coordinator
        gameplaySyncFlushOnReachabilityRegainedEnabled = true
    }
    
    // MARK: - Network Status

    /// Same as `isNetworkReachable`; kept for existing call sites (`isOnline` reads).
    var isOnline: Bool { isNetworkReachable }
    
    /// Returns info about a restored Firebase user (from Keychain) if they exist and are not anonymous.
    /// Use this on onboarding to offer "Sign in as existing user" when a previous session was restored.
    var restoredUserInfo: (userName: String, email: String)? {
        guard let firebaseUser = auth.currentUser, !firebaseUser.isAnonymous else { return nil }
        let userName = currentUser?.userName ?? firebaseUser.displayName ?? "User"
        let email = firebaseUser.email ?? ""
        return (userName, email)
    }
    
    // MARK: - Initialization
    
    /// Initialize authentication state (call on app startup)
    func initializeAuthState(modelContext: ModelContext) async {
        self.modelContext = modelContext
        
        // Check if Firebase Auth already has a user (persisted session)
        if let firebaseUser = auth.currentUser {
            // Firebase has a user, load it
            await loadUserFromFirebase(firebaseUser)
        } else {
            // No Firebase user, check for local user by device
            let deviceId = DeviceIdentifier.getDeviceIdentifier()
            let descriptor = FetchDescriptor<AppUser>(
                predicate: #Predicate<AppUser> { $0.deviceIdentifier == deviceId }
            )
            
            if let existingUser = try? modelContext.fetch(descriptor).first {
                // Found existing user, set as current
                currentUser = existingUser
                isAuthenticated = true
                
                // If online and user has firebaseUID, try to restore Firebase session
                if isOnline, let firebaseUID = existingUser.firebaseUID {
                    // Try to load from Firestore
                    Task {
                        try? await loadUserDataFromFirestore(userId: firebaseUID)
                    }
                } else if isOnline, existingUser.firebaseUID == nil {
                    // User exists locally but no Firebase account - sign in anonymously.
                    // (Existing local guest ⇒ not a genuine first launch; never gated.)
                    Task {
                        try? await signInAnonymously()
                    }
                }
            } else {
                // No user exists, create default user
                try? await createDefaultUser()
            }
        }
        // FR-60(c) eager verification (device pass 2026-08-16, bug 1). `loadUserFromFirebase`
        // above already detaches on a confirmed-absent bootstrap read, but that read is the
        // cache-tolerant `getDocument()` — an offline or cache-served launch reports the
        // document present and the one-shot check is spent. This forces the `.server` read on
        // session restore, so a deletion that landed while the app was closed is caught before
        // any writer can paper over it. Costs one extra document read per launch, and only for
        // an anonymous session this device DECLARED as a child — every other session is
        // refused by `requiresVerification` before any network happens.
        await verifyAnonymousChildIdentityIfNeeded(force: true)

        // COPPA F-7 (FR-23): the auth listener may have fired before `modelContext`
        // existed; this is the same identity-transition seam, re-run now that the
        // session is fully bootstrapped.
        ChildSessionPostureCoordinator.shared.applyPostures(trigger: .identityTransition)
    }
    
    // MARK: - Default User Creation
    
    /// Create default user with device-based username
    private func createDefaultUser() async throws {
        try createFreshLocalGuestUser()

        // F-6 (FR-27): anonymous provisioning (auth account + first users/{uid} write)
        // waits for this identity epoch's age answer. If it already exists (QA
        // `--skipOnboarding` seeding), provision immediately.
        if isOnline, AgeGateStore.shared.isResolved {
            Task {
                try? await signInAnonymously()
            }
        }
    }

    /// F-6 (FR-27): called when a guest age step completes (first launch or rebirth).
    /// Performs the deferred anonymous sign-in; an under-13 answer is declared inside
    /// `signInAnonymously` for exactly the uid it creates, before its first profile write.
    ///
    /// F-18 follow-up (FR-60(a), FR-74(d′) spirit): the answer is applied to the IDENTITY
    /// first. A reinstall restores the Keychain's anonymous uid before the age screen is ever
    /// shown, and an under-13 answer that lands on such a session produces the chimera
    /// `RestoredIdentityAgeAnswerPolicy` documents — half the app treating it as a child, the
    /// other half writing a flagless `users/{uid}` for one. Detaching first makes the deferred
    /// provisioning below correct by construction: the session is a clean, uid-less
    /// local-first child, exactly as a genuine first install would be.
    func completeDeferredGuestProvisioningIfNeeded() async {
        await applyRecordedAgeAnswerToRestoredIdentity()

        guard AgeGateStore.shared.isResolved,
              let user = currentUser,
              user.firebaseUID == nil,
              isOnline else {
            return
        }
        try? await signInAnonymously()
    }

    /// FR-60(a) / FR-74(d′) spirit: drop a restored anonymous identity that the age answer
    /// just recorded does not own. LOCAL ONLY — the account may hold another person's data,
    /// and deleting it server-side is never this device's call.
    ///
    /// Called from every surface that presents the age screen. Two of them
    /// (`OnboardingContainerView`, `QuickSoloStartView`) reach it through
    /// `completeDeferredGuestProvisioningIfNeeded`; `SignInView`'s in-form ask calls it
    /// directly, because that flow deliberately does not provision a guest.
    func applyRecordedAgeAnswerToRestoredIdentity() async {
        guard let firebaseUser = auth.currentUser else { return }
        let store = AgeGateStore.shared
        let uid = firebaseUser.uid
        guard RestoredIdentityAgeAnswerPolicy.requiresLocalDetach(
            category: store.category,
            isAnonymousSession: firebaseUser.isAnonymous,
            isBoundToCurrentAnswer: store.isPendingDeclaration(userId: uid)
                || store.isDeclaredChildUserId(uid)
        ) else { return }

        await detachAnonymousIdentityLocally(uid: uid, reason: "restored_identity_under13_answer")
    }

    /// FR-60(c) EAGER detection (device pass 2026-08-16, bug 1). Verifies that the anonymous
    /// identity this session is running on still exists server-side, and detaches it the
    /// moment it is confirmed gone.
    ///
    /// Wave 1 only looked on identity EDGES — the auth-state bootstrap, share-code redemption,
    /// and Firebase's own force-sign-out. A captain's remove-and-delete produces none of them
    /// on the child's device: the account disappears while the app sits in the foreground, and
    /// the cached ID token keeps authenticating reads and writes for the rest of its hour.
    ///
    /// The window is self-sealing, which is what made it stick: the first self-doc write inside
    /// it (`saveUserDataToFirestore` from an avatar edit) RECREATES `users/{uid}` with
    /// `setData(merge: true)`, so the next launch's bootstrap reads `.present`, the detach never
    /// fires, and the device settles into a permanent half-state — a live-looking anonymous uid
    /// whose account is gone. Checking on foreground and on session restore closes it before a
    /// write can.
    ///
    /// Debounced, because `scenePhase` flips on every notification-centre pull. A read failure
    /// is never actionable (`.unknown`), so an offline foreground costs nothing but a no-op.
    func verifyAnonymousChildIdentityIfNeeded(force: Bool = false) async {
        guard let firebaseUser = auth.currentUser else { return }
        let uid = firebaseUser.uid
        let store = AgeGateStore.shared

        guard DetachedIdentityDetectionPolicy.requiresVerification(
            hasFirebaseUid: true,
            isAnonymousSession: firebaseUser.isAnonymous,
            wasDeclaredByThisDevice: store.isDeclaredChildUserId(uid),
            isAlreadyDetached: store.isIdentityDetached(uid),
            isOnline: isOnline
        ) else { return }

        if !force, let last = lastIdentityVerificationAt,
           Date().timeIntervalSince(last) < Self.identityVerificationDebounce {
            return
        }
        lastIdentityVerificationAt = .now

        let status = await selfUserDocumentStatus(userId: uid)
        guard DetachedIdentityDetectionPolicy.requiresDetach(
            isAnonymousSession: firebaseUser.isAnonymous,
            documentStatus: status,
            wasDeclaredByThisDevice: store.isDeclaredChildUserId(uid)
        ) else { return }

        await detachAnonymousIdentityLocally(uid: uid, reason: "server_deleted_identity_eager")
    }

    /// Foreground checks must not turn a notification-centre pull into a Firestore read storm.
    private static let identityVerificationDebounce: TimeInterval = 30
    private var lastIdentityVerificationAt: Date?

    /// The one teardown both zombie paths share: end the Auth session, retire the uid so no
    /// `users/{uid}` writer can address it again, and leave the device as an UNPROVISIONED
    /// local-first player.
    ///
    /// Local gameplay rows are deliberately untouched and `AppUser.id` deliberately keeps the
    /// retired uid, so `firebaseUID ?? id` still resolves every trip, discovery and XP row the
    /// player already has — and the next provisioning rebinds them onto the new uid through
    /// FR-60(d)'s existing pass. The device ratchet (`declaredChildUserIds`, `ChildSignalCache`,
    /// the epoch answer) is preserved: the FR-60(c) cleanup preserves it deliberately, and
    /// nothing here is a correction.
    ///
    /// Deliberately logs NO analytics: both callers are child-session paths on a child's own
    /// device, which is the case the taxonomy must never carry (FR-21 / SRS §12).
    private func detachAnonymousIdentityLocally(uid: String, reason: StaticString) async {
        _ = reason // DEBUG-only provenance; never leaves the device.
        // Re-entrancy guard: the `auth.signOut()` below fires the auth-state listener, whose
        // `releaseVanishedAnonymousIdentityIfNeeded` now routes back into this same teardown.
        // One settle per uid — the outer call finishes it.
        guard detachesInFlightUids.insert(uid).inserted else { return }
        defer { detachesInFlightUids.remove(uid) }

        AgeGateStore.shared.markIdentityDetached(userId: uid)
        // Device pass 2026-08-16 (bug 1): the detach has to settle the WHOLE session, not
        // just the uid. A "waiting for your family's approval" flag that outlives the
        // identity it was recorded for is one half of a hybrid — the screen would keep
        // promising an answer from a captain who is looking at nothing.
        ChildRestrictedModeService.shared.clearFamilyApprovalPending()

        do {
            try auth.signOut()
        } catch {
            #if DEBUG
            print("⚠️ Local detach sign-out failed for \(uid): \(error)")
            #endif
        }
        // The auth-state listener runs as its own MainActor task; let it settle before the
        // local user is put back into its unprovisioned shape, so its `isAuthenticated = false`
        // cannot land after this method's own state.
        await Task.yield()

        UserRepository.shared.clearEntitlementTags(for: uid)

        // `currentUser` is nil on the launch path (the auth listener reaches here before the
        // bootstrap publishes anyone), so the row is resolved by uid as well.
        let existingRow = currentUser ?? modelContext.flatMap { context in
            try? context.fetch(
                FetchDescriptor<AppUser>(
                    predicate: #Predicate<AppUser> { $0.id == uid || $0.firebaseUID == uid }
                )
            ).first
        }

        if let user = existingRow {
            user.firebaseUID = nil
            user.email = nil
            user.linkedPlatforms = []
            user.activeFamilyId = nil
            user.lastDateLoggedIn = nil
            user.needsSync = false
            user.lastUpdated = .now
            try? modelContext?.save()
            currentUser = user
            isAuthenticated = true
        } else {
            // Nothing local to keep (reinstall): start the unprovisioned local-first session
            // the FR-60 model expects instead of leaving the app with no user at all.
            try? createFreshLocalGuestUser()
        }

        #if DEBUG
        print("F-18: detached local identity \(uid) (\(reason))")
        #endif
        ChildSessionPostureCoordinator.shared.applyPostures(trigger: .identityTransition)
    }

    /// The bootstrap read's outcome, in the vocabulary the detach decision speaks. A FAILED
    /// read is `.unknown`, never absence — an offline relaunch must never cost a live account
    /// its session.
    private static func selfDocumentStatus(
        for load: AuthProfileSyncPolicy.DocumentLoadStatus
    ) -> DetachedIdentityDetectionPolicy.SelfDocumentStatus {
        switch load {
        case .found: return .present
        case .notFound: return .confirmedAbsent
        case .failed: return .unknown
        }
    }

    /// Fresh SERVER read of the caller's own `users/{uid}`, reduced to the tri-state the
    /// detach decision needs. `.server` on purpose: the offline cache would happily report a
    /// document that the server deleted, and a stale "present" is the failure this whole
    /// guard exists to end. Any read failure is `.unknown`, which is never actionable.
    private func selfUserDocumentStatus(
        userId: String
    ) async -> DetachedIdentityDetectionPolicy.SelfDocumentStatus {
        guard isOnline else { return .unknown }
        do {
            let snapshot = try await db.collection("users").document(userId)
                .getDocument(source: .server)
            return snapshot.exists ? .present : .confirmedAbsent
        } catch {
            #if DEBUG
            print("⚠️ Self user-document read failed for \(userId): \(error)")
            #endif
            return .unknown
        }
    }

    /// F-6 (FR-27): binds the current epoch's under-13 answer to `flowUid` — a uid this
    /// flow just created or upgraded — and delivers `declareChildRegistration`.
    /// EVERY uid an under-13 epoch provisions is bound, so a second provisioning inside
    /// one epoch cannot slip through undeclared. Binding is scoped to the CURRENT
    /// epoch's answer, so a stored answer still cannot declare a pre-existing account
    /// (incident-1 regression).
    /// - Returns: false while a declaration for `flowUid` is still outstanding (the
    ///   caller must hold that uid's first profile write).
    private func ensureFlowChildDeclaration(flowUid: String) async -> Bool {
        let store = AgeGateStore.shared
        guard store.bindAndCheckDeclarationOutstanding(forFlowUserId: flowUid) else { return true }
        guard isOnline, auth.currentUser?.uid == flowUid else { return false }
        do {
            try await UserRepository.shared.declareChildRegistration()
            store.markChildDeclarationSent(userId: flowUid)
            return true
        } catch {
            #if DEBUG
            print("⚠️ declareChildRegistration failed; profile write stays held: \(error)")
            #endif
            return false
        }
    }

    /// F-18 (FR-60(b)/(d)): moves local play history from the device-local play identity onto
    /// the uid that has just been minted. Best-effort by design — a failure here must not
    /// abort provisioning, because an un-provisioned child cannot seek consent at all, and a
    /// history that stayed under the old id is recoverable while a blocked consent path is
    /// not. Logged loudly in DEBUG.
    private func rebindLocalPlayIdentity(from previousUserId: String, to newUserId: String) {
        guard LocalPlayIdentityRebindPolicy.shouldRebind(
            previousUserId: previousUserId,
            newUserId: newUserId
        ) else { return }
        do {
            // Same `ModelContext` this service saves the `AppUser` through, so the rebind and
            // the identity swap share one transaction boundary — and so the rebind still
            // works on paths that run before `RootView` has wired the repositories.
            if let modelContext {
                LocalPlayIdentityRepository.shared.setModelContext(modelContext)
            }
            let summary = try LocalPlayIdentityRepository.shared.rebindLocalPlayIdentity(
                from: previousUserId,
                to: newUserId
            )
            ReturnStreakService.shared.rebindLocalState(from: previousUserId, to: newUserId)
            #if DEBUG
            print("F-18: rebound \(summary.totalRowsRewritten) local rows onto \(newUserId)")
            #endif
        } catch {
            #if DEBUG
            print("⚠️ F-18: local play identity rebind failed: \(error)")
            #endif
        }
    }

    /// F-18 (FR-60(b)) — the ONE provisioning moment for an under-13 player.
    ///
    /// Share-code entry is the act of seeking parental consent, so it is the only place a
    /// child acquires a backend identity. Runs FR-60(b)'s sequence in order:
    ///
    ///   mint anonymous uid → bind (before `currentUser` publishes) → declareChildRegistration
    ///
    /// and leaves `redeemShareCode` to the caller, which must run LAST. `signInAnonymously`
    /// owns the first three steps and already enforces FR-27's bind-before-publish ordering;
    /// this method exists to name the moment, pass the consent-seeking override, and refuse to
    /// hand back a uid whose declaration never landed.
    ///
    /// - Throws: `AuthError.offline` when there is no network (the code cannot be redeemed
    ///   offline either), and `AuthError.childDeclarationPending` when the uid was minted but
    ///   `declareChildRegistration` did not land. The uid stays BOUND in that case — its
    ///   profile write is held by `UserDocumentWritePolicy`, so no flagless `users/{uid}` can
    ///   appear — and a retry re-enters `ensureFlowChildDeclaration` for the same uid.
    ///   Redemption must not proceed: the server carve-out admits an anonymous caller only on
    ///   a declared `isChildAccount`, and a captain approving an undeclared account would
    ///   admit a child as an adult.
    func provisionIdentityForConsentSeekingRedemptionIfNeeded() async throws {
        guard let localUser = currentUser else { throw AuthError.noUser }
        let store = AgeGateStore.shared

        // FR-60(c) zombie guard, BEFORE the "already has a uid ⇒ skip" shortcut below.
        // A declined or removed-and-deleted child still holds the dead uid in the Keychain,
        // and skipping on its strength is what made every subsequent share code fail as
        // "unregistered". Verified against a fresh SERVER read; an unreadable server leaves
        // the session exactly as it was.
        if ChildConsentRedemptionPolicy.requiresIdentityVerification(
            hasFirebaseUid: localUser.firebaseUID != nil,
            category: store.category
        ), let existingUid = localUser.firebaseUID {
            let status = await selfUserDocumentStatus(userId: existingUid)
            if DetachedIdentityDetectionPolicy.requiresDetach(
                isAnonymousSession: isAnonymousUser,
                documentStatus: status,
                wasDeclaredByThisDevice: store.isDeclaredChildUserId(existingUid)
            ) {
                await detachAnonymousIdentityLocally(uid: existingUid, reason: "server_deleted_identity")
            }
        }

        guard ChildConsentRedemptionPolicy.requiresProvisioning(
            hasFirebaseUid: localUser.firebaseUID != nil,
            category: store.category
        ) else {
            return
        }
        guard isOnline else { throw AuthError.offline }

        try await signInAnonymously(isConsentSeekingRedemption: true)

        let uid = currentUser?.firebaseUID
        guard ChildConsentRedemptionPolicy.mayRedeem(
            hasFirebaseUid: uid != nil,
            isDeclarationOutstanding: AgeGateStore.shared.isPendingDeclaration(userId: uid)
        ) else {
            throw AuthError.childDeclarationPending
        }
    }

    /// Inserts a new local guest `AppUser` with device default username. Does not touch Auth.
    private func createFreshLocalGuestUser() throws {
        guard let modelContext = modelContext else {
            throw AuthError.noModelContext
        }

        let deviceId = DeviceIdentifier.getDeviceIdentifier()
        let defaultUsername = DeviceIdentifier.generateDefaultUsername(deviceId: deviceId)

        let localID = UUID().uuidString
        let newUser = AppUser(
            id: localID,
            userName: defaultUsername,
            deviceIdentifier: deviceId,
            isUsernameManuallyChanged: false,
            needsSync: true
        )
        let randomAvatarId = AvatarCatalog.randomGuestAvatarId()
        newUser.avatarId = randomAvatarId

        modelContext.insert(newUser)
        try modelContext.save()

        currentUser = newUser
        isAuthenticated = true
    }

    // MARK: - Anonymous Authentication

    /// Sign in anonymously (creates Firebase anonymous account and links to local user)
    ///
    /// - Parameter isConsentSeekingRedemption: F-18 (FR-60(b)). The ONE caller allowed to
    ///   provision an under-13 identity — share-code entry, which is the act of seeking
    ///   parental consent. Every other caller leaves it false and an under-13 epoch stays
    ///   local-only, with no Firebase account and no `users/{uid}` document.
    func signInAnonymously(isConsentSeekingRedemption: Bool = false) async throws {
        guard let modelContext = modelContext,
              let localUser = currentUser else {
            throw AuthError.noUser
        }

        // If user already has firebaseUID, don't create new anonymous account
        if localUser.firebaseUID != nil {
            return
        }

        // F-6 (FR-27, identity-epoch rule): a NEW anonymous uid is never created
        // without an age answer for the current epoch — first launch and post-sign-out
        // guest rebirth alike. The gate UI re-invokes provisioning after the answer.
        //
        // F-18 (FR-60(a)): and an under-13 answer no longer provisions at all. This is the
        // single choke point all five provisioning call sites funnel through, so the rule
        // holds for relaunch, first launch, the deferred post-age-gate path, sign-out and
        // post-deletion rebirth without any of them restating it.
        guard GuestProvisioningPolicy.mayCreateAnonymousIdentity(
            category: AgeGateStore.shared.category,
            isConsentSeekingRedemption: isConsentSeekingRedemption
        ) else {
            localUser.needsSync = true
            try? modelContext.save()
            return
        }

        isLoading = true
        defer { isLoading = false }

        guard isOnline else {
            // Offline - mark for sync later
            localUser.needsSync = true
            try? modelContext.save()
            return
        }
        
        do {
            let result = try await auth.signInAnonymously()
            let firebaseUID = result.user.uid

            // This flow owns the uid from here until it publishes. Without this the
            // auth-state listener bootstraps the brand-new uid in parallel, finds no local
            // row yet, and replaces the local player with a default-named, avatar-less
            // `AppUser` — which is how the redemption-provisioned child lost the avatar and
            // username they had picked (owner device pass 2026-08-15).
            uidsBeingProvisionedLocally.insert(firebaseUID)
            defer { uidsBeingProvisionedLocally.remove(firebaseUID) }

            // F-6 (FR-27) — BIND BEFORE PUBLISHING, same invariant as the
            // `createNewUserFromFirebase` choke point: synchronous, no await, ahead of
            // `localUser.firebaseUID` below. The moment this uid is observable on
            // `currentUser`, SwiftUI can run `handleHomeOnAppear` → `AppPrefsStore.load`
            // → a `users/{uid}` writer that decides whether it is held by consulting
            // `pendingDeclarationUserIds`. Binding after the declaration's `await` would
            // leave that window unguarded by construction, not just by timing.
            AgeGateStore.shared.bindPendingDeclaration(toUserId: firebaseUID)

            // F-18 (FR-60(b)/(d)): under the local-first model this uid can arrive after
            // days of local play, so the play identity changes under an existing history.
            // Carry that history onto the new uid BEFORE `currentUser` publishes it —
            // otherwise the first view to re-read `firebaseUID ?? id` filters the child's
            // own trips and XP out, and FR-28h late-replay has nothing correct to upload.
            // A no-op for the ordinary guest case, where `previousLocalId == firebaseUID`
            // is impossible but the local id has no rows attached to it yet either.
            let previousLocalId = localUser.id
            rebindLocalPlayIdentity(from: previousLocalId, to: firebaseUID)

            // Link local user to Firebase anonymous account
            localUser.firebaseUID = firebaseUID
            localUser.id = firebaseUID // Update ID to Firebase UID
            localUser.localIDBeforeFirebase = previousLocalId
            localUser.needsSync = false

            try modelContext.save()

            // F-6 (FR-27): an under-13 answer from this flow binds to the uid the flow
            // just created and is declared BEFORE the first users/{uid} write. On
            // failure the profile write stays held (queued; choke point retries).
            guard await ensureFlowChildDeclaration(flowUid: firebaseUID) else {
                localUser.needsSync = true
                try? syncCoordinator?.enqueueUserProfileSync(userId: firebaseUID)
                try? modelContext.save()
                currentUser = localUser
                isAuthenticated = true
                return
            }

            // Save to Firestore
            try await saveUserDataToFirestore(localUser)

            currentUser = localUser
            isAuthenticated = true

            // COPPA F-7 (FR-19): a brand-new uid has no fresh `users/{uid}` READ yet,
            // so the ads/posture hold would otherwise persist all session. One fresh
            // read through the sanctioned merge path resolves it (and posts
            // `.userProfilesMerged`, which re-runs the posture seam).
            await UserRepository.shared.refreshUsersFromFirestoreIfPresent(userIds: [firebaseUID])
        } catch {
            print("⚠️ Anonymous sign-in failed: \(error)")
            // Continue with local user
            localUser.needsSync = true
            try? modelContext.save()
        }
    }
    
    // MARK: - Username Uniqueness Checking
    
    func isUsernameTakenLocally(_ username: String, excludingUserId: String? = nil) async throws -> Bool {
        guard let modelContext = modelContext else { return false }
        let descriptor = FetchDescriptor<AppUser>(
            predicate: #Predicate<AppUser> { $0.userName == username }
        )
        let users = try? modelContext.fetch(descriptor)
        
        guard let users = users, !users.isEmpty else {
            return false
        }
        
        if let excludingID = excludingUserId {
            let otherUsers = users.filter { $0.id != excludingID && $0.firebaseUID != excludingID }
            return !otherUsers.isEmpty
        }
        
        return true
    }
    
    func isUsernameTaken(_ username: String, excludingUserId: String? = nil) async throws -> Bool {
        // Check local first
        if try await isUsernameTakenLocally(username, excludingUserId: excludingUserId) {
            return true
        }
        
        // Check Firebase if online
        guard isOnline else {
            return false
        }
        
        do {
            let usersRef = db.collection("users")
            let query = usersRef.whereField("userName", isEqualTo: username).limit(to: 1)
            let snapshot = try await query.getDocuments()
            
            guard !snapshot.documents.isEmpty else {
                return false
            }
            
            if let excludingUID = excludingUserId {
                let matchingDocs = snapshot.documents.filter { doc in
                    doc.documentID != excludingUID
                }
                return !matchingDocs.isEmpty
            }
            
            return true
        } catch {
            print("⚠️ Firebase username check failed: \(error)")
            return false
        }
    }
    
    // MARK: - Authentication Status
    
    var isTrulyAuthenticated: Bool {
        guard let firebaseUser = auth.currentUser else {
            return false
        }
        return !firebaseUser.isAnonymous
    }
    
    var isAnonymousUser: Bool {
        guard let firebaseUser = auth.currentUser else {
            return currentUser?.firebaseUID != nil && !isTrulyAuthenticated
        }
        return firebaseUser.isAnonymous
    }

    /// FR-60(c): true when the identity this session would address has been retired by this
    /// device. Exposed so UI-side write triggers can decline before calling a writer, rather
    /// than relying on each writer's own hold — same answer, but the surface can also stop
    /// telling the player the edit was published.
    var isCurrentIdentityDetached: Bool {
        let store = AgeGateStore.shared
        if let uid = auth.currentUser?.uid, store.isIdentityDetached(uid) { return true }
        guard let user = currentUser else { return false }
        return store.isIdentityDetached(user.firebaseUID ?? user.id)
    }
    
    var wasPreviouslySignedIn: Bool {
        guard let user = currentUser else { return false }
        return user.firebaseUID != nil && !isAuthenticated && !isAnonymousUser
    }

    /// Firebase Auth provider IDs linked to the signed-in account
    /// (e.g. "password", "apple.com", "google.com"). Empty when signed out.
    var linkedAuthProviderIDs: [String] {
        guard let firebaseUser = auth.currentUser else { return [] }
        return firebaseUser.providerData.map { $0.providerID }
    }

    // MARK: - Sign In / Create Account
    
    /// Sign in with email and password
    func signIn(email: String, password: String) async throws {
        isLoading = true
        defer { isLoading = false }
        
        guard isOnline else {
            throw AuthError.offline
        }
        
        do {
            let result = try await auth.signIn(withEmail: email, password: password)
            await loadUserFromFirebase(result.user)
            // updateLoginTracking is called in loadUserFromFirebase
        } catch {
            if let error = error as NSError? {
                switch error.code {
                case 17008, 17009, 17010, 17011:
                    throw AuthError.invalidCredentials
                default:
                    throw AuthError.networkError
                }
            }
            throw AuthError.networkError
        }
    }
    
    /// Create account with email and password (upgrades anonymous if exists).
    /// Real names are never collected (owner decision, F-6 rework): registration takes
    /// username + email + password only.
    func createAccount(
        email: String,
        password: String,
        userName: String
    ) async throws {
        isLoading = true
        defer { isLoading = false }
        
        guard isOnline else {
            throw AuthError.offline
        }
        
        guard modelContext != nil,
              let currentUser = currentUser else {
            throw AuthError.noUser
        }

        let trimmedUserName = UsernameValidation.trimmed(userName)
        if let failure = UsernameValidation.failure(for: trimmedUserName) {
            throw AuthError.usernameValidationFailure(failure)
        }

        // Check username uniqueness (exclude current user)
        let excludingId = currentUser.firebaseUID ?? currentUser.id
        guard try await !isUsernameTaken(trimmedUserName, excludingUserId: excludingId) else {
            throw AuthError.usernameTaken
        }
        
        // The identity every local gameplay row is keyed to right now (`firebaseUID ?? id`,
        // the app's play-identity resolution). Captured BEFORE anything touches Auth so the
        // rebind below has a truthful "from" even on the paths that replace the session.
        let previousPlayIdentity = currentUser.firebaseUID ?? currentUser.id

        do {
            // v2.1 §11.4: a guest becomes a registered user by LINKING, not by registering a
            // second account. The uid is the whole point — it is what keeps this device's
            // trips, XP and achievements owned by the same player and what lets the server
            // accept `createdBy` on the next publish.
            if let firebaseUser = auth.currentUser, firebaseUser.isAnonymous {
                let credential = EmailAuthProvider.credential(withEmail: email, password: password)

                // ONLY the link call is guarded. Everything after a successful link (profile
                // save, declaration, Firestore write) used to sit inside this `do`, so a
                // Firestore failure on an ALREADY-LINKED account fell into the fallback,
                // signed the linked session out and registered a second account behind the
                // user's back — the "it made a new user instead of converting" report.
                var linkedUser: User?
                do {
                    linkedUser = try await firebaseUser.link(with: credential).user
                } catch let linkError as NSError
                    where AnonymousUpgradePolicy.shouldFallBackToFreshAccount(
                        linkErrorCode: linkError.code
                    ) {
                    // The email belongs to another account; a fresh account is the only
                    // thing that could resolve it. Every other failure (network, App Check,
                    // backend) is transient — it rethrows and the anonymous session survives
                    // for the retry instead of being forked.
                    linkedUser = nil
                }

                if let linkedUser {
                    // uid preserved. The rebind is a no-op in the normal case and repairs the
                    // desynced case where the local `AppUser` never took the anonymous uid.
                    await bindLocalIdentityToRegisteredAccount(
                        linkedUser,
                        email: email,
                        userName: trimmedUserName,
                        previousPlayIdentity: previousPlayIdentity
                    )
                } else {
                    // FR-60(d): the stale anonymous session is abandoned client-side (it keeps
                    // no local data — the rebind moves all of it — and server-side it is an
                    // unreferenced anonymous account, swept by the FR-60(c) backstop when it
                    // is a declared child). `createUser` replaces the session itself, so it is
                    // NOT signed out first: a `createUser` failure then leaves the anonymous
                    // session intact rather than stranding the user with no session at all.
                    let result = try await auth.createUser(withEmail: email, password: password)
                    await bindLocalIdentityToRegisteredAccount(
                        result.user,
                        email: email,
                        userName: trimmedUserName,
                        previousPlayIdentity: previousPlayIdentity
                    )
                }
            } else {
                // No anonymous session to upgrade (registration straight from an
                // unprovisioned local guest). The local play history still has to follow the
                // player onto the uid this creates.
                let result = try await auth.createUser(withEmail: email, password: password)
                await bindLocalIdentityToRegisteredAccount(
                    result.user,
                    email: email,
                    userName: trimmedUserName,
                    previousPlayIdentity: previousPlayIdentity
                )
            }
            await updateLoginTracking()
        } catch {
            if let error = error as NSError? {
                switch error.code {
                case 17007:
                    throw AuthError.emailAlreadyInUse
                case 17008:
                    throw AuthError.invalidCredentials
                default:
                    throw AuthError.networkError
                }
            }
            throw AuthError.networkError
        }
    }

    /// Settles the device's local identity onto the uid a registration flow just produced —
    /// whether that uid came from a link (unchanged) or from a fresh account (changed).
    ///
    /// This is the seam Bug 2 came through. Before FR-60 the two could not diverge in any way
    /// that mattered: a guest's local `AppUser.id` was a UUID for milliseconds, so a fresh
    /// registration account "orphaned" nothing. Under the local-first model a player can hold
    /// days of trips, discoveries and XP under the previous identity, and every one of those
    /// rows resolves through `firebaseUID ?? id`. Leaving them behind is invisible locally
    /// (the fetch predicates simply stop matching) and fatal in the cloud:
    /// `ensureOwnerMemberIfCreatorPayload` declines to seed `members/{uid}` when the payload's
    /// `createdBy` is not the caller, and `assertTripOwner` then rejects the publish.
    ///
    /// FR-27 ordering is preserved: the uid is bound SYNCHRONOUSLY before `currentUser`
    /// publishes it, exactly as `signInAnonymously` / `createNewUserFromFirebase` do.
    private func bindLocalIdentityToRegisteredAccount(
        _ firebaseUser: User,
        email: String,
        userName: String,
        previousPlayIdentity: String
    ) async {
        guard let modelContext else { return }
        let newUid = firebaseUser.uid

        // Same ownership claim as `signInAnonymously`: the auth-state listener must not
        // bootstrap this uid in parallel and publish a default profile over the one this
        // flow is about to write.
        uidsBeingProvisionedLocally.insert(newUid)
        defer { uidsBeingProvisionedLocally.remove(newUid) }

        // FR-60(d): carry this device's local play history onto the registered uid FIRST, so
        // it is already correct by the time any view re-reads the play identity.
        if AnonymousUpgradePolicy.requiresLocalPlayIdentityRebind(
            previousPlayIdentity: previousPlayIdentity,
            registeredUid: newUid
        ) {
            rebindLocalPlayIdentity(from: previousPlayIdentity, to: newUid)
        }

        // FR-27 BIND BEFORE PUBLISHING — synchronous, no await, ahead of `currentUser`.
        AgeGateStore.shared.bindPendingDeclaration(toUserId: newUid)

        // `AppUser.id` is `@Attribute(.unique)`, so a row already holding this uid — the
        // auth-state listener can reach `createNewUserFromFirebase` first — is ADOPTED rather
        // than collided with. Otherwise the row that carried the previous play identity is
        // REPOINTED rather than shadowed by a second one, so the ordinary path cannot leave
        // the device with an empty duplicate `AppUser` for a later device-identifier lookup
        // to resolve to instead.
        let existingForNewUid = try? modelContext.fetch(
            FetchDescriptor<AppUser>(
                predicate: #Predicate<AppUser> { $0.id == newUid || $0.firebaseUID == newUid }
            )
        ).first
        let carrier = existingForNewUid
            ?? currentUser.flatMap { ($0.firebaseUID ?? $0.id) == previousPlayIdentity ? $0 : nil }

        guard let user = carrier else {
            // No local row to carry: fall back to the shared provisioning choke point.
            await createNewUserFromFirebase(firebaseUser, email: email, userName: userName)
            return
        }

        if user.id != newUid {
            user.localIDBeforeFirebase = user.id
            user.id = newUid
        }
        user.firebaseUID = newUid
        user.email = email
        user.userName = userName
        user.isUsernameManuallyChanged = true
        user.lastUpdated = .now
        user.needsSync = true
        try? modelContext.save()

        currentUser = user
        isAuthenticated = true

        // F-6 (FR-27): an under-13 answer from THIS flow is declared for the uid the flow
        // settled on, before its first profile write (the choke point holds the write while
        // the declaration is outstanding).
        _ = await ensureFlowChildDeclaration(flowUid: newUid)

        do {
            try await saveUserDataToFirestore(user)
            // COPPA F-7 (FR-19): resolve the child projection from a fresh server read.
            await UserRepository.shared.refreshUsersFromFirestoreIfPresent(userIds: [newUid])
        } catch {
            // The Auth account exists — a Firestore hiccup is a sync problem, not a failed
            // registration, and must never be answered by creating a second account.
            user.needsSync = true
            try? syncCoordinator?.enqueueUserProfileSync(userId: newUid)
            try? modelContext.save()
            #if DEBUG
            print("⚠️ Registered profile write failed for \(newUid); queued for sync: \(error)")
            #endif
        }
    }

    /// Sign out (keeps local user, clears Firebase auth)
    func signOut() async throws {
        guard let modelContext = modelContext else {
            throw AuthError.noModelContext
        }
        
        if isOnline {
            do {
                try auth.signOut()
            } catch {
                print("⚠️ Firebase sign out failed: \(error)")
            }
        }

        if let userId = currentUser?.firebaseUID ?? currentUser?.id {
            UserRepository.shared.clearEntitlementTags(for: userId)
        }
        founderEntitlementAttemptedUserIds.removeAll()

        // F-6 (identity-epoch rule): the answer belongs to the identity that gave it.
        // Clearing on sign-out ends the epoch — the next registration flow asks fresh
        // (incident-2 regression), and any future guest rebirth must pass the age
        // screen before its new uid is provisioned.
        AgeGateStore.shared.clearAnswer()

        // Keep user data, just mark as signed out
        if let user = currentUser {
            user.linkedPlatforms.removeAll()
            user.needsSync = false
            // Keep firebaseUID for future sign-in
            try modelContext.save()
        }
        
        isAuthenticated = false
    }

    /// Profile Sign Out: wipe all local user-associated data, then recreate a device-username guest.
    /// Does not cancel remote multiplayer trips. When online, signs in anonymously afterward.
    func hardSignOutAndResetToGuest() async throws {
        guard modelContext != nil else {
            throw AuthError.noModelContext
        }
        guard let user = currentUser else {
            throw AuthError.noUser
        }

        let oldUserId = user.firebaseUID ?? user.id
        // Release profile bindings before SwiftData rows are deleted; keep settings sheet open.
        NotificationCenter.default.post(name: .accountWillHardSignOut, object: nil)
        currentUser = nil
        isAuthenticated = false
        try await Task.yield()

        // Clear push routing while Auth still matches the signed-out account.
        if user.firebaseUID != nil {
            await FirebaseMessagingService.shared.clearTokenForSignOut(userId: oldUserId)
        }

        try LocalUserDataPurgeService.shared.purgeAllLocalUserData(oldUserId: oldUserId)

        founderEntitlementAttemptedUserIds.removeAll()
        // F-6 (identity-epoch rule, option B): hard sign-out ends the epoch. The
        // replacement guest below stays UNPROVISIONED (`signInAnonymously` self-defers)
        // and is never prompted — it lives as a restricted, age-unknown local guest
        // behind the standard guest gates until a sign-up flow answers or the user
        // signs in to an existing account.
        AgeGateStore.shared.clearAnswer()

        if isOnline {
            do {
                try auth.signOut()
            } catch {
                print("⚠️ Firebase sign out failed during hard sign-out: \(error)")
            }
        }
        GIDSignIn.sharedInstance.signOut()
        await RevenueCatEntitlementBridge.shared.identify(userId: nil)

        try createFreshLocalGuestUser()
        if isOnline {
            try await signInAnonymously()
            await FirebaseMessagingService.shared.refreshAndPersistTokenIfPossible()
        }
        SyncCoordinator.shared.resumeProcessingAfterPurge()
        NotificationCenter.default.post(name: .accountDidHardSignOut, object: nil)
    }

    /// Account deletion: local teardown after `deleteAccount` removed the Auth user and
    /// cloud data. Mirrors `hardSignOutAndResetToGuest()` but never writes to Firestore
    /// as the deleted user (a merge write would resurrect the deleted users/{uid} doc).
    func finalizeDeletedAccountLocally() async throws {
        guard modelContext != nil else {
            throw AuthError.noModelContext
        }
        guard let user = currentUser else {
            throw AuthError.noUser
        }

        let oldUserId = user.firebaseUID ?? user.id
        // Release profile bindings before SwiftData rows are deleted; keep settings sheet open.
        NotificationCenter.default.post(name: .accountWillHardSignOut, object: nil)
        currentUser = nil
        isAuthenticated = false
        try await Task.yield()

        // Server already deleted users/{uid} (incl. fcmToken); drop only the device token.
        await FirebaseMessagingService.shared.deleteDeviceTokenAfterAccountDeletion()

        try LocalUserDataPurgeService.shared.purgeAllLocalUserData(oldUserId: oldUserId)

        founderEntitlementAttemptedUserIds.removeAll()
        // F-6 (identity-epoch rule, option B): account deletion ends the epoch; the
        // replacement guest stays unprovisioned and unprompted (standard guest gates)
        // until a sign-up flow answers or the user signs in.
        AgeGateStore.shared.clearAnswer()

        // The Auth session is invalid server-side; always clear the local Keychain session.
        do {
            try auth.signOut()
        } catch {
            print("⚠️ Firebase sign out failed after account deletion: \(error)")
        }
        GIDSignIn.sharedInstance.signOut()
        await RevenueCatEntitlementBridge.shared.identify(userId: nil)
        Analytics.resetAnalyticsData()

        try createFreshLocalGuestUser()
        if isOnline {
            try await signInAnonymously()
            await FirebaseMessagingService.shared.refreshAndPersistTokenIfPossible()
        }
        SyncCoordinator.shared.resumeProcessingAfterPurge()
        NotificationCenter.default.post(name: .accountDidHardSignOut, object: nil)
    }

    /// Resets the current local user to default guest values. Call when switching to a fresh guest experience.
    /// Single place to clear local user profile data for reuse elsewhere (e.g., sign out and switch account).
    func resetLocalUserToGuest() throws {
        guard let user = currentUser, let modelContext = modelContext else { return }
        
        let deviceId = DeviceIdentifier.getDeviceIdentifier()
        let newUsername = DeviceIdentifier.generateDefaultUsername(deviceId: deviceId)
        user.userName = newUsername
        user.firstName = nil
        user.lastName = nil
        user.email = nil
        user.phoneNumber = nil
        user.firebaseUID = nil
        user.userImageURL = nil
        user.isUsernameManuallyChanged = false
        user.linkedPlatforms = []
        user.lastDateLoggedIn = nil
        user.lastLoginLocation = []
        user.activeFamilyId = nil
        user.lastUpdated = .now
        
        try modelContext.save()
    }
    
    /// Sign out and create a fresh anonymous account. Use when user chooses "Continue as Guest" over a restored account.
    /// No-ops when the current session is already guest-like so trips/XP keyed by UID are not orphaned.
    func signOutAndCreateAnonymous() async throws {
        let accountState = FirebaseAccountStateProvider.shared.currentAccountState(for: currentUser)
        guard GuestContinuationPolicy.shouldCreateFreshAnonymousSession(accountState: accountState) else {
            return
        }
        try await signOut()
        try resetLocalUserToGuest()
        try await signInAnonymously()
    }
    
    // MARK: - OAuth Sign In
    
    /// Sign in with Google
    func signInWithGoogle(presentingViewController: UIViewController) async throws {
        guard isOnline else {
            throw AuthError.offline
        }
        
        guard let modelContext = modelContext else {
            throw AuthError.noModelContext
        }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            guard let clientID = FirebaseApp.app()?.options.clientID else {
                throw AuthError.notImplemented
            }
            
            let config = GIDConfiguration(clientID: clientID)
            GIDSignIn.sharedInstance.configuration = config
            
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController)
            let googleUser = result.user
            guard let idToken = googleUser.idToken?.tokenString else {
                throw AuthError.networkError
            }
            
            let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: googleUser.accessToken.tokenString)
            
          // Check if anonymous, link if so
                     if let firebaseUser = auth.currentUser, firebaseUser.isAnonymous {
                         let result = try await firebaseUser.link(with: credential)
                         await updateUserFromOAuth(result.user, email: googleUser.profile?.email, displayName: googleUser.profile?.name)
                         // Update login tracking
                         await updateLoginTracking()
                     } else {
                let authResult = try await auth.signIn(with: credential)
                await loadUserFromFirebase(authResult.user)
                // updateLoginTracking is called in loadUserFromFirebase
            }
        } catch {
            if let error = error as NSError? {
                switch error.code {
                case 17020:
                    throw AuthError.emailAlreadyInUse
                default:
                    throw AuthError.networkError
                }
            }
            throw AuthError.networkError
        }
    }
    
    /// Sign in with Apple
    func signInWithApple() async throws {
        guard isOnline else {
            throw AuthError.offline
        }
        
        guard let modelContext = modelContext else {
            throw AuthError.noModelContext
        }
        
        isLoading = true
        defer { isLoading = false }
        
        let appleIDProvider = ASAuthorizationAppleIDProvider()
        let request = appleIDProvider.createRequest()
        request.requestedScopes = [.fullName, .email]
        let nonce = Self.randomNonceString()
        request.nonce = Self.sha256(nonce)
        
        let authorizationController = ASAuthorizationController(authorizationRequests: [request])
        
        do {
            let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ASAuthorization, Error>) in
                authorizationController.delegate = AppleSignInDelegate(continuation: continuation)
                authorizationController.presentationContextProvider = AppleSignInPresentationContextProvider()
                authorizationController.performRequests()
            }
            
            guard let appleIDCredential = result.credential as? ASAuthorizationAppleIDCredential,
                  let identityToken = appleIDCredential.identityToken,
                  let idTokenString = String(data: identityToken, encoding: .utf8) else {
                throw AuthError.networkError
            }
            
            let credential = OAuthProvider.appleCredential(withIDToken: idTokenString, rawNonce: nonce, fullName: appleIDCredential.fullName)
            
            let email = appleIDCredential.email
            let displayName = appleIDCredential.fullName.map { name in
                let given = name.givenName ?? ""
                let family = name.familyName ?? ""
                return "\(given) \(family)".trimmingCharacters(in: .whitespaces)
            }
            let finalDisplayName = displayName?.isEmpty == false ? displayName : nil
            
          // Check if anonymous, link if so
                     if let firebaseUser = auth.currentUser, firebaseUser.isAnonymous {
                         let result = try await firebaseUser.link(with: credential)
                         await updateUserFromOAuth(result.user, email: email, displayName: finalDisplayName)
                         // Update login tracking
                         await updateLoginTracking()
                     } else {
                let authResult = try await auth.signIn(with: credential)
                await loadUserFromFirebase(authResult.user)
                // updateLoginTracking is called in loadUserFromFirebase
            }
        } catch {
            if let error = error as NSError? {
                switch error.code {
                case 17020:
                    throw AuthError.emailAlreadyInUse
                default:
                    throw AuthError.networkError
                }
            }
            throw AuthError.networkError
        }
    }
    
    // MARK: - Re-authentication (account deletion)

    // Firebase requires a recent sign-in for destructive account operations. These
    // refresh the token's auth_time by re-authenticating the signed-in user with a
    // credential from one of their linked providers, then the caller retries.

    /// Re-authenticate with the account's email and password.
    func reauthenticate(email: String, password: String) async throws {
        guard isOnline else {
            throw AuthError.offline
        }
        guard let firebaseUser = auth.currentUser, isTrulyAuthenticated else {
            throw AuthError.noUser
        }

        isLoading = true
        defer { isLoading = false }

        let credential = EmailAuthProvider.credential(withEmail: email, password: password)
        do {
            _ = try await firebaseUser.reauthenticate(with: credential)
        } catch {
            throw Self.mapReauthenticationError(error)
        }
    }

    /// Re-authenticate with Sign in with Apple.
    func reauthenticateWithApple() async throws {
        guard isOnline else {
            throw AuthError.offline
        }
        guard let firebaseUser = auth.currentUser, isTrulyAuthenticated else {
            throw AuthError.noUser
        }

        isLoading = true
        defer { isLoading = false }

        let appleIDProvider = ASAuthorizationAppleIDProvider()
        let request = appleIDProvider.createRequest()
        request.requestedScopes = [.fullName, .email]
        let nonce = Self.randomNonceString()
        request.nonce = Self.sha256(nonce)

        let authorizationController = ASAuthorizationController(authorizationRequests: [request])

        let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ASAuthorization, Error>) in
            authorizationController.delegate = AppleSignInDelegate(continuation: continuation)
            authorizationController.presentationContextProvider = AppleSignInPresentationContextProvider()
            authorizationController.performRequests()
        }

        guard let appleIDCredential = result.credential as? ASAuthorizationAppleIDCredential,
              let identityToken = appleIDCredential.identityToken,
              let idTokenString = String(data: identityToken, encoding: .utf8) else {
            throw AuthError.networkError
        }

        let credential = OAuthProvider.appleCredential(withIDToken: idTokenString, rawNonce: nonce, fullName: appleIDCredential.fullName)
        do {
            _ = try await firebaseUser.reauthenticate(with: credential)
        } catch {
            throw Self.mapReauthenticationError(error)
        }
    }

    /// Re-authenticate with Google.
    func reauthenticateWithGoogle(presentingViewController: UIViewController) async throws {
        guard isOnline else {
            throw AuthError.offline
        }
        guard let firebaseUser = auth.currentUser, isTrulyAuthenticated else {
            throw AuthError.noUser
        }

        isLoading = true
        defer { isLoading = false }

        guard let clientID = FirebaseApp.app()?.options.clientID else {
            throw AuthError.notImplemented
        }

        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config

        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController)
        let googleUser = result.user
        guard let idToken = googleUser.idToken?.tokenString else {
            throw AuthError.networkError
        }

        let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: googleUser.accessToken.tokenString)
        do {
            _ = try await firebaseUser.reauthenticate(with: credential)
        } catch {
            throw Self.mapReauthenticationError(error)
        }
    }

    private static func mapReauthenticationError(_ error: Error) -> Error {
        let nsError = error as NSError
        switch nsError.code {
        case 17004, 17008, 17009: // invalidCredential, invalidEmail, wrongPassword
            return AuthError.invalidCredentials
        case 17024: // userMismatch — re-authenticated with a different account
            return AuthError.reauthAccountMismatch
        default:
            return AuthError.networkError
        }
    }

    // MARK: - Platform Linking (for existing authenticated users)

    func linkGoogleAccount(presentingViewController: UIViewController) async throws {
        guard !isLinking else {
            throw AuthError.networkError // Already linking
        }
        
        guard let user = currentUser, isTrulyAuthenticated else {
            throw AuthError.noUser
        }
        
        guard isOnline else {
            throw AuthError.offline
        }
        
        isLinking = true
        isLoading = true
        defer { 
            isLinking = false
            isLoading = false 
        }
        
        print("🔗 Attempting to link Google account...")
        
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            throw AuthError.notImplemented
        }
        
        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config
        
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController)
            let googleUser = result.user
            guard let idToken = googleUser.idToken?.tokenString else {
                throw AuthError.networkError
            }
            
            let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: googleUser.accessToken.tokenString)
            print("🔗 Google credential received, provider: \(credential.provider)")
            
            try await linkPlatformCredential(credential, platform: .google, email: googleUser.profile?.email, displayName: googleUser.profile?.name)
        } catch {
            print("❌ Google linking failed: \(error.localizedDescription)")
            throw error
        }
    }
    
    func linkAppleAccount() async throws {
        guard !isLinking else {
            throw AuthError.networkError // Already linking
        }
        
        guard let user = currentUser, isTrulyAuthenticated else {
            throw AuthError.noUser
        }
        
        guard isOnline else {
            throw AuthError.offline
        }
        
        isLinking = true
        isLoading = true
        defer { 
            isLinking = false
            isLoading = false 
        }
        
        print("🔗 Attempting to link Apple account...")
        
        let appleIDProvider = ASAuthorizationAppleIDProvider()
        let request = appleIDProvider.createRequest()
        request.requestedScopes = [.fullName, .email]
        let nonce = Self.randomNonceString()
        request.nonce = Self.sha256(nonce)
        
        let authorizationController = ASAuthorizationController(authorizationRequests: [request])
        
        // Store delegate and controller to prevent deallocation
        var storedDelegate: AppleSignInDelegate?
        
        do {
            let result = try await withTaskCancellationHandler(operation: {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ASAuthorization, Error>) in
                    let signInDelegate = AppleSignInDelegate(continuation: continuation)
                    storedDelegate = signInDelegate
                    authorizationController.delegate = signInDelegate
                    authorizationController.presentationContextProvider = AppleSignInPresentationContextProvider()
                    authorizationController.performRequests()
                }
            }, onCancel: {
                // If cancelled, ensure continuation resumes
                if let delegate = storedDelegate, !delegate.hasResumed {
                    print("⚠️ Apple Sign-In was cancelled, resuming continuation with error")
                    // The delegate will handle the cancellation error
                }
            })
            
            guard let appleIDCredential = result.credential as? ASAuthorizationAppleIDCredential,
                  let identityToken = appleIDCredential.identityToken,
                  let idTokenString = String(data: identityToken, encoding: .utf8) else {
                throw AuthError.networkError
            }
            
            let credential = OAuthProvider.appleCredential(withIDToken: idTokenString, rawNonce: nonce, fullName: appleIDCredential.fullName)
            print("🔗 Apple credential received, provider: \(credential.provider)")
            
            let email = appleIDCredential.email
            let displayName = appleIDCredential.fullName.map { name in
                let given = name.givenName ?? ""
                let family = name.familyName ?? ""
                return "\(given) \(family)".trimmingCharacters(in: .whitespaces)
            }
            let finalDisplayName = displayName?.isEmpty == false ? displayName : nil
            
            try await linkPlatformCredential(credential, platform: .apple, email: email, displayName: finalDisplayName)
        } catch {
            print("❌ Apple linking failed: \(error.localizedDescription)")
            // Ensure delegate is cleaned up
            storedDelegate = nil
            throw error
        }
    }
    
    func linkMicrosoftAccount(presentingViewController: UIViewController) async throws {
        guard !isLinking else {
            throw AuthError.networkError // Already linking
        }
        
        guard currentUser != nil, isTrulyAuthenticated else {
            throw AuthError.noUser
        }
        
        guard isOnline else {
            throw AuthError.offline
        }
        
        isLinking = true
        isLoading = true
        defer { 
            isLinking = false
            isLoading = false 
        }
        
        print("🔗 Attempting to link Microsoft account...")
        
        // Create a dedicated view controller that conforms to AuthUIDelegate
        let authViewController = AuthUIDelegateViewController()
        
        // Present it first so OAuth can use it
        await MainActor.run {
            presentingViewController.present(authViewController, animated: true)
        }
        
        let provider = OAuthProvider(providerID: "microsoft.com")
        provider.scopes = ["openid", "email", "profile"]
        
        do {
            // Get credential - this will present the Microsoft OAuth flow
            print("🔗 Getting Microsoft credential with provider ID: microsoft.com")
            let credential = try await provider.credential(with: authViewController)
            print("🔗 Microsoft credential received, provider: \(credential.provider)")
            
            // Dismiss the view controller
            await MainActor.run {
                authViewController.dismiss(animated: true)
            }
            
            try await linkPlatformCredential(credential, platform: .microsoft, email: nil, displayName: nil)
        } catch {
            print("❌ Microsoft linking failed: \(error.localizedDescription)")
            await MainActor.run {
                authViewController.dismiss(animated: true)
            }
            throw error
        }
    }
    
    func linkYahooAccount(presentingViewController: UIViewController) async throws {
        guard !isLinking else {
            throw AuthError.networkError // Already linking
        }
        
        guard currentUser != nil, isTrulyAuthenticated else {
            throw AuthError.noUser
        }
        
        guard isOnline else {
            throw AuthError.offline
        }
        
        isLinking = true
        isLoading = true
        defer { 
            isLinking = false
            isLoading = false 
        }
        
        print("🔗 Attempting to link Yahoo account...")
        
        // Create a dedicated view controller that conforms to AuthUIDelegate
        let authViewController = AuthUIDelegateViewController()
        
        // Present it first so OAuth can use it
        await MainActor.run {
            presentingViewController.present(authViewController, animated: true)
        }
        
        let provider = OAuthProvider(providerID: "yahoo.com")
        provider.scopes = ["openid", "email", "profile"]
        
        do {
            // Get credential - this will present the Yahoo OAuth flow
            print("🔗 Getting Yahoo credential with provider ID: yahoo.com")
            let credential = try await provider.credential(with: authViewController)
            print("🔗 Yahoo credential received, provider: \(credential.provider)")
            
            // Dismiss the view controller
            await MainActor.run {
                authViewController.dismiss(animated: true)
            }
            
            try await linkPlatformCredential(credential, platform: .yahoo, email: nil, displayName: nil)
        } catch {
            print("❌ Yahoo linking failed: \(error.localizedDescription)")
            await MainActor.run {
                authViewController.dismiss(animated: true)
            }
            throw error
        }
    }
    
    
    // MARK: - Helper method for Google Sign-In (finds UIViewController automatically)
    func linkGoogleAccount() async throws {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            throw AuthError.notImplemented
        }
        
        try await linkGoogleAccount(presentingViewController: rootViewController)
    }
    
    // MARK: - Unlink Platform
    func unlinkPlatform(_ platform: LinkedPlatform.PlatformType) async throws {
        guard let firebaseUser = auth.currentUser, isTrulyAuthenticated else {
            throw AuthError.noUser
        }
        
        guard let user = currentUser, let modelContext = modelContext else {
            throw AuthError.noUser
        }
        
        guard isOnline else {
            throw AuthError.offline
        }
        
        isLoading = true
        defer { isLoading = false }
        
        // Map platform type to provider ID
        let providerID: String
        switch platform {
        case .google:
            providerID = "google.com"
        case .apple:
            providerID = "apple.com"
        case .microsoft:
            providerID = "microsoft.com"
        case .yahoo:
            providerID = "yahoo.com"
        case .facebook:
            providerID = "facebook.com"
        case .twitter:
            providerID = "twitter.com"
        case .instagram:
            providerID = "instagram.com"
        }
        
        // Prevent unlinking if it's the only provider (user needs at least one way to sign in)
        if firebaseUser.providerData.count <= 1 {
            throw AuthError.cannotUnlinkLastProvider
        }
        
        do {
            try await firebaseUser.unlink(fromProvider: providerID)
            
            // Remove from local user's linked platforms
            user.linkedPlatforms.removeAll { $0.platform == platform }
            user.needsSync = true
            
            try modelContext.save()
            
            // Sync to Firestore
            if isOnline {
                try? await saveUserDataToFirestore(user)
            }
        } catch {
            throw AuthError.networkError
        }
    }
    
  private func linkPlatformCredential(_ credential: AuthCredential, platform: LinkedPlatform.PlatformType, email: String?, displayName: String?) async throws {
         guard let firebaseUser = auth.currentUser, isTrulyAuthenticated else {
             throw AuthError.noUser
         }
         
         guard let user = currentUser, let modelContext = modelContext else {
             throw AuthError.noUser
         }
         
         print("🔗 Linking platform: \(platform.rawValue), credential provider: \(credential.provider)")
         
         // Map platform to expected provider ID
         let expectedProviderID: String
         switch platform {
         case .google:
             expectedProviderID = "google.com"
         case .apple:
             expectedProviderID = "apple.com"
         case .microsoft:
             expectedProviderID = "microsoft.com"
         case .yahoo:
             expectedProviderID = "yahoo.com"
         case .facebook:
             expectedProviderID = "facebook.com"
         case .twitter:
             expectedProviderID = "twitter.com"
         case .instagram:
             expectedProviderID = "instagram.com"
         }
         
         // Verify credential provider matches expected platform
         guard credential.provider == expectedProviderID else {
             print("❌ Provider mismatch: Expected \(expectedProviderID) for platform \(platform.rawValue), but got \(credential.provider)")
             throw AuthError.networkError
         }
         
         print("✅ Provider verified: \(credential.provider) matches \(platform.rawValue)")
         
         do {
             let result = try await firebaseUser.link(with: credential)
             let linkedUser = result.user
             
             var platformEmail = email
             var platformPhone: String? = nil
             // Provider display names are discarded — real names are never stored
             // locally or in Firestore (owner decision, F-6 rework).
             _ = displayName

             // Extract provider data - look for the provider we just linked
             for providerData in linkedUser.providerData {
                 if providerData.providerID == expectedProviderID {
                     platformEmail = platformEmail ?? providerData.email
                     platformPhone = providerData.phoneNumber
                     break
                 }
             }
             
             // Check username conflict (only if username wasn't manually changed)
             if !user.isUsernameManuallyChanged {
                 let excludingId = user.firebaseUID ?? user.id
                 if try await isUsernameTaken(user.userName, excludingUserId: excludingId) {
                     await showUsernameConflictDialogForLinking(platform: platform)
                     try? await firebaseUser.unlink(fromProvider: expectedProviderID)
                     return
                 }
             }
             
             // Contact stays local + private/contact; only platform/platformUserId are
             // serialized to the peer-readable users/{uid} doc (LinkedPlatformFirestore).
             let platformInfo = LinkedPlatform(
                 platform: platform,
                 platformUserId: linkedUser.uid,
                 linkedAt: .now,
                 email: platformEmail,
                 phoneNumber: platformPhone,
                 displayName: nil
             )
             
             if !user.linkedPlatforms.contains(where: { $0.platform == platform }) {
                 user.linkedPlatforms.append(platformInfo)
             }
             
             if let email = platformEmail, user.email == nil {
                 user.email = email
             }
             if let phone = platformPhone, user.phoneNumber == nil {
                 user.phoneNumber = phone
             }
             
             try modelContext.save()
             try await saveUserDataToFirestore(user)
         } catch {
             throw AuthError.networkError
         }
     }
     
     /// Show username conflict dialog during linking
     private func showUsernameConflictDialogForLinking(platform: LinkedPlatform.PlatformType) async {
         guard let user = currentUser else { return }
         
         conflictDialogMessage = "Your username '\(user.userName)' is already taken. Please choose a new username to link your \(platform.rawValue) account."
         conflictDialogNewUsername = ""
         showUsernameConflictDialog = true
         
         await withCheckedContinuation { continuation in
             usernameConflictResolver = { newUsername in
                 continuation.resume()
                 self.usernameConflictResolver = nil
                 
                 if let username = newUsername {
                     Task { @MainActor in
                         do {
                             try await self.updateUserName(username)
                             // Retry linking after username update
                             // Note: This would need to be handled by the caller
                         } catch {
                             self.errorMessage = error.localizedDescription
                         }
                     }
                 } else {
                     Task { @MainActor in
                         self.errorMessage = "Account linking cancelled."
                     }
                 }
             }
         }
     }
    // MARK: - User Management
    
    func updateUserName(_ newName: String) async throws {
        guard let user = currentUser else {
            throw AuthError.noUser
        }
        
        let trimmedName = UsernameValidation.trimmed(newName)
        if let failure = UsernameValidation.failure(for: trimmedName) {
            throw AuthError.usernameValidationFailure(failure)
        }
        
        guard trimmedName != user.userName else {
            return
        }
        
        let excludingId = user.firebaseUID ?? user.id
        guard try await !isUsernameTaken(trimmedName, excludingUserId: excludingId) else {
            throw AuthError.usernameTaken
        }
        
        user.updateUserName(trimmedName, isManual: true)
        user.needsSync = true
        
        if let modelContext = modelContext {
            try modelContext.save()
        }
        
        if isOnline {
            Task {
                try? await saveUserDataToFirestore(user)
            }
        }
    }
  
  /// Resolve username conflict
     func resolveUsernameConflict(newUsername: String?) {
         usernameConflictResolver?(newUsername)
     }
    
    /// Update login tracking (login timestamps only — never location).
    private func updateLoginTracking() async {
        guard let user = currentUser,
              let modelContext = modelContext else {
            return
        }
        
        // Debounce: Only track if it's been more than 5 seconds since last tracking
        if let lastTracking = lastLoginTrackingTime,
           Date().timeIntervalSince(lastTracking) < 5.0 {
            // Too soon since last tracking, skip
            return
        }
        
        // Update last tracking time
        lastLoginTrackingTime = .now
        
        // Always update last login date
        let loginDate = Date()
        user.lastDateLoggedIn = loginDate
        user.lastUpdated = loginDate
        
        // Login never captures location (COPPA: silent login-location flow removed).
        // The stored property survives only because the SwiftData schema is frozen; scrub
        // any coordinates a pre-removal build persisted locally.
        if !user.lastLoginLocation.isEmpty {
            user.lastLoginLocation = []
        }

        try? modelContext.save()

        // Login tracking must not full-profile sync (avoids overwriting username/contact
        // with stale local SwiftData before Firestore hydrate).
        // F-6 (FR-27): the merge write could create a skeleton users/{uid} doc for a
        // flow-created uid awaiting its declaration, so it honors the same hold
        // (best-effort; next login re-stamps). No other account is ever held.
        // FR-60(c): a detached uid is held here too. This exact write — `lastDateLoggedIn` +
        // `lastUpdated`, `setData(merge: true)` — is what resurrected a deleted child's
        // document on the next relaunch.
        let ageGateAllowsWrite = !AgeGateProfileWritePolicy.isProfileWriteHeld(
            userUid: user.firebaseUID,
            pendingDeclarationUserIds: AgeGateStore.shared.pendingDeclarationUserIds,
            detachedIdentityUserIds: AgeGateStore.shared.detachedIdentityUserIds
        )
        if isOnline, ageGateAllowsWrite, let firebaseUID = user.firebaseUID {
            Task {
                do {
                    try await updateLoginTimestampsInFirestore(userId: firebaseUID, loginDate: loginDate)
                } catch {
                    #if DEBUG
                    print("⚠️ Failed to update login timestamps: \(error)")
                    #endif
                }
            }
        }
    }

    /// Patches only login timestamps — never identity or private contact.
    private func updateLoginTimestampsInFirestore(userId: String, loginDate: Date) async throws {
        let data: [String: Any] = [
            "lastDateLoggedIn": Timestamp(date: loginDate),
            "lastUpdated": Timestamp(date: loginDate),
        ]
        assert(
            Set(data.keys) == AuthProfileSyncPolicy.loginTimestampFieldKeys,
            "Login tracking must only write AuthProfileSyncPolicy.loginTimestampFieldKeys"
        )
        try await db.collection("users").document(userId).setData(data, merge: true)
    }
    
    // MARK: - Helper Methods
    
    private func handleAuthStateChange(_ user: User?) async {
        if let firebaseUser = user {
            lastObservedAnonymousUid = firebaseUser.isAnonymous ? firebaseUser.uid : nil
            await loadUserFromFirebase(firebaseUser)
        } else {
            // Firebase signed out
            isAuthenticated = false
            await releaseVanishedAnonymousIdentityIfNeeded()
        }
        // COPPA F-7 (FR-23 trigger 1 of 2): every identity transition re-applies the
        // child session postures (ads config, analytics, location, paywall) AFTER the
        // fresh `users/{uid}` read above resolved the projection. The second trigger
        // is the coordinator's own `.userProfilesMerged` observer.
        ChildSessionPostureCoordinator.shared.applyPostures(trigger: .identityTransition)
    }
    
    /// FR-60(c) zombie guard. The uid of the last ANONYMOUS session this service observed.
    ///
    /// When Firebase's own token refresh discovers the Auth user is gone it force-signs-out,
    /// and the listener fires with `nil` — the only notice the client ever gets. An anonymous
    /// uid has no credentials, so a session lost that way is unrecoverable by construction:
    /// keeping it on `AppUser.firebaseUID` only blocks re-provisioning forever, because both
    /// `signInAnonymously` and `ChildConsentRedemptionPolicy.requiresProvisioning`
    /// short-circuit on a non-nil uid.
    private var lastObservedAnonymousUid: String?

    /// Uids a provisioning flow in THIS service is currently attaching to the local player.
    ///
    /// Firebase fires the auth-state listener the moment a uid exists — before the flow has
    /// had a chance to write it onto the local `AppUser`. The listener's bootstrap then sees
    /// "brand-new uid, no local row, no cloud doc" and does the one thing that is right for a
    /// genuine new account and catastrophic here: it builds a SECOND `AppUser` with a
    /// device-default username and no avatar, publishes it as `currentUser`, and saves it to
    /// Firestore over the profile the flow was about to write.
    ///
    /// The flow owns the uid until it says otherwise: it does its own bind, profile write and
    /// fresh read, so the bootstrap has nothing to add and every reason to stay out.
    private var uidsBeingProvisionedLocally: Set<String> = []

    /// Uids whose local detach is mid-flight — see `detachAnonymousIdentityLocally`.
    private var detachesInFlightUids: Set<String> = []

    /// Returns the device to an unprovisioned local-first session after an anonymous Auth
    /// session vanished underneath it. Deliberate sign-outs cannot reach the body: they
    /// either clear `currentUser` first (`hardSignOutAndResetToGuest`,
    /// `finalizeDeletedAccountLocally`) or apply only to registered accounts (`signOut`).
    private func releaseVanishedAnonymousIdentityIfNeeded() async {
        guard let uid = lastObservedAnonymousUid else { return }
        lastObservedAnonymousUid = nil
        guard auth.currentUser == nil,
              let user = currentUser,
              user.firebaseUID == uid else { return }

        // Device pass 2026-08-16 (bug 1): ONE teardown for both zombie paths. This used to
        // retire the uid and stop there, leaving `activeFamilyId`, `email`, `linkedPlatforms`
        // and the pending-approval flag pointing at an account that no longer exists — a
        // session that is uid-less by one measure and still in a family by another. Every
        // surface that mixes those two reads renders a hybrid. `detachAnonymousIdentityLocally`
        // is the settle; the redundant `signOut()` inside it is a no-op here (Firebase already
        // signed this session out, which is why the listener fired at all).
        await detachAnonymousIdentityLocally(uid: uid, reason: "vanished_anonymous_session")
    }

    private func loadUserFromFirebase(_ firebaseUser: User) async {
        guard let modelContext = modelContext else { return }

        let firebaseUID = firebaseUser.uid

        // Owner device pass 2026-08-15: the redemption-provisioned child lost their chosen
        // avatar and username. This is the race that ate them. `signInAnonymously` mints the
        // uid, and Firebase fires the auth-state listener for it BEFORE the flow has written
        // that uid onto the local `AppUser` — so this bootstrap finds no local row for a
        // brand-new uid, resolves `.createLocalThenTrackLogin`, and builds a SECOND `AppUser`
        // with a device-default username and no avatar, publishes it as `currentUser`, and
        // saves THAT to Firestore. The flow's own profile write then has nothing left to
        // carry. Under FR-60 the stakes changed: the local player now holds a real, chosen
        // profile for days before the uid exists.
        guard !uidsBeingProvisionedLocally.contains(firebaseUID) else { return }

        // FR-60(c) one-way ratchet (device pass 2026-08-16, bug 1). A uid this device retired
        // is never adopted again, whatever the server currently shows. The check below only
        // detaches on a CONFIRMED-ABSENT document, and a resurrection write puts a document
        // back — so without this the ratchet could be un-ratcheted by the very write it exists
        // to prevent, and the session would settle back onto the dead identity for good.
        if AgeGateStore.shared.isIdentityDetached(firebaseUID) {
            await detachAnonymousIdentityLocally(uid: firebaseUID, reason: "already_detached_identity")
            return
        }

        // Check if user exists locally
        let descriptor = FetchDescriptor<AppUser>(
            predicate: #Predicate<AppUser> { $0.firebaseUID == firebaseUID || $0.id == firebaseUID }
        )

        var existingUser = try? modelContext.fetch(descriptor).first

        let loadStatus: AuthProfileSyncPolicy.DocumentLoadStatus
        var loadedCloudUser: AppUser?
        do {
            if let firestoreUser = try await loadUserDataFromFirestore(userId: firebaseUID) {
                loadStatus = .found
                loadedCloudUser = firestoreUser
            } else {
                loadStatus = .notFound
            }
        } catch {
            loadStatus = .failed
            #if DEBUG
            print("⚠️ Failed to load user \(firebaseUID) from Firestore: \(error)")
            #endif
        }
        
        // FR-60(c) zombie guard, ahead of every branch below. A uid this device DECLARED has
        // a `users/{uid}` by construction — the declaration is a server write — so a
        // CONFIRMED absence can only mean the account was deleted (captain decline, or
        // remove-and-delete). Left alone, `.keepLocalThenTrackLogin` runs
        // `updateLoginTracking()` on the way out and RESURRECTS the document as a flagless
        // `{lastDateLoggedIn, lastUpdated}` create — a deleted child reappearing server-side,
        // reading back as an adult because rules forbid `isChildAccount` on create.
        //
        // Only ABSENCE acts. A present-but-flagless document is deliberately not treated as
        // deletion: that is also what a manager CORRECTION leaves behind, and detaching an
        // anonymous session is irreversible.
        if DetachedIdentityDetectionPolicy.requiresDetach(
            isAnonymousSession: firebaseUser.isAnonymous,
            documentStatus: Self.selfDocumentStatus(for: loadStatus),
            wasDeclaredByThisDevice: AgeGateStore.shared.isDeclaredChildUserId(firebaseUID)
        ) {
            await detachAnonymousIdentityLocally(uid: firebaseUID, reason: "server_deleted_identity_restore")
            return
        }

        // Re-sample after the network wait. The first read happened BEFORE the Firestore
        // await, and a provisioning flow can attach this uid to the local player during it —
        // acting on the stale sample is what creates the duplicate, default-profile `AppUser`.
        existingUser = (try? modelContext.fetch(descriptor).first) ?? existingUser

        let action = AuthProfileSyncPolicy.bootstrapAction(
            hasLocalUser: existingUser != nil,
            load: loadStatus
        )

        switch action {
        case .applyCloudThenTrackLogin:
            guard let existingUser, let cloud = loadedCloudUser else { return }
            if existingUser.id != firebaseUID {
                existingUser.id = firebaseUID
            }
            existingUser.firebaseUID = firebaseUID
            AuthProfileSyncPolicy.applyCloudProfile(
                cloud,
                to: existingUser,
                isAnonymous: firebaseUser.isAnonymous
            )
            try? modelContext.save()
            currentUser = existingUser
            isAuthenticated = true
            await updateLoginTracking()
            
        case .keepLocalThenTrackLogin:
            guard let existingUser else { return }
            if existingUser.id != firebaseUID {
                existingUser.id = firebaseUID
            }
            existingUser.firebaseUID = firebaseUID
            try? modelContext.save()
            currentUser = existingUser
            isAuthenticated = true
            if loadStatus == .failed {
                AnalyticsService.shared.log(.authProfileHydrateFailed(outcome: "keep_local"))
            }
            await updateLoginTracking()
            
        case .insertCloudThenTrackLogin:
            guard let cloud = loadedCloudUser else { return }
            if firebaseUser.isAnonymous {
                cloud.email = nil
            }
            modelContext.insert(cloud)
            try? modelContext.save()
            currentUser = cloud
            isAuthenticated = true
            await updateLoginTracking()
            
        case .createLocalThenTrackLogin:
            let email = firebaseUser.isAnonymous ? nil : firebaseUser.email
            await createNewUserFromFirebase(firebaseUser, email: email, userName: nil)
            await updateLoginTracking()

        case .abortWithoutCreate:
            AnalyticsService.shared.log(.authProfileHydrateFailed(outcome: "abort_no_create"))
            // Do not invent a guest username or full-save over a possibly existing cloud doc.
        }
    }

    /// Real names are never collected (owner decision, F-6 rework).
    ///
    /// F-6 (FR-27): this is the ONE choke point that provisions a brand-new
    /// `users/{uid}` — reached both from the explicit registration call and from the
    /// auth-state-listener bootstrap (`AuthProfileSyncPolicy.createLocalThenTrackLogin`,
    /// which only fires when the cloud doc is CONFIRMED ABSENT, i.e. never for a
    /// pre-existing account). It binds and delivers the under-13 declaration itself, so
    /// the declare-before-write ordering no longer depends on which task gets here first.
    private func createNewUserFromFirebase(_ firebaseUser: User, email: String?, userName: String?) async {
        guard let modelContext = modelContext else { return }

        let firebaseUID = firebaseUser.uid
        let deviceId = DeviceIdentifier.getDeviceIdentifier()

        // FR-60(b) promotion: when this uid is being minted for the device's own
        // UNPROVISIONED local player, the profile they already chose comes with them.
        // Defence in depth behind `uidsBeingProvisionedLocally` — that guard keeps this path
        // out of the provisioning race entirely, but if anything else ever reaches here for a
        // local-first player, defaults must not be what gets published to their new family.
        let localPlayer = LocalPlayerPromotionPolicy.carriesLocalProfile(
            isAnonymousSession: firebaseUser.isAnonymous,
            localPlayerHasFirebaseUid: currentUser?.firebaseUID != nil
        ) ? currentUser : nil

        let defaultUsername = userName
            ?? localPlayer?.userName
            ?? DeviceIdentifier.generateDefaultUsername(deviceId: deviceId)
        let carriedAvatarId = localPlayer?.avatarId
        let carriedManualUsername = userName != nil
            || (localPlayer?.isUsernameManuallyChanged ?? false)
        let previousPlayIdentity = localPlayer.map { $0.firebaseUID ?? $0.id }

        // F-6 (FR-27) — BIND BEFORE PUBLISHING. Synchronous, no await, and ahead of
        // `currentUser` below: the moment this uid becomes observable, SwiftUI can run
        // `handleHomeOnAppear` → `AppPrefsStore.load` → `updateGameDefaults`, and every
        // `users/{uid}` writer decides whether it is held by consulting
        // `pendingDeclarationUserIds`. Binding after the `await` on the declaration
        // would leave a window in which those writers see an unbound uid and create a
        // FLAGLESS document for a child. The network half runs below.
        AgeGateStore.shared.bindPendingDeclaration(toUserId: firebaseUID)

        // FR-60(d): the promoted player's local history follows them onto the new uid,
        // before `currentUser` publishes it.
        if let previousPlayIdentity {
            rebindLocalPlayIdentity(from: previousPlayIdentity, to: firebaseUID)
        }

        let newUser = AppUser(
            id: firebaseUID,
            userName: defaultUsername,
            email: email,
            deviceIdentifier: deviceId,
            isUsernameManuallyChanged: carriedManualUsername,
            firebaseUID: firebaseUID
        )
        newUser.avatarId = carriedAvatarId
        newUser.localIDBeforeFirebase = previousPlayIdentity

        modelContext.insert(newUser)
        try? modelContext.save()

        currentUser = newUser
        isAuthenticated = true

        // F-6 (FR-27) declare-before-write, at the provisioning choke point itself.
        // No-op unless this identity epoch answered under-13; on failure the write
        // below stays held (queued; the choke point retries).
        _ = await ensureFlowChildDeclaration(flowUid: firebaseUID)

        do {
            try await saveUserDataToFirestore(newUser)
            // COPPA F-7 (FR-19): fresh-read the just-created doc so the child
            // projection resolves this session (see signInAnonymously note).
            await UserRepository.shared.refreshUsersFromFirestoreIfPresent(userIds: [firebaseUID])
        } catch {
            #if DEBUG
            print("⚠️ Failed to save new user \(firebaseUID) to Firestore: \(error)")
            #endif
        }
    }
    
    /// Real names are never collected (owner decision, F-6 rework): the provider's
    /// display name is discarded — never split into first/last, never stored locally
    /// or in Firestore.
    private func updateUserFromOAuth(_ firebaseUser: User, email: String?, displayName: String?) async {
        guard let modelContext = modelContext,
              let user = currentUser else { return }

        // Update user info from OAuth
        if let email = email, user.email == nil {
            user.email = email
        }

        _ = displayName // provider names are intentionally dropped

        try? modelContext.save()
        try? await saveUserDataToFirestore(user)
    }
    
    // MARK: - Firestore Serialization
    
    /// Loads `users/{userId}` (+ own `private/contact` when applicable).
    /// - Returns: profile when the document exists; `nil` only when it is confirmed absent.
    /// - Throws: on Firestore/network/read failures (callers must not treat throws as "missing").
    private func loadUserDataFromFirestore(userId: String) async throws -> AppUser? {
        let docRef = db.collection("users").document(userId)
        let document = try await docRef.getDocument()
        
        guard document.exists, let data = document.data() else {
            return nil
        }

        UserRepository.shared.ingestEntitlementTags(
            userId: userId,
            tags: UserRepository.parseEntitlementTags(from: data)
        )
        // COPPA §7.1 projection (F-7): fresh-read resolution of the server-owned
        // child flag. Never mirrored into AppUser/SwiftData (§7.4). FR-19: only a
        // server-resolved snapshot may confirm not-child; a cached or
        // pending-write snapshot leaves the projection nil (held).
        if ChildFlagIngestPolicy.mayIngest(
            isFromCache: document.metadata.isFromCache,
            hasPendingWrites: document.metadata.hasPendingWrites
        ) {
            UserRepository.shared.ingestChildAccountResolution(
                userId: userId,
                UserRepository.parseChildAccountResolution(from: data)
            )
            // COPPA FR-88: this session's first server-resolved answer to "is a family still
            // deciding about me?". It is the read that unsticks a device whose optimistic
            // "waiting for approval" flag outlived a decline — see
            // `FamilyApprovalPendingPolicy`. Same provenance gate as the child flag.
            UserRepository.shared.ingestPendingFamilyRequest(
                userId: userId,
                isPresent: UserRepository.parsePendingFamilyRequestPresence(from: data)
            )
        }
        var user = appUserFromFirestoreData(data, id: userId)

        // Own contact may live only under private/contact after PII strip.
        if userId == Auth.auth().currentUser?.uid {
            let contactSnap = try? await docRef.collection("private").document("contact").getDocument()
            if let contact = contactSnap?.data() {
                if let email = contact["email"] as? String, !email.isEmpty {
                    user.email = email
                }
                if let phone = contact["phoneNumber"] as? String, !phone.isEmpty {
                    user.phoneNumber = phone
                }
                // Linked-platform contact is owner-only too (public doc keeps identity only).
                user.linkedPlatforms = LinkedPlatformFirestore.merging(
                    user.linkedPlatforms,
                    privateEntries: contact["linkedPlatforms"] as? [[String: Any]]
                )
            }
        }

        return user
    }
    
    func saveUserDataToFirestore(_ user: AppUser, extraFields: [String: Any] = [:]) async throws {
        let syncUserId = user.firebaseUID ?? user.id

        // F-6 (FR-27, flow-scoped): the ONLY profile writes ever held are the uids a
        // registration flow provisioned while their under-13 declaration is outstanding
        // — retried here (declaration first, then the write). Existing accounts are
        // never held, and a stored answer can never declare a pre-existing uid.
        // FR-60(c): a DETACHED uid is held permanently and is never queued for retry — the
        // account behind it is gone, there is no declaration left to deliver, and the write
        // would recreate the very document the server deleted.
        //
        // Both id fields are checked, not just `firebaseUID ?? id`: a detach nils `firebaseUID`
        // and deliberately leaves the retired uid on `id` (so `firebaseUID ?? id` still resolves
        // the player's local rows), and a row can reach here from either direction.
        let store = AgeGateStore.shared
        if store.isIdentityDetached(syncUserId)
            || store.isIdentityDetached(user.firebaseUID)
            || store.isIdentityDetached(user.id) {
            user.needsSync = false
            try? modelContext?.save()
            return
        }

        if AgeGateProfileWritePolicy.isProfileWriteHeld(
            userUid: syncUserId,
            pendingDeclarationUserIds: AgeGateStore.shared.pendingDeclarationUserIds
        ) {
            guard await ensureFlowChildDeclaration(flowUid: syncUserId) else {
                user.needsSync = true
                try? syncCoordinator?.enqueueUserProfileSync(userId: syncUserId)
                try? modelContext?.save()
                return
            }
        }

        guard isOnline else {
            user.needsSync = true
            try? syncCoordinator?.enqueueUserProfileSync(userId: syncUserId)
            try? modelContext?.save()
            return
        }
        
        guard let firebaseUID = user.firebaseUID else {
            user.needsSync = true
            try? syncCoordinator?.enqueueUserProfileSync(userId: syncUserId)
            try? modelContext?.save()
            return
        }
        
        let docRef = db.collection("users").document(firebaseUID)
        var data = firestoreDataFromAppUser(user)
        for (key, value) in extraFields {
            data[key] = value
        }
        // COPPA §7.4 write guard: the child flag is server-owned (FR-7); no client
        // profile write may ever carry it.
        assert(data["isChildAccount"] == nil, "isChildAccount is server-owned (COPPA FR-7); never written by the client")
        data["isChildAccount"] = nil
        try await docRef.setData(data, merge: true)
        try await savePrivateContact(for: user, userId: firebaseUID)
        await ensureUserProgressionDocumentIfPossible(userId: firebaseUID)
        await ensureFounderEntitlementIfPossible(userId: firebaseUID)
        
        user.lastSyncedToFirebase = .now
        user.needsSync = false
        try? modelContext?.save()
    }

    /// Writes normalized contact under users/{uid}/private/contact for search indexes,
    /// plus the owner-only linked-platform contact rows (FR-43).
    /// Non-destructive: missing local email/phone are omitted (never cleared with null).
    private func savePrivateContact(for user: AppUser, userId: String) async throws {
        var contact: [String: Any] = ContactSearchNormalization.privateContactMergeFields(
            email: user.email,
            phoneNumber: user.phoneNumber
        ) ?? [:]

        if let platformContacts = LinkedPlatformFirestore.privateContactEntries(from: user.linkedPlatforms) {
            contact["linkedPlatforms"] = platformContacts
        }

        guard !contact.isEmpty else { return }
        contact["updatedAt"] = FieldValue.serverTimestamp()
        try await db.collection("users").document(userId)
            .collection("private").document("contact")
            .setData(contact, merge: true)
    }

    private func ensureFounderEntitlementIfPossible(userId: String?) async {
        guard isOnline,
              let userId,
              !userId.isEmpty,
              Auth.auth().currentUser?.uid == userId,
              !isAnonymousUser,
              !founderEntitlementAttemptedUserIds.contains(userId)
        else { return }

        founderEntitlementAttemptedUserIds.insert(userId)
        let outcome = await FounderEntitlementService.shared.ensureIfPossible(isAnonymous: false)
        guard outcome == .granted || outcome == .alreadyGranted else { return }

        try? await refreshCurrentUserFromFirestore()
    }

    private func ensureUserProgressionDocumentIfPossible(userId: String?) async {
        guard isOnline,
              let userId,
              !userId.isEmpty,
              Auth.auth().currentUser?.uid == userId,
              !progressionBootstrapAttemptedUserIds.contains(userId)
        else { return }

        do {
            let fn = Functions.functions().httpsCallable("ensureUserProgressionDocument")
            _ = try await fn.call(([:] as [String: Any]).addingClientMetadata())
            progressionBootstrapAttemptedUserIds.insert(userId)
        } catch {
            #if DEBUG
            print("⚠️ Failed to ensure user_progression document: \(error)")
            #endif
        }
    }
    
    /// Refresh current user data from Firestore (useful after Cloud Function updates)
    func refreshCurrentUserFromFirestore() async throws {
        guard let firebaseUID = currentUser?.firebaseUID ?? Auth.auth().currentUser?.uid else {
            throw NSError(domain: "FirebaseAuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        guard let modelContext = modelContext else {
            throw NSError(domain: "FirebaseAuthService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Model context not set"])
        }
        
        // Load latest data from Firestore
        guard let firestoreUser = try await loadUserDataFromFirestore(userId: firebaseUID) else {
            return
        }
        
        // Find existing user in SwiftData
        let descriptor = FetchDescriptor<AppUser>(
            predicate: #Predicate<AppUser> { $0.firebaseUID == firebaseUID || $0.id == firebaseUID }
        )
        
        if let existingUser = try? modelContext.fetch(descriptor).first {
            // Merge all fields from Firestore (names are never stored — F-6 rework)
            existingUser.userName = firestoreUser.userName
            existingUser.email = firestoreUser.email
            existingUser.phoneNumber = firestoreUser.phoneNumber
            existingUser.userImageURL = firestoreUser.userImageURL
            existingUser.linkedPlatforms = firestoreUser.linkedPlatforms
            existingUser.avatarId = firestoreUser.avatarId
            existingUser.equippedBadgeId = firestoreUser.equippedBadgeId
            existingUser.equippedLicenseCosmeticId = firestoreUser.equippedLicenseCosmeticId
            existingUser.wasEverInFamily = firestoreUser.wasEverInFamily
            // Friends & Family fields
            existingUser.activeFamilyId = firestoreUser.activeFamilyId
            existingUser.friendCount = firestoreUser.friendCount
            existingUser.isRetiredGeneral = firestoreUser.isRetiredGeneral
            existingUser.lastSyncedToFirebase = .now
            existingUser.needsSync = false
            
            try? modelContext.save()
            
            // Update published property
            currentUser = existingUser
            NotificationCenter.default.post(
                name: .userProfilesMerged,
                object: nil,
                userInfo: ["userIds": [firebaseUID]]
            )
        } else {
            // User doesn't exist locally, insert it
            modelContext.insert(firestoreUser)
            try? modelContext.save()
            currentUser = firestoreUser
            NotificationCenter.default.post(
                name: .userProfilesMerged,
                object: nil,
                userInfo: ["userIds": [firebaseUID]]
            )
        }
    }
    
    private func firestoreDataFromAppUser(_ user: AppUser) -> [String: Any] {
        var data: [String: Any] = [
            "userName": user.userName,
            "userNameLower": ContactSearchNormalization.userNameLower(user.userName),
            "createdAt": Timestamp(date: user.createdAt),
            "lastUpdated": Timestamp(date: user.lastUpdated),
            "isUsernameManuallyChanged": user.isUsernameManuallyChanged,
            "privacy": UserPrivacyFirestore.encode(
                isEmailPublic: user.isEmailPublic,
                isPhonePublic: user.isPhonePublic
            )
        ]
        
        // Real names are never collected (owner decision, F-6 rework); purge any
        // existing dev-doc values on sync (same migration pattern as email/phone).
        data["firstName"] = FieldValue.delete()
        data["lastName"] = FieldValue.delete()
        // Email/phone live on private/contact only (not peer-readable public profile).
        data["email"] = FieldValue.delete()
        data["phoneNumber"] = FieldValue.delete()
        if let userImageURL = user.userImageURL {
            data["userImageURL"] = userImageURL
        }
        if let avatarId = user.avatarId {
            data["avatarId"] = avatarId
        }
        if let equippedBadgeId = user.equippedBadgeId {
            data["equippedBadgeId"] = equippedBadgeId
        }
        if let equippedLicenseCosmeticId = user.equippedLicenseCosmeticId {
            data["equippedLicenseCosmeticId"] = equippedLicenseCosmeticId
        }
        // wasEverInFamily is server-owned (set on family join/leave); never overwrite from client.
        data["deviceIdentifier"] = FieldValue.delete()
        // Soft-retire legacy avatar identity (catalog avatarId is source of truth).
        data["avatarColor"] = FieldValue.delete()
        data["avatarType"] = FieldValue.delete()
        // Align with search/functions: privacy.* only (drop top-level legacy keys).
        data["isEmailPublic"] = FieldValue.delete()
        data["isPhonePublic"] = FieldValue.delete()
        if let lastDateLoggedIn = user.lastDateLoggedIn {
            data["lastDateLoggedIn"] = Timestamp(date: lastDateLoggedIn)
        }
        data["lastLoginLocation"] = FieldValue.delete()
        // Push routing lives at users/{uid}/private/fcm; strip any legacy peer-readable copy.
        data["fcmToken"] = FieldValue.delete()
        data["fcmTokenUpdatedAt"] = FieldValue.delete()

        // Friends & Family fields
        if let activeFamilyId = user.activeFamilyId {
            data["activeFamilyId"] = activeFamilyId
        }
        data["friendCount"] = user.friendCount
        data["isRetiredGeneral"] = user.isRetiredGeneral
        data["isRegistered"] = !(Auth.auth().currentUser?.isAnonymous ?? true)
        
        // Platform identity only; provider email/phone/displayName go to private/contact.
        // Overwriting the array also migrates legacy docs that still carry those subfields.
        if !user.linkedPlatforms.isEmpty {
            data["linkedPlatforms"] = LinkedPlatformFirestore.publicEntries(from: user.linkedPlatforms)
        }

        return data
    }
    
    private func appUserFromFirestoreData(_ data: [String: Any], id: String) -> AppUser {
        let userName = (data["userName"] as? String) ?? (data["username"] as? String) ?? "User"
        // firstName/lastName are never read: real names are not collected (F-6 rework).
        let email = data["email"] as? String
        let phoneNumber = data["phoneNumber"] as? String
        let userImageURL = data["userImageURL"] as? String
        let avatarId = data["avatarId"] as? String
        let equippedBadgeId = data["equippedBadgeId"] as? String
        let equippedLicenseCosmeticId = data["equippedLicenseCosmeticId"] as? String
        let wasEverInFamily = data["wasEverInFamily"] as? Bool ?? false
        let deviceIdentifier = data["deviceIdentifier"] as? String
        let isUsernameManuallyChanged = data["isUsernameManuallyChanged"] as? Bool ?? false
        let privacyFlags = UserPrivacyFirestore.decode(from: data)
        let isEmailPublic = privacyFlags.isEmailPublic
        let isPhonePublic = privacyFlags.isPhonePublic
        
        let createdAt: Date
        if let timestamp = data["createdAt"] as? Timestamp {
            createdAt = timestamp.dateValue()
        } else {
            createdAt = .now
        }
        
        let lastUpdated: Date
        if let timestamp = data["lastUpdated"] as? Timestamp {
            lastUpdated = timestamp.dateValue()
        } else {
            lastUpdated = .now
        }
        
        let lastDateLoggedIn: Date?
        if let timestamp = data["lastDateLoggedIn"] as? Timestamp {
            lastDateLoggedIn = timestamp.dateValue()
        } else {
            lastDateLoggedIn = nil
        }
        
        // Legacy top-level `lastLoginLocation` is never parsed — login coordinates are no
        // longer collected, and the profile write scrubs the field (FieldValue.delete()).

        // Legacy avatarType/avatarColor Ignored — catalog avatarId is source of truth (V22+).
        
        var linkedPlatforms: [LinkedPlatform] = []
        if let platformsArray = data["linkedPlatforms"] as? [[String: Any]] {
            for platformData in platformsArray {
                guard let platformString = platformData["platform"] as? String,
                      let platformType = LinkedPlatform.PlatformType(rawValue: platformString),
                      let platformUserId = platformData["platformUserId"] as? String else {
                    continue
                }
                
                let linkedAt: Date
                if let timestamp = platformData["linkedAt"] as? Timestamp {
                    linkedAt = timestamp.dateValue()
                } else {
                    linkedAt = .now
                }
                
                // Legacy pre-FR-43 docs may still carry contact subfields here; reading them
                // keeps the data until the next profile sync moves it to private/contact.
                let platformEmail = platformData["email"] as? String
                let platformPhone = platformData["phoneNumber"] as? String
                let platformDisplayName = platformData["displayName"] as? String

                linkedPlatforms.append(LinkedPlatform(
                    platform: platformType,
                    platformUserId: platformUserId,
                    linkedAt: linkedAt,
                    email: platformEmail,
                    phoneNumber: platformPhone,
                    displayName: platformDisplayName
                ))
            }
        }
        
        // Friends & Family fields
        let activeFamilyId = data["activeFamilyId"] as? String
        let friendCount = data["friendCount"] as? Int ?? 0
        let isRetiredGeneral = data["isRetiredGeneral"] as? Bool ?? false
        
        return AppUser(
            id: id,
            userName: userName,
            email: email,
            phoneNumber: phoneNumber,
            createdAt: createdAt,
            lastUpdated: lastUpdated,
            userImageURL: userImageURL,
            deviceIdentifier: deviceIdentifier,
            isUsernameManuallyChanged: isUsernameManuallyChanged,
            isEmailPublic: isEmailPublic,
            isPhonePublic: isPhonePublic,
            avatarId: avatarId,
            equippedBadgeId: equippedBadgeId,
            equippedLicenseCosmeticId: equippedLicenseCosmeticId,
            wasEverInFamily: wasEverInFamily,
            isRetiredGeneral: isRetiredGeneral,
            activeFamilyId: activeFamilyId,
            friendCount: friendCount,
            linkedPlatforms: linkedPlatforms,
            firebaseUID: id,
            lastSyncedToFirebase: .now,
            needsSync: false,
            lastDateLoggedIn: lastDateLoggedIn
        )
    }
    
    // MARK: - Apple Nonce Helpers
    
    private static func sha256(_ input: String) -> String {
        guard let inputData = input.data(using: .utf8) else { return "" }
        let hashed = SHA256.hash(data: inputData)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    private static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length
        
        while remainingLength > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            let errorCode = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            if errorCode != errSecSuccess {
                fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
            }
            
            randoms.forEach { random in
                if remainingLength == 0 { return }
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }
        
        return result
    }
}

// MARK: - Apple Sign In Helpers

private class AppleSignInDelegate: NSObject, ASAuthorizationControllerDelegate {
    private var continuation: CheckedContinuation<ASAuthorization, Error>?
    private(set) var hasResumed = false
    private let lock = NSLock()
    
    init(continuation: CheckedContinuation<ASAuthorization, Error>) {
        self.continuation = continuation
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        lock.lock()
        defer { lock.unlock() }
        
        guard !hasResumed, let continuation = continuation else { 
            print("⚠️ Apple Sign-In delegate: Already resumed or no continuation")
            return 
        }
        hasResumed = true
        self.continuation = nil
        continuation.resume(returning: authorization)
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        lock.lock()
        defer { lock.unlock() }
        
        guard !hasResumed, let continuation = continuation else { 
            print("⚠️ Apple Sign-In delegate: Already resumed or no continuation")
            return 
        }
        hasResumed = true
        self.continuation = nil
        print("🔗 Apple Sign-In error: \(error.localizedDescription)")
        continuation.resume(throwing: error)
    }
    
    deinit {
        // Safety: If delegate is deallocated without resuming, resume with error
        lock.lock()
        defer { lock.unlock() }
        
        if !hasResumed, let continuation = continuation {
            print("⚠️ Apple Sign-In delegate deallocated without resuming, resuming with cancellation error")
            hasResumed = true
            continuation.resume(throwing: NSError(domain: "AppleSignIn", code: -1, userInfo: [NSLocalizedDescriptionKey: "Sign-in was cancelled"]))
        }
    }
}

private class AppleSignInPresentationContextProvider: NSObject, ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            fatalError("No window available for Apple Sign In")
        }
        return window
    }
}

// MARK: - AuthUIDelegate View Controller

private class AuthUIDelegateViewController: UIViewController, AuthUIDelegate {
    // AuthUIDelegate protocol - UIViewController already provides the necessary presentation context
    // This view controller is used specifically for OAuth flows that require AuthUIDelegate
}

// MARK: - Auth Errors

enum AuthError: LocalizedError {
    case notImplemented
    case noUser
    case invalidCredentials
    case networkError
    case usernameTaken
    case invalidUsername
    case usernameValidationFailure(UsernameValidation.Failure)
    case noModelContext
    case emailAlreadyInUse
    case offline
    case cannotUnlinkLastProvider
    case reauthAccountMismatch
    /// F-18 (FR-60(b)): the redemption uid was minted but `declareChildRegistration` did not
    /// land, so redemption must not proceed. Retryable — the uid stays bound and held.
    case childDeclarationPending

    var errorDescription: String? {
        switch self {
        case .notImplemented:
            return "This feature is not yet available."
        case .noUser:
            return "No user is currently signed in."
        case .invalidCredentials:
            return "Invalid email or password."
        case .networkError:
            return "Unknown Network Error. Please try again later."
        case .usernameTaken:
            return "This username is already taken. Please choose another."
        case .invalidUsername:
            return "Username cannot be empty."
        case .usernameValidationFailure(.profanity):
            return "This username contains inappropriate language. Please choose another.".localized
        case .usernameValidationFailure(.empty):
            return "Username cannot be empty.".localized
        case .noModelContext:
            return "Model context is not available."
        case .emailAlreadyInUse:
            return "This email is already in use. Please sign in or use a different email."
        case .offline:
            return "You are currently offline. Please check your connection."
        case .cannotUnlinkLastProvider:
            return "You cannot unlink your last sign-in method. Please link another account first."
            return "You are offline. Please connect to the internet to perform this action."
        case .reauthAccountMismatch:
            return "Please verify with the same account you are signed in with.".localized
        case .childDeclarationPending:
            return "child_gate.join.setup_incomplete".localized
        }
    }
}

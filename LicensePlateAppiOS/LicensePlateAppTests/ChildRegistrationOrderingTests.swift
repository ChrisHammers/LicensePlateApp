//
//  ChildRegistrationOrderingTests.swift
//  LicensePlateAppTests
//
//  COPPA F-6/F-7 (FR-27 ordering × FR-19 ad eligibility) — owner-reported device
//  incident: "created an account, set to child, but am seeing ads."
//
//  A declared-under-13 account must NEVER reach `.confirmedNonChild`, the only
//  ad-eligible posture. Reaching it requires ALL of:
//    (1) `users/{uid}` exists WITHOUT `isChildAccount` (the declaration never ran
//        before the first write that created the doc), and
//    (2) the device holds no uid-bound child lineage for that uid.
//  Both are consequences of the same defect: the under-13 obligation was tracked as a
//  ONE-SHOT binding (one uid per identity epoch, bound only at the sites that call
//  `ensureFlowChildDeclaration`), while an identity epoch can provision a `users/{uid}`
//  from more than one place and for more than one uid.
//
//  Round 2 adds the writers that are not the profile write at all: every
//  `setData(merge: true)` on `users/{uid}` CREATES the document, so the preference
//  writers can produce shape (1) on their own (`AppPrefsStore.load` fires from
//  `ContentView.handleHomeOnAppear` on the first Home appearance).
//
//  These tests drive the real `AgeGateStore`, `AgeGateProfileWritePolicy`,
//  `UserDocumentWritePolicy`, `AuthProfileSyncPolicy` and `ChildSessionPosturePolicy`
//  through a deterministic transcription of `FirebaseAuthService`'s provisioning
//  sequence — no Firebase, no timing, no device repro. `RegistrationWorld` below
//  mirrors, step for step, the functions named in its doc comments; keep them in sync.
//

import Foundation
import Testing
@testable import LicensePlateApp

// MARK: - Deterministic transcription of the provisioning sequence

@MainActor
private final class RegistrationWorld {

    /// Fake `users/{uid}` document. Only the COPPA-relevant shape matters: whether the
    /// doc exists, and whether the SERVER-owned `isChildAccount` key is present and
    /// what it says. `nil` = the doc exists with NO such key (the dangerous shape).
    struct ServerDoc {
        var isChildAccount: Bool?
    }

    private(set) var serverDocs: [String: ServerDoc] = [:]

    /// `UserRepository.childResolutionByUserId` — the per-session projection.
    private(set) var freshResolution: [String: UserRepository.ChildAccountResolution] = [:]

    /// `ChildSignalCache` (per-uid cache + one-way device ratchet).
    private(set) var cachedIsChildAccount: [String: Bool] = [:]
    private(set) var isDeviceRatcheted = false

    let store: AgeGateStore
    var authUid: String?
    /// `authService.currentUser?.id` as the UI sees it. `handleHomeOnAppear` only
    /// reaches the preference writers once this is non-nil.
    var observableUid: String?
    var isOnline = true
    /// Simulates `declareChildRegistration` failing (offline blip, App Check, transport).
    var declareShouldFail = false
    /// A local `AppUser` row already matches the auth uid (drives `bootstrapAction`).
    var hasLocalUserForAuthUid = false

    private(set) var log: [String] = []

    init() {
        let suite = "ChildRegistrationOrderingTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        store = AgeGateStore(defaults: defaults)
    }

    /// Seeds a `users/{uid}` doc that existed before this session (an account the app
    /// is signing INTO, not provisioning).
    func seedExistingProfile(uid: String, isChildAccount: Bool) {
        serverDocs[uid] = ServerDoc(isChildAccount: isChildAccount)
    }

    // MARK: FirebaseAuthService.ensureFlowChildDeclaration

    @discardableResult
    func ensureFlowChildDeclaration(flowUid: String) -> Bool {
        guard store.bindAndCheckDeclarationOutstanding(forFlowUserId: flowUid) else { return true }
        guard isOnline, authUid == flowUid else { return false }
        guard !declareShouldFail else {
            log.append("declare-failed(\(flowUid))")
            return false
        }
        // Server half (`declareChildRegistrationFlow`): set-merge, protective only —
        // safe before any profile doc exists, and it writes the key EXPLICITLY.
        serverDocs[flowUid] = ServerDoc(isChildAccount: true)
        store.markChildDeclarationSent(userId: flowUid)
        log.append("declared(\(flowUid))")
        return true
    }

    // MARK: FirebaseAuthService.saveUserDataToFirestore

    func saveUserDataToFirestore(uid: String) {
        if AgeGateProfileWritePolicy.isProfileWriteHeld(
            userUid: uid,
            pendingDeclarationUserIds: store.pendingDeclarationUserIds
        ) {
            guard ensureFlowChildDeclaration(flowUid: uid) else {
                log.append("write-held(\(uid))")
                return
            }
        }
        guard isOnline else { return }
        // The client write NEVER carries `isChildAccount` (§7.4 write guard), so it
        // creates a FLAGLESS doc when the declaration has not landed first.
        if serverDocs[uid] == nil { serverDocs[uid] = ServerDoc(isChildAccount: nil) }
        log.append("profile-write(\(uid))")
    }

    // MARK: FirebaseAuthService.updateLoginTracking (timestamp-only merge write —
    // still CREATES `users/{uid}` when it is absent)

    func updateLoginTracking(uid: String) {
        let allowed = !AgeGateProfileWritePolicy.isProfileWriteHeld(
            userUid: uid,
            pendingDeclarationUserIds: store.pendingDeclarationUserIds
        )
        guard allowed, isOnline else {
            log.append("login-write-held(\(uid))")
            return
        }
        if serverDocs[uid] == nil { serverDocs[uid] = ServerDoc(isChildAccount: nil) }
        log.append("login-write(\(uid))")
    }

    // MARK: UserRepository.updateGameDefaults / updateNotificationPrefs /
    // updateParticipationDefaults — plain `setData(merge: true)` preference writers.
    // Reached unconditionally from `ContentView.handleHomeOnAppear` →
    // `AppPrefsStore.load` when the cloud map is absent, i.e. for every brand-new uid.

    func writeAccountPreferences(uid: String) {
        // `handleHomeOnAppear` passes `currentUserId`, so this is unreachable until the
        // uid is observable.
        guard observableUid == uid else {
            log.append("prefs-write-unreachable(\(uid))")
            return
        }
        guard !UserDocumentWritePolicy.isWriteHeld(
            userId: uid,
            pendingDeclarationUserIds: store.pendingDeclarationUserIds
        ) else {
            log.append("prefs-write-held(\(uid))")
            return
        }
        guard isOnline else { return }
        if serverDocs[uid] == nil { serverDocs[uid] = ServerDoc(isChildAccount: nil) }
        log.append("prefs-write(\(uid))")
    }

    // MARK: FirebaseAuthService.createNewUserFromFirebase (the ONE choke point that
    // provisions a brand-new users/{uid}; reached from createAccount AND from the
    // auth-state-listener bootstrap)
    //
    // `publishNewUser` below also stands in for `signInAnonymously`
    // (FirebaseAuthService.swift ~line 313): after the adversarial-review fixup, that
    // function binds synchronously (`AgeGateStore.shared.bindPendingDeclaration`)
    // immediately before `localUser.firebaseUID = firebaseUID` makes the guest uid
    // observable — the identical bind-before-publish shape proven safe below. It isn't
    // modeled as a separate harness function because the policy layer it drives
    // (`AgeGateProfileWritePolicy`, `UserDocumentWritePolicy`) doesn't distinguish call
    // sites; the interleaving proof is call-site-agnostic by construction.

    func createNewUserFromFirebase(uid: String) {
        publishNewUser(uid: uid)
        ensureFlowChildDeclaration(flowUid: uid)
        saveUserDataToFirestore(uid: uid)
        refreshUsersFromFirestoreIfPresent(uid: uid)
    }

    /// The synchronous prefix of `createNewUserFromFirebase` up to and including
    /// `currentUser = newUser` — the instant the uid becomes observable to SwiftUI and
    /// therefore to `handleHomeOnAppear`. Binding happens HERE, before publishing, with
    /// no `await` in between; everything after this point may be interleaved.
    func publishNewUser(uid: String) {
        store.bindPendingDeclaration(toUserId: uid)
        observableUid = uid
        log.append("publish(\(uid))")
    }

    // MARK: UserRepository.refreshUsersFromFirestoreIfPresent (fresh SERVER read)

    func refreshUsersFromFirestoreIfPresent(uid: String) {
        guard isOnline, let doc = serverDocs[uid] else { return }
        freshResolution[uid] = resolution(for: doc)
        log.append("fresh-read(\(uid)=\(String(describing: doc.isChildAccount)))")
    }

    /// `UserRepository.parseChildAccountResolution` semantics.
    private func resolution(for doc: ServerDoc) -> UserRepository.ChildAccountResolution {
        guard let value = doc.isChildAccount else {
            return .init(isChild: false, isServerExplicit: false)
        }
        return .init(isChild: value, isServerExplicit: true)
    }

    // MARK: FirebaseAuthService.loadUserFromFirebase (auth-state-listener bootstrap)

    /// Step 1: read `users/{uid}` and resolve the bootstrap action. Split from step 2
    /// so the network wait between them can be interleaved with the registration call.
    func bootstrapRead(uid: String) -> AuthProfileSyncPolicy.BootstrapAction {
        let load: AuthProfileSyncPolicy.DocumentLoadStatus
        if !isOnline {
            load = .failed
        } else if let doc = serverDocs[uid] {
            freshResolution[uid] = resolution(for: doc)
            load = .found
        } else {
            load = .notFound
        }
        return AuthProfileSyncPolicy.bootstrapAction(
            hasLocalUser: hasLocalUserForAuthUid,
            load: load
        )
    }

    /// Step 2: act on the decision captured in step 1.
    func bootstrapApply(uid: String, action: AuthProfileSyncPolicy.BootstrapAction) {
        switch action {
        case .createLocalThenTrackLogin:
            createNewUserFromFirebase(uid: uid)
            updateLoginTracking(uid: uid)
        case .applyCloudThenTrackLogin, .insertCloudThenTrackLogin, .keepLocalThenTrackLogin:
            // A pre-existing account also becomes the observable current user, but the
            // choke point (and therefore any binding) is never reached for it.
            observableUid = uid
            updateLoginTracking(uid: uid)
        case .abortWithoutCreate:
            break
        }
    }

    // MARK: ChildSessionPostureCoordinator.applyPostures

    func currentPosture(isAnonymous: Bool = false) -> ChildSessionPosture {
        let uid = authUid
        let fresh = uid.flatMap { freshResolution[$0]?.isChild }
        if let uid, let fresh {
            cachedIsChildAccount[uid] = fresh
            if fresh { isDeviceRatcheted = true }
        }
        let cached = uid.flatMap { cachedIsChildAccount[$0] }
        let declared = store.isPendingDeclaration(userId: uid)
            || store.isDeclaredChildUserId(uid)
        if fresh == true || cached == true || declared { isDeviceRatcheted = true }

        return ChildSessionPosturePolicy.posture(for: ChildSessionSignal(
            hasCurrentUser: uid != nil,
            isAnonymousOrSignedOut: isAnonymous || uid == nil,
            freshIsChildAccount: fresh,
            cachedIsChildAccount: cached,
            isDeclaredChildIdentity: declared,
            isAgeResolved: store.isResolved,
            isDeviceRatcheted: isDeviceRatcheted
        ))
    }

    /// The compliance invariant, asserted from both sides.
    func expectChildProtected(uid: String, _ note: String) {
        let posture = currentPosture()
        #expect(
            posture != .confirmedNonChild,
            "\(note): declared child resolved to the ad-eligible posture — log \(log)"
        )
        #expect(
            posture.isAdDisplayEligible == false,
            "\(note): ads eligible for a declared child — log \(log)"
        )
        if let doc = serverDocs[uid] {
            #expect(
                doc.isChildAccount == true,
                "\(note): users/\(uid) exists without isChildAccount — log \(log)"
            )
        }
    }
}

/// All order-preserving interleavings of two step lists (both tasks run on the main
/// actor and each suspends at its network hops, so any merge order is reachable).
private func interleavings<T>(_ a: [T], _ b: [T]) -> [[T]] {
    if a.isEmpty { return [b] }
    if b.isEmpty { return [a] }
    let withAFirst = interleavings(Array(a.dropFirst()), b).map { [a[0]] + $0 }
    let withBFirst = interleavings(a, Array(b.dropFirst())).map { [b[0]] + $0 }
    return withAFirst + withBFirst
}

// MARK: - Tests

@MainActor
struct ChildRegistrationOrderingTests {

    // MARK: The owner's traced path — registration + auth-state-listener bootstrap

    /// `auth.createUser` both returns to `createAccount` (task A) and fires the
    /// auth-state listener (task B). Task B's bootstrap reaches
    /// `.createLocalThenTrackLogin` — a SECOND, independent path that provisions the
    /// same brand-new `users/{uid}`. Before the fix that path performed no declaration
    /// at all: it was safe only when task A happened to bind first. Now the declaration
    /// lives at the provisioning choke point, so EVERY interleaving is safe.
    ///
    /// The invariant is checked after EVERY step, not just at the end: both triggers of
    /// `applyPostures` (the identity transition and the `.userProfilesMerged` post that
    /// a fresh read emits) fire inside this window, so even a transient
    /// `.confirmedNonChild` un-stamps the ads config and makes banners eligible.
    @Test func registrationAndListenerBootstrap_everyInterleavingDeclaresBeforeTheFirstWrite() {
        let uid = "uid-new-child"

        for (index, order) in interleavings(["A1", "A2"], ["B1", "B2"]).enumerated() {
            let world = RegistrationWorld()
            world.store.recordAnswer(.under13) // registration age step, pre-uid
            world.authUid = uid                // auth.createUser has returned a uid

            var bootstrapAction: AuthProfileSyncPolicy.BootstrapAction = .abortWithoutCreate

            for (stepIndex, step) in order.enumerated() {
                switch step {
                case "A1": world.ensureFlowChildDeclaration(flowUid: uid)
                case "A2": world.createNewUserFromFirebase(uid: uid)
                case "B1": bootstrapAction = world.bootstrapRead(uid: uid)
                case "B2": world.bootstrapApply(uid: uid, action: bootstrapAction)
                default: Issue.record("unknown step \(step)")
                }
                world.expectChildProtected(
                    uid: uid,
                    "interleaving \(index) \(order) after step \(stepIndex + 1) (\(step))"
                )
            }

            #expect(world.store.isDeclaredChildUserId(uid) == true, "interleaving \(index) \(order)")
        }
    }

    /// The exact scenario in the bug report, isolated: the listener bootstrap runs to
    /// completion FIRST, against a fresh uid, before the registration call has bound
    /// anything. This is the interleaving that used to write a flagless `users/{uid}`,
    /// fresh-read it as `false`, and land on `.confirmedNonChild`.
    @Test func listenerBootstrapAlone_neverProvisionsAChildAsAnAdult() {
        let world = RegistrationWorld()
        let uid = "uid-listener-first"
        world.store.recordAnswer(.under13)
        world.authUid = uid

        // Nothing bound yet — the pre-fix write-hold was a no-op in exactly this state.
        #expect(world.store.pendingDeclarationUserIds.isEmpty)

        let action = world.bootstrapRead(uid: uid)
        #expect(action == .createLocalThenTrackLogin)
        world.bootstrapApply(uid: uid, action: action)

        #expect(world.serverDocs[uid]?.isChildAccount == true)
        #expect(world.currentPosture() == .childDirected)
        #expect(world.currentPosture().isAdDisplayEligible == false)
    }

    /// Same interleaving with the declaration failing: the write must stay HELD (no
    /// flagless doc), the session stays child-directed, and the obligation is still
    /// recorded for the retry.
    @Test func listenerBootstrapWithFailedDeclaration_holdsTheWriteInsteadOfWritingAnAdult() {
        let world = RegistrationWorld()
        let uid = "uid-declare-fails"
        world.store.recordAnswer(.under13)
        world.authUid = uid
        world.declareShouldFail = true

        world.bootstrapApply(uid: uid, action: world.bootstrapRead(uid: uid))

        #expect(world.serverDocs[uid] == nil, "a held write must not create users/\(uid)")
        #expect(world.store.isPendingDeclaration(userId: uid) == true)
        #expect(world.currentPosture() == .childDirected)

        // Retry (sync queue / next launch) closes it out.
        world.declareShouldFail = false
        world.saveUserDataToFirestore(uid: uid)
        world.refreshUsersFromFirestoreIfPresent(uid: uid)
        #expect(world.serverDocs[uid]?.isChildAccount == true)
        #expect(world.currentPosture() == .childDirected)
    }

    // MARK: Two uids inside one identity epoch

    /// `createAccount`'s anonymous-upgrade branch: when `link(with:)` fails it signs out
    /// and calls `createUser`, so ONE epoch provisions TWO uids. The epoch's under-13
    /// answer had already been spent on the guest uid, so the second uid used to
    /// short-circuit to "no hold", be written flagless, and read back as an adult.
    @Test func secondUidProvisionedInTheSameEpochIsAlsoHeldAndDeclared() {
        let world = RegistrationWorld()
        let guestUid = "uid-guest"
        let registeredUid = "uid-after-failed-link"

        // Guest provisioning: answer, declare, write.
        world.store.recordAnswer(.under13)
        world.authUid = guestUid
        world.ensureFlowChildDeclaration(flowUid: guestUid)
        world.saveUserDataToFirestore(uid: guestUid)
        #expect(world.store.isDeclaredChildUserId(guestUid) == true)

        // link(with:) throws → auth.signOut() → auth.createUser() → a NEW uid, same
        // epoch, same child.
        world.authUid = registeredUid
        world.createNewUserFromFirebase(uid: registeredUid)

        #expect(world.store.isDeclaredChildUserId(registeredUid) == true)
        world.expectChildProtected(uid: registeredUid, "second uid in one epoch")
    }

    /// Two uids can owe declarations at once (the first one's call failed). Binding the
    /// second must not release the first — the reason the obligation is a set, not a slot.
    @Test func bindingASecondUidDoesNotReleaseTheFirstUidsHold() {
        let world = RegistrationWorld()
        world.store.recordAnswer(.under13)

        world.authUid = "uid-first"
        world.declareShouldFail = true
        world.ensureFlowChildDeclaration(flowUid: "uid-first")

        world.authUid = "uid-second"
        world.ensureFlowChildDeclaration(flowUid: "uid-second")

        #expect(world.store.isPendingDeclaration(userId: "uid-first") == true)
        #expect(world.store.isPendingDeclaration(userId: "uid-second") == true)
        world.saveUserDataToFirestore(uid: "uid-first")
        #expect(world.serverDocs["uid-first"] == nil, "the first uid's write must stay held")
    }

    // MARK: Sign-out with an undelivered declaration

    /// Sign-out ends the epoch, but the uid-bound promise survives: signing back in must
    /// not write that account's profile as an adult.
    @Test func signOutWithAnUndeliveredDeclaration_stillHoldsAndStillDeclaresOnReturn() {
        let world = RegistrationWorld()
        let uid = "uid-child-undelivered"
        world.store.recordAnswer(.under13)
        world.authUid = uid
        world.declareShouldFail = true
        world.createNewUserFromFirebase(uid: uid)
        #expect(world.serverDocs[uid] == nil)

        // Sign out (clears the epoch answer) and sign back into the same account.
        world.store.clearAnswer()
        world.authUid = nil
        world.authUid = uid
        world.hasLocalUserForAuthUid = true
        world.declareShouldFail = false

        world.bootstrapApply(uid: uid, action: world.bootstrapRead(uid: uid))
        // The login-timestamp merge write is held, so no flagless doc appears.
        #expect(world.serverDocs[uid] == nil)
        #expect(world.currentPosture() == .childDirected)

        // The queued profile sync retries the declaration and closes it out.
        world.saveUserDataToFirestore(uid: uid)
        world.refreshUsersFromFirestoreIfPresent(uid: uid)
        #expect(world.serverDocs[uid]?.isChildAccount == true)
        world.expectChildProtected(uid: uid, "sign-out with undelivered declaration")
    }

    // MARK: GAP 1(a) — the preference writers are writers too

    /// `ContentView.handleHomeOnAppear` → `AppPrefsStore.load` → `updateGameDefaults`
    /// fires unconditionally on the first Home appearance, and `setData(merge: true)`
    /// CREATES `users/{uid}`. For a child whose declaration has not landed, that write
    /// produced exactly the flagless doc that reads back as not-a-child. It must be held
    /// by the same policy as the profile write.
    @Test func preferenceWritesNeverCreateAFlaglessDocForAHeldChild() {
        let world = RegistrationWorld()
        let uid = "uid-prefs-race"
        world.store.recordAnswer(.under13)
        world.authUid = uid
        world.declareShouldFail = true

        // Registration publishes the uid (binding first), then the declaration fails.
        world.publishNewUser(uid: uid)
        world.ensureFlowChildDeclaration(flowUid: uid)
        #expect(world.store.isPendingDeclaration(userId: uid) == true)

        // Home appears and the prefs load fires against the brand-new uid.
        world.writeAccountPreferences(uid: uid)

        #expect(world.serverDocs[uid] == nil, "prefs write must not create users/\(uid)")
        #expect(world.log.contains("prefs-write-held(\(uid))"))
        world.expectChildProtected(uid: uid, "prefs writer during a held declaration")
    }

    /// The prefs write becomes reachable the instant `currentUser` is published, and
    /// every step after that publish is an `await` boundary the Home task can slot into.
    /// So the binding must happen in the SAME synchronous turn as the publish — this
    /// exhaustively interleaves the Home task against the remaining provisioning steps
    /// and asserts the invariant after every one.
    ///
    /// Regression: with the bind placed after the declaration's `await` (its first
    /// position in this round), the `publish → prefs` order created a flagless
    /// `users/{uid}` for a child and this test failed on `doc.isChildAccount == nil`.
    @Test func prefsWriteInterleavedWithProvisioningIsAlwaysSafe() {
        let uid = "uid-prefs-interleave"

        // Task A: the rest of createNewUserFromFirebase after the publish.
        // Task B: handleHomeOnAppear → AppPrefsStore.load → updateGameDefaults.
        for (index, order) in interleavings(["declare", "profile-write", "fresh-read"], ["prefs"]).enumerated() {
            let world = RegistrationWorld()
            world.store.recordAnswer(.under13)
            world.authUid = uid

            world.publishNewUser(uid: uid)
            // Publishing alone must already have bound the obligation.
            #expect(
                world.store.isPendingDeclaration(userId: uid) == true,
                "uid observable before it was bound — interleaving \(index) \(order)"
            )

            for step in order {
                switch step {
                case "declare": world.ensureFlowChildDeclaration(flowUid: uid)
                case "profile-write": world.saveUserDataToFirestore(uid: uid)
                case "fresh-read": world.refreshUsersFromFirestoreIfPresent(uid: uid)
                case "prefs": world.writeAccountPreferences(uid: uid)
                default: Issue.record("unknown step \(step)")
                }
                world.expectChildProtected(uid: uid, "prefs interleaving \(index) \(order) after \(step)")
            }
        }
    }

    /// The same interleaving with the declaration failing throughout: the prefs write
    /// must stay held for as long as the obligation is outstanding, so no flagless doc
    /// is ever created.
    @Test func prefsWriteStaysHeldForAsLongAsTheDeclarationIsOutstanding() {
        let world = RegistrationWorld()
        let uid = "uid-prefs-declare-fails"
        world.store.recordAnswer(.under13)
        world.authUid = uid
        world.declareShouldFail = true

        world.publishNewUser(uid: uid)
        for _ in 0..<3 {
            world.ensureFlowChildDeclaration(flowUid: uid)
            world.writeAccountPreferences(uid: uid)
            world.saveUserDataToFirestore(uid: uid)
        }

        #expect(world.serverDocs[uid] == nil, "nothing may create users/\(uid) while held")
        #expect(world.log.contains("prefs-write-held(\(uid))"))
        #expect(world.currentPosture() == .childDirected)
    }

    /// The hold is uid-scoped, so an ADULT's preference writes are never affected.
    @Test func preferenceWritesAreNeverHeldForAnAdult() {
        let world = RegistrationWorld()
        let uid = "uid-adult-prefs"
        world.store.recordAnswer(.teenAdult)
        world.authUid = uid

        world.createNewUserFromFirebase(uid: uid)
        world.writeAccountPreferences(uid: uid)

        #expect(world.log.contains("prefs-write(\(uid))"))
        #expect(world.currentPosture() == .confirmedNonChild)
    }

    // MARK: Guardrails — the fix must not over-hold

    /// A 13+ registration is untouched: nothing binds, nothing holds, the profile is
    /// written, and the fresh read confirms not-child so ads stay eligible (D-6 / FR-19).
    ///
    /// This is also the case that forbids a naive "absent flag ⇒ unresolved forever"
    /// fix: a legitimate adult document never carries `isChildAccount`, so the
    /// projection must still resolve it to `false`.
    @Test func adultRegistrationIsNeverHeldAndStaysAdEligible() {
        let world = RegistrationWorld()
        let uid = "uid-adult"
        world.store.recordAnswer(.teenAdult)
        world.authUid = uid

        world.createNewUserFromFirebase(uid: uid)

        #expect(world.store.pendingDeclarationUserIds.isEmpty)
        #expect(world.serverDocs[uid]?.isChildAccount == nil, "adult docs carry no flag")
        #expect(world.freshResolution[uid]?.isChild == false)
        #expect(world.freshResolution[uid]?.isServerExplicit == false)
        #expect(world.currentPosture() == .confirmedNonChild)
        #expect(world.currentPosture().isAdDisplayEligible == true)
    }

    /// Incident-1: an EXISTING signed-in captain on a device carrying a stale, unbound
    /// under-13 answer. Their `users/{uid}` exists, so the bootstrap resolves to
    /// `.applyCloudThenTrackLogin` — the provisioning choke point (and therefore any
    /// binding or declaration) is unreachable for them. Their write is never held and
    /// their session is never classified as a child.
    @Test func incident1Regression_existingAccountIsNeverHeldBoundOrDeclared() {
        let world = RegistrationWorld()
        let captainUid = "uid-captain"
        world.seedExistingProfile(uid: captainUid, isChildAccount: false) // pre-existing adult
        world.hasLocalUserForAuthUid = true
        world.store.recordAnswer(.under13)     // stale answer sitting on the device
        world.authUid = captainUid

        let action = world.bootstrapRead(uid: captainUid)
        #expect(action == .applyCloudThenTrackLogin)
        world.bootstrapApply(uid: captainUid, action: action)

        #expect(world.store.pendingDeclarationUserIds.isEmpty)
        #expect(world.store.isDeclaredChildUserId(captainUid) == false)
        #expect(world.log.contains("login-write(\(captainUid))"))
        #expect(world.currentPosture() == .confirmedNonChild)

        // Their preference writes are untouched too.
        world.writeAccountPreferences(uid: captainUid)
        #expect(world.log.contains("prefs-write(\(captainUid))"))
    }

    /// Incident-2: after sign-out the epoch answer is gone, so a brand-new sign-up is
    /// NOT silently declared a child by the previous flow's answer.
    @Test func incident2Regression_clearedEpochNeverDeclaresTheNextSignUp() {
        let world = RegistrationWorld()
        world.store.recordAnswer(.under13)
        world.authUid = "uid-old-child"
        world.ensureFlowChildDeclaration(flowUid: "uid-old-child")
        world.store.clearAnswer() // sign-out

        let newUid = "uid-new-adult"
        world.authUid = newUid
        world.createNewUserFromFirebase(uid: newUid)

        #expect(world.store.isDeclaredChildUserId(newUid) == false)
        #expect(world.store.isPendingDeclaration(userId: newUid) == false)
        #expect(world.serverDocs[newUid]?.isChildAccount == nil)
    }
}

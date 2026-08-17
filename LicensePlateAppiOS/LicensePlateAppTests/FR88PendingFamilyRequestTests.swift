//
//  FR88PendingFamilyRequestTests.swift
//  LicensePlateAppTests
//
//  COPPA FR-88 (device pass 2026-08-17): "waiting for your family's approval" becomes a
//  claim the server backs instead of a guess the device makes.
//
//  THE DEFECT. The waiting state was a UserDefaults uid written at share-code redemption and
//  cleared in exactly two places: the child stops being a restricted unconsented child (they
//  were approved) and identity detach (the account was deleted). A DECLINE that deletes
//  nothing clears neither — and FR-60(c) deliberately spares a child with
//  `wasEverInFamily == true` — so that child kept a screen promising an answer from a captain
//  who had already said no. They could not check: `families/{id}/pending` is member-read-only
//  and a pending child is not a member.
//
//  THE FIX under test here is the client half: `users/{uid}.pendingFamilyRequest`, server-
//  written on the same batch as the pending row, arriving on the FR-23 self listener that is
//  already pinned. Three properties matter and each is pinned below:
//
//    1. server PRESENT ⇒ pending, whatever the device believes;
//    2. server ABSENT from a SERVER-RESOLVED read ⇒ not pending, and the stale device flag is
//       retired — the self-healing half, and the whole reason the field exists;
//    3. server UNANSWERED ⇒ the device flag stands, so redemption still reads "waiting"
//       instantly and an offline session behaves exactly as it did before.
//
//  A cached or latency-compensated snapshot is never an answer for (2): a doc the server
//  stamped moments ago legitimately lacks the field in the local cache, and reading that as
//  "nobody is deciding" would retire a live consent request.
//

import Foundation
import Testing
@testable import LicensePlateApp

@MainActor
struct FR88PendingFamilyRequestTests {

    // MARK: - Harness

    /// A service whose server projection is a dictionary the test can flip mid-scenario,
    /// standing in for a snapshot arriving on the pinned listener. Assigning `nil` removes
    /// the entry, which is exactly the "no server answer this session" state.
    private final class ServerProjection {
        var answers: [String: Bool] = [:]
        func answer(for uid: String) -> Bool? { answers[uid] }
    }

    private func makeService(
        currentUserId: String?,
        activeFamilyId: String? = nil,
        projection: ServerProjection
    ) -> (service: ChildRestrictedModeService, defaults: UserDefaults) {
        let suite = "FR88PendingFamilyRequestTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = AgeGateStore(defaults: defaults)
        store.recordAnswer(.under13)
        if let currentUserId {
            store.markChildDeclarationSent(userId: currentUserId)
        }
        let service = ChildRestrictedModeService(
            ageGateStore: store,
            defaults: defaults,
            childSignalCache: ChildSignalCache(defaults: defaults)
        )
        service.configure(
            currentUserIdProvider: { currentUserId },
            activeFamilyIdProvider: { activeFamilyId },
            resolvedIsChildAccountProvider: { _ in true },
            serverPendingFamilyRequestProvider: { projection.answer(for: $0) }
        )
        return (service, defaults)
    }

    private func localFlag(_ defaults: UserDefaults) -> String? {
        defaults.string(forKey: ChildRestrictedModeKeys.pendingFamilyApprovalUserId)
    }

    // MARK: - The rule itself

    /// The whole reconciliation as a truth table. `nil` is the only input that defers to the
    /// device, and it is the only input that must never retire the device's flag.
    @Test func policyTruthTable() {
        typealias P = FamilyApprovalPendingPolicy

        #expect(P.isPending(serverPendingFamilyRequest: true, hasLocalOptimisticFlag: false) == true)
        #expect(P.isPending(serverPendingFamilyRequest: true, hasLocalOptimisticFlag: true) == true)
        #expect(P.isPending(serverPendingFamilyRequest: false, hasLocalOptimisticFlag: true) == false)
        #expect(P.isPending(serverPendingFamilyRequest: false, hasLocalOptimisticFlag: false) == false)
        #expect(P.isPending(serverPendingFamilyRequest: nil, hasLocalOptimisticFlag: true) == true)
        #expect(P.isPending(serverPendingFamilyRequest: nil, hasLocalOptimisticFlag: false) == false)

        #expect(P.shouldClearLocalOptimisticFlag(serverPendingFamilyRequest: false) == true)
        #expect(P.shouldClearLocalOptimisticFlag(serverPendingFamilyRequest: true) == false)
        #expect(P.shouldClearLocalOptimisticFlag(serverPendingFamilyRequest: nil) == false)
    }

    // MARK: - The projection

    @Test func projectionIsTriStateAndNilUntilAServerReadResolvesIt() {
        let repo = UserRepository()
        let uid = "fr88-projection-\(UUID().uuidString)"

        #expect(repo.hasPendingFamilyRequest(for: uid) == nil)

        repo.ingestPendingFamilyRequest(userId: uid, isPresent: true)
        #expect(repo.hasPendingFamilyRequest(for: uid) == true)

        repo.ingestPendingFamilyRequest(userId: uid, isPresent: false)
        #expect(repo.hasPendingFamilyRequest(for: uid) == false)
    }

    /// Presence is the entire signal — the payload is never read, and anything at all under
    /// the key counts, which is the conservative direction (keeps a live request visible).
    @Test func parsePresenceIgnoresThePayload() {
        #expect(UserRepository.parsePendingFamilyRequestPresence(from: ["userName": "kid"]) == false)
        #expect(
            UserRepository.parsePendingFamilyRequestPresence(from: [
                "pendingFamilyRequest": ["familyId": "fam1", "requestId": "req1"]
            ]) == true
        )
        #expect(
            UserRepository.parsePendingFamilyRequestPresence(from: ["pendingFamilyRequest": "junk"]) == true
        )
    }

    @Test func signOutClearsTheProjection() {
        let repo = UserRepository()
        let uid = "fr88-clear-\(UUID().uuidString)"
        repo.ingestPendingFamilyRequest(userId: uid, isPresent: true)
        #expect(repo.hasPendingFamilyRequest(for: uid) == true)

        repo.clearInMemoryState()
        #expect(repo.hasPendingFamilyRequest(for: uid) == nil)
    }

    /// FR-19 provenance, applied to the new field: a cached / latency-compensated snapshot
    /// merges profile fields but leaves the projection UNRESOLVED. Without this, a child who
    /// went offline holding a live request would have it retired by their own stale cache.
    @Test func aCachedSnapshotNeverResolvesTheProjection() async throws {
        let repo = UserRepository()
        let uid = "fr88-cached-\(UUID().uuidString)"

        try await repo.mergeRemoteUserDocument(
            userId: uid,
            data: ["userName": "Speedy"],
            isServerResolved: false
        )
        #expect(repo.hasPendingFamilyRequest(for: uid) == nil)

        // The same flagless payload from a genuine server read DOES resolve it.
        try await repo.mergeRemoteUserDocument(
            userId: uid,
            data: ["userName": "Speedy"],
            isServerResolved: true
        )
        #expect(repo.hasPendingFamilyRequest(for: uid) == false)
    }

    @Test func aServerResolvedSnapshotCarryingTheStampResolvesPending() async throws {
        let repo = UserRepository()
        let uid = "fr88-present-\(UUID().uuidString)"

        try await repo.mergeRemoteUserDocument(
            userId: uid,
            data: [
                "userName": "Speedy",
                "pendingFamilyRequest": ["familyId": "fam1", "requestId": "req1"]
            ],
            isServerResolved: true
        )
        #expect(repo.hasPendingFamilyRequest(for: uid) == true)
    }

    // MARK: - Reconciliation matrix

    @Test func serverPresentMeansPendingEvenWithNoDeviceFlag() {
        let projection = ServerProjection()
        projection.answers["kid"] = true
        let (service, defaults) = makeService(currentUserId: "kid", projection: projection)

        #expect(localFlag(defaults) == nil)
        #expect(service.isFamilyApprovalPending == true)
    }

    /// The stamp is what a child sees after re-provisioning on a device that never redeemed
    /// anything — the device has no flag to offer, and the server's answer stands alone.
    @Test func serverPresentSurvivesAReconcilePass() {
        let projection = ServerProjection()
        projection.answers["kid"] = true
        let (service, defaults) = makeService(currentUserId: "kid", projection: projection)
        service.markFamilyApprovalPending()

        service.reconcileFamilyApprovalPendingWithServer()

        #expect(service.isFamilyApprovalPending == true)
        #expect(localFlag(defaults) == "kid")
    }

    @Test func serverAbsentFromAFreshReadOverridesAStaleDeviceFlag() {
        let projection = ServerProjection()
        let (service, defaults) = makeService(currentUserId: "kid", projection: projection)
        service.markFamilyApprovalPending()
        #expect(service.isFamilyApprovalPending == true)   // unresolved: device flag stands

        projection.answers["kid"] = false                  // the server answers: nobody is deciding
        #expect(service.isFamilyApprovalPending == false)
        // Reading the truth is not enough — the stale flag has to be retired, or it comes
        // back the next time the projection is unresolved (cold launch, offline).
        #expect(localFlag(defaults) == "kid")
        service.reconcileFamilyApprovalPendingWithServer()
        #expect(localFlag(defaults) == nil)
    }

    @Test func anUnresolvedProjectionHonoursTheDeviceFlagAndNeverClearsIt() {
        let projection = ServerProjection()
        let (service, defaults) = makeService(currentUserId: "kid", projection: projection)
        service.markFamilyApprovalPending()

        service.reconcileFamilyApprovalPendingWithServer()

        #expect(service.isFamilyApprovalPending == true)
        #expect(localFlag(defaults) == "kid")
    }

    /// A CACHED snapshot leaves the projection unresolved (see the repository test above), so
    /// end to end it can never clear the flag. Pinned at the service level too, because this
    /// is the composition that would actually strand a child mid-request.
    @Test func aCachedSnapshotCannotRetireALiveRequest() async throws {
        let repo = UserRepository()
        let uid = "fr88-cached-service-\(UUID().uuidString)"
        let projection = ServerProjection()
        let (service, defaults) = makeService(currentUserId: uid, projection: projection)
        service.markFamilyApprovalPending()

        try await repo.mergeRemoteUserDocument(
            userId: uid,
            data: ["userName": "Speedy"],
            isServerResolved: false
        )
        projection.answers[uid] = repo.hasPendingFamilyRequest(for: uid)

        service.reconcileFamilyApprovalPendingWithServer()

        #expect(service.isFamilyApprovalPending == true)
        #expect(localFlag(defaults) == uid)
    }

    @Test func aSessionWithNoCloudIdentityIgnoresTheServerEntirely() {
        let projection = ServerProjection()
        projection.answers["kid"] = true
        let (service, _) = makeService(currentUserId: nil, projection: projection)

        // FR-60(c): a local-first child has no uid, so there is no doc and no claim to make.
        #expect(service.isFamilyApprovalPending == false)
    }

    @Test func onlyAMergeOfTheCurrentUidReconciles() {
        let projection = ServerProjection()
        let (service, defaults) = makeService(currentUserId: "kid", projection: projection)
        service.markFamilyApprovalPending()
        projection.answers["kid"] = false

        service.noteUserProfilesMerged(userIds: ["someone-else"])
        #expect(localFlag(defaults) == "kid")

        service.noteUserProfilesMerged(userIds: ["someone-else", "kid"])
        #expect(localFlag(defaults) == nil)
    }

    // MARK: - The owner's bug, end to end

    /// A declined child whose account was NOT deleted (`wasEverInFamily == true`, so FR-60(c)
    /// spares it). Before FR-88 this device claimed a family was deciding for the rest of the
    /// install's life; the server clearing its stamp is now what ends it — and the clear must
    /// SURVIVE the projection going unresolved again, which is why the device flag is retired
    /// and not merely outvoted.
    @Test func aDeclineThatSparesTheAccountUnsticksTheDevice() {
        let projection = ServerProjection()
        let (service, defaults) = makeService(currentUserId: "kid", projection: projection)

        // Redemption: optimistic flag up, server has not answered yet.
        service.markFamilyApprovalPending()
        #expect(service.isFamilyApprovalPending == true)

        // The request reaches the captain — the server stamps the child's own doc.
        projection.answers["kid"] = true
        service.noteUserProfilesMerged(userIds: ["kid"])
        #expect(service.isFamilyApprovalPending == true)

        // DECLINED. The account survives; the stamp does not.
        projection.answers["kid"] = false
        service.noteUserProfilesMerged(userIds: ["kid"])

        #expect(service.isFamilyApprovalPending == false)
        #expect(localFlag(defaults) == nil)

        // Next cold launch, offline: the projection is unresolved again and there is nothing
        // stale left to resurrect the waiting state.
        projection.answers["kid"] = nil
        #expect(service.isFamilyApprovalPending == false)
    }

    // MARK: - The consumers, unchanged behind the same property

    /// FR-28f: the pending presentation is always full-size and always keeps share-code entry
    /// reachable, so a child whose request was declined lands on a prompt they can act on
    /// rather than a dead "waiting" screen.
    @Test func theHomeBannerFollowsServerTruth() {
        let projection = ServerProjection()
        let (service, _) = makeService(currentUserId: "kid", projection: projection)
        service.markFullFamilyPromptPresented()
        service.markFamilyApprovalPending()

        projection.answers["kid"] = true
        #expect(service.familyPromptPresentation == .full)

        projection.answers["kid"] = false
        // Back to the ordinary FR-28 prompt — still visible, still the route to a share code.
        #expect(service.familyPromptPresentation == .compact)
        #expect(service.familyPromptPresentation.isVisible == true)
    }

    /// `AuthenticationStatusPolicy` state (5) claims a live request EXISTS. It needed no
    /// change: it reads the reconciled property, so the claim is now the server's.
    @Test func authenticationStatusStateFiveFollowsServerTruth() {
        let projection = ServerProjection()
        let (service, _) = makeService(currentUserId: "kid", projection: projection)
        service.markFamilyApprovalPending()

        func state() -> AuthenticationStatusState {
            AuthenticationStatusPolicy.state(
                for: .init(
                    isAnonymousSession: true,
                    hasFirebaseUid: true,
                    childSessionState: service.childSessionState,
                    isFamilyApprovalPending: service.isFamilyApprovalPending,
                    wasEverInFamily: true
                )
            )
        }

        projection.answers["kid"] = true
        #expect(state() == .transientDeclaredChild)

        // Declined: the card stops claiming a captain is deliberating and falls to the
        // sticky post-revocation copy, which is what this session actually is.
        projection.answers["kid"] = false
        #expect(state() == .postRevocationChild)
    }
}

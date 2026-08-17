//
//  FamilyCaptainRosterRegressionTests.swift
//  LicensePlateAppTests
//
//  THE CAPTAIN REGRESSION — device pass 2026-08-17.
//
//  "My Captain user interface no longer allows me to do anything with the User. As if I am not
//  captain. Pending Users then has no user info as well... I created the share code, but get no
//  red bubble or other UI elements of a captain."
//
//  The server never stopped believing he was a captain — `createShareCode` requires
//  `families/{id}/members/{uid}` to exist (`shareCodes.ts`) and it succeeded. What failed was
//  purely local: every family surface answers "am I a captain?" by looking for MY row in
//  `members`, and the refresh paths published an EMPTY local read straight over a good roster.
//  An empty roster is not a neutral state on these screens — it is an authorization answer.
//
//  What made an empty read reachable in the field: `expireInvitesAndCodes` deleted a
//  provisional child's account 15 minutes after the captain shared a code, and nothing pruned
//  the local pending row that named them. The dead uid stayed in the hydration set forever,
//  so every identity refresh ran a denied round trip for a document that will never exist —
//  and each of those refreshes ended in an unguarded `members = getMembers(...)`.
//
//  Pinned here, in the order the failure travelled:
//    1. an empty re-read never demotes a captain (`FamilyRosterPublishPolicy`);
//    2. the dashboard keeps `canManageFamily` across a refresh cycle whose hydration set
//       contains an unreadable/deleted uid;
//    3. Family Settings — the screen that actually holds the manage controls — keeps
//       `isCaptainOrCreator` across the same cycle;
//    4. a pending row the server no longer lists is retired locally instead of haunting the
//       roster forever with no identity.
//

import Foundation
import SwiftData
import Testing
@testable import LicensePlateApp

@MainActor
struct FamilyCaptainRosterRegressionTests {

    private let familyId = "fam-1"
    private let captainId = "captain-uid"
    /// The uid `expireInvitesAndCodes` deleted on 2026-08-17. Its `users/{uid}` document is
    /// gone; every read of it now fails, forever.
    private let deletedChildId = "iWD7OYLYnCODzXTGLljYkyILsF32"

    private func makeContext() throws -> ModelContext {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: AppMigrationPlan.self,
            configurations: [config]
        )
        return ModelContext(container)
    }

    private func seedFamily(in context: ModelContext, withGhostPendingRow: Bool) throws {
        context.insert(Family(familyId: familyId, name: "Hammers", creatorId: captainId))
        context.insert(FamilyMember(familyId: familyId, userId: captainId, role: .creator))
        context.insert(FamilyMember(familyId: familyId, userId: "scout-1", role: .scout))
        if withGhostPendingRow {
            context.insert(
                PendingJoinRequest(
                    requestId: "req-ghost",
                    familyId: familyId,
                    userId: deletedChildId,
                    requestedBy: deletedChildId,
                    method: .code
                )
            )
        }
        try context.save()
    }

    private func auth() -> FirebaseAuthService {
        let service = FirebaseAuthService()
        let user = AppUser(id: captainId, userName: "captain", firebaseUID: captainId)
        user.activeFamilyId = familyId
        service.currentUser = user
        return service
    }

    // MARK: - 1. The rule itself

    @Test("An empty re-read never replaces a populated roster")
    func emptyReReadIsRefused() {
        let populated = [FamilyMember(familyId: "f", userId: "u", role: .creator)]

        #expect(FamilyRosterPublishPolicy.shouldPublish(refreshed: [], current: populated) == false)
        #expect(FamilyRosterPublishPolicy.shouldPublish(refreshed: populated, current: []) == true)
        #expect(FamilyRosterPublishPolicy.shouldPublish(refreshed: populated, current: populated) == true)
        // Nothing to protect: an empty read on an empty surface is the ordinary first load.
        #expect(FamilyRosterPublishPolicy.shouldPublish(refreshed: [], current: []) == true)
    }

    // MARK: - 2. The dashboard across a refresh cycle

    /// THE named regression test. A captain with a populated roster keeps `canManageFamily`
    /// across a full `refreshMemberIdentitiesIfNeeded()` cycle in which the hydration set
    /// contains a uid whose account was deleted — and even if the local store answers the
    /// post-refresh re-read with nothing at all.
    @Test("A captain keeps canManageFamily across a refresh cycle carrying a dead uid")
    func captainSurvivesRefreshCycleWithDeletedRequester() async throws {
        let context = try makeContext()
        try seedFamily(in: context, withGhostPendingRow: true)

        let repository = FamilyRepository()
        repository.setModelContext(context)

        let viewModel = FamilyDashboardViewModel(
            familyRepository: repository,
            userRepository: UserRepository(),
            // The throwaway the view builds in `init`, then the environment's real one.
            authService: FirebaseAuthService()
        )
        viewModel.setAuthService(auth())
        viewModel.setModelContext(context)

        repository.families = [try #require(repository.getFamily(familyId: familyId))]
        repository.familyMembers[familyId] = repository.getMembers(familyId: familyId)
        repository.pendingRequests[familyId] = repository.getPendingRequests(familyId: familyId)

        #expect(viewModel.currentUserRole == .creator)
        #expect(viewModel.canManageFamily)
        // The dead uid really is in the set the refresh will hydrate.
        #expect(viewModel.pendingRequests.contains { $0.userId == deletedChildId })

        // The store answers the post-refresh re-read with nothing — a prune, a cache-served
        // members snapshot, or a SwiftData fetch that threw behind `try?`. Before the fix this
        // was published verbatim and the captain lost every control on the screen.
        repository.pruneLocalMembers(familyId: familyId, keepingUserIds: [])
        repository.pruneLocalPendingRequests(familyId: familyId, keepingRequestIds: [])
        try context.save()
        #expect(repository.getMembers(familyId: familyId).isEmpty)

        viewModel.refreshMemberIdentitiesIfNeeded()

        // `pendingRequests` is reassigned by the SAME block as `members` and is deliberately
        // NOT guarded (an emptied pending list is real news). Watching it go empty is how this
        // test knows the refresh actually completed, rather than passing because it never ran.
        try await waitUntil { viewModel.pendingRequests.isEmpty }
        #expect(viewModel.pendingRequests.isEmpty, "the refresh cycle did not complete in time")

        #expect(viewModel.canManageFamily, "an empty local re-read must never demote a captain")
        #expect(viewModel.currentUserRole == .creator)
        #expect(viewModel.members.contains { $0.userId == captainId })
    }

    // MARK: - 3. Family Settings — where the manage controls actually live

    @Test("Family Settings keeps its manage controls across a roster re-read that returns empty")
    func settingsSurvivesEmptyReRead() throws {
        let context = try makeContext()
        try seedFamily(in: context, withGhostPendingRow: false)

        let repository = FamilyRepository()
        repository.setModelContext(context)

        let viewModel = FamilySettingsViewModel(
            familyRepository: repository,
            authService: FirebaseAuthService()
        )
        viewModel.setAuthService(auth())
        viewModel.loadData(familyId: familyId)

        #expect(viewModel.isCaptainOrCreator)
        #expect(viewModel.canManageChildStatus)

        // `observeChildProjection` re-reads the roster on every projection publish. With the
        // rows gone it used to publish `[]`, and every control on the sheet disappeared.
        repository.pruneLocalMembers(familyId: familyId, keepingUserIds: [])
        try context.save()
        repository.applyChildMemberFlags([:], familyId: familyId)

        #expect(viewModel.isCaptainOrCreator, "an empty local re-read must never demote a captain")
        #expect(viewModel.canManageChildStatus)
    }

    // MARK: - 4. The ghost that poisoned the hydration set

    @Test("A pending row the server no longer lists is retired locally")
    func serverRetiredPendingRowIsPrunedLocally() throws {
        let context = try makeContext()
        try seedFamily(in: context, withGhostPendingRow: true)

        let repository = FamilyRepository()
        repository.setModelContext(context)

        #expect(repository.getPendingRequests(familyId: familyId).count == 1)

        // The authoritative read no longer carries the row — resolved elsewhere, swept by
        // FR-89, or deleted with its requester's account.
        repository.pruneLocalPendingRequests(familyId: familyId, keepingRequestIds: [])
        try context.save()

        #expect(
            repository.getPendingRequests(familyId: familyId).isEmpty,
            "a row the server has retired must not keep rendering with no identity"
        )
    }

    @Test("Pruning pending rows is scoped to the family and to still-live rows")
    func pruningPendingRowsIsScoped() throws {
        let context = try makeContext()
        try seedFamily(in: context, withGhostPendingRow: true)
        context.insert(
            PendingJoinRequest(
                requestId: "req-other-family",
                familyId: "fam-2",
                userId: "someone",
                requestedBy: "someone",
                method: .code
            )
        )
        context.insert(
            PendingJoinRequest(
                requestId: "req-resolved",
                familyId: familyId,
                userId: "resolved-user",
                requestedBy: "resolved-user",
                method: .code,
                status: .approved
            )
        )
        try context.save()

        let repository = FamilyRepository()
        repository.setModelContext(context)
        repository.pruneLocalPendingRequests(familyId: familyId, keepingRequestIds: [])
        try context.save()

        let all = try context.fetch(FetchDescriptor<PendingJoinRequest>()).map(\.requestId)
        #expect(all.contains("req-other-family"), "another family's rows are not this prune's business")
        #expect(all.contains("req-resolved"), "a resolved row is already invisible; leave its history")
        #expect(!all.contains("req-ghost"))
    }

    /// Polls until an async view-model cycle has visibly landed. Bounded above
    /// `FamilyCallable.deadline` so a wedged hydration read cannot make this hang.
    private func waitUntil(
        timeout: TimeInterval = 40,
        _ done: () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if done() { return }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }
}

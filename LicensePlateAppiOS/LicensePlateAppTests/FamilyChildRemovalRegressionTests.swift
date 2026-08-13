//
//  FamilyChildRemovalRegressionTests.swift
//  LicensePlateAppTests
//
//  Regressions for the three bugs owner testing found in F-8 step 7 (remove a flagged
//  child from the family). Each suite reproduces the broken behavior first, then pins
//  the fix.
//
//  A — parent roster showed a ghost member after a successful server removal.
//  B — child device did not react, then showed a phantom "waiting for approval".
//  C — after consent, queued discoveries sat behind an hour-long retry backoff.
//

import Foundation
import SwiftData
import Testing
import FirebaseFunctions
@testable import LicensePlateApp

// MARK: - BUG A: roster reconciliation

@MainActor
struct FamilyRosterReconciliationTests {

    private func makeRepository() throws -> (FamilyRepository, ModelContext) {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: AppMigrationPlan.self,
            configurations: [config]
        )
        let context = ModelContext(container)
        let repository = FamilyRepository()
        repository.setModelContext(context)
        return (repository, context)
    }

    private func seedFamily(_ context: ModelContext, memberIds: [String]) throws {
        context.insert(Family(familyId: "fam-1", name: "Hammers", creatorId: "creator"))
        context.insert(FamilyMember(familyId: "fam-1", userId: "creator", role: .creator))
        for id in memberIds {
            context.insert(FamilyMember(familyId: "fam-1", userId: id, role: .scout))
        }
        try context.save()
    }

    /// The bug: a members snapshot that no longer lists a member left the local row in
    /// place forever, so the roster kept showing someone the server had deleted — and
    /// every subsequent action on them failed with "Member not found".
    @Test func aMemberMissingFromTheSnapshotIsDeletedLocally() throws {
        let (repository, context) = try makeRepository()
        try seedFamily(context, memberIds: ["child-1", "scout-2"])
        #expect(repository.getMembers(familyId: "fam-1").count == 3)

        // Server state after the removal: child-1 is gone.
        repository.pruneLocalMembers(familyId: "fam-1", keepingUserIds: ["creator", "scout-2"])
        try context.save()

        let remaining = repository.getMembers(familyId: "fam-1").map(\.userId).sorted()
        #expect(remaining == ["creator", "scout-2"])
    }

    @Test func pruningIsScopedToOneFamily() throws {
        let (repository, context) = try makeRepository()
        try seedFamily(context, memberIds: ["child-1"])
        context.insert(FamilyMember(familyId: "fam-2", userId: "child-1", role: .scout))
        try context.save()

        repository.pruneLocalMembers(familyId: "fam-1", keepingUserIds: ["creator"])
        try context.save()

        #expect(repository.getMembers(familyId: "fam-1").map(\.userId) == ["creator"])
        #expect(repository.getMembers(familyId: "fam-2").map(\.userId) == ["child-1"])
    }

    /// The caller-side half: the roster must reconcile in the same motion as the
    /// callable, not a snapshot round-trip later.
    @Test func removingLocallyDropsTheRowAndItsChildFlag() throws {
        let (repository, context) = try makeRepository()
        try seedFamily(context, memberIds: ["child-1", "scout-2"])
        repository.applyChildMemberFlags(["child-1": true], familyId: "fam-1")
        #expect(repository.childMemberIds(familyId: "fam-1") == ["child-1"])

        repository.removeLocalMember(familyId: "fam-1", memberUserId: "child-1")

        #expect(repository.getMembers(familyId: "fam-1").map(\.userId).sorted() == ["creator", "scout-2"])
        #expect(repository.childMemberIds(familyId: "fam-1").isEmpty)
        #expect(repository.familyMembers["fam-1"]?.contains { $0.userId == "child-1" } == false)
    }

    /// The exact shape of the reported bug: the child flag cleared (badge vanished) while
    /// the row survived (member still listed). Both must move together.
    @Test func theBadgeAndTheRowCannotDisagreeAfterRemoval() throws {
        let (repository, context) = try makeRepository()
        try seedFamily(context, memberIds: ["child-1"])
        repository.applyChildMemberFlags(["child-1": true], familyId: "fam-1")

        // Snapshot after removal: the member doc is gone, so its isChild is gone too.
        repository.applyChildMemberFlags([:], familyId: "fam-1")
        repository.pruneLocalMembers(familyId: "fam-1", keepingUserIds: ["creator"])
        try context.save()

        let listed = repository.getMembers(familyId: "fam-1").map(\.userId)
        #expect(!listed.contains("child-1"))
        #expect(!repository.childMemberIds(familyId: "fam-1").contains("child-1"))
    }
}

struct FamilyMembershipRecoveryPolicyTests {

    private func callableError(_ code: FunctionsErrorCode, _ message: String) -> NSError {
        NSError(
            domain: FunctionsErrorDomain,
            code: code.rawValue,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }

    @Test func notFoundMeansTheMemberIsAlreadyGone() {
        #expect(
            FamilyMembershipRecoveryPolicy.isAlreadyRemoved(
                callableError(.notFound, "Member not found")
            )
        )
    }

    @Test func otherFailuresAreRealFailures() {
        #expect(!FamilyMembershipRecoveryPolicy.isAlreadyRemoved(callableError(.permissionDenied, "nope")))
        #expect(!FamilyMembershipRecoveryPolicy.isAlreadyRemoved(callableError(.failedPrecondition, "nope")))
        #expect(!FamilyMembershipRecoveryPolicy.isAlreadyRemoved(NSError(domain: "Other", code: 5)))
    }
}

@MainActor
struct FamilySettingsStaleRosterRecoveryTests {

    private func makeHarness() throws -> (FamilySettingsViewModel, MockFamilyChildStatusService, FamilyRepository) {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: AppMigrationPlan.self,
            configurations: [config]
        )
        let context = ModelContext(container)
        context.insert(Family(familyId: "fam-1", name: "Hammers", creatorId: "creator"))
        context.insert(FamilyMember(familyId: "fam-1", userId: "creator", role: .creator))
        context.insert(FamilyMember(familyId: "fam-1", userId: "captain", role: .captain))
        context.insert(FamilyMember(familyId: "fam-1", userId: "child-1", role: .scout))
        try context.save()

        let repository = FamilyRepository()
        repository.setModelContext(context)
        repository.applyChildMemberFlags(["child-1": true], familyId: "fam-1")

        let service = MockFamilyChildStatusService()
        let viewModel = FamilySettingsViewModel(
            familyRepository: repository,
            authService: FirebaseAuthService(),
            childStatusService: service,
            analytics: MockAnalyticsService(),
            currentYearProvider: { 2026 }
        )
        let auth = FirebaseAuthService()
        auth.currentUser = AppUser(id: "captain", userName: "captain", firebaseUID: "captain")
        viewModel.setAuthService(auth)
        viewModel.loadData(familyId: "fam-1")
        return (viewModel, service, repository)
    }

    private func notFound() -> NSError {
        NSError(
            domain: FunctionsErrorDomain,
            code: FunctionsErrorCode.notFound.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "Member not found"]
        )
    }

    /// Acting on a member the server no longer has must reconcile the list and explain
    /// itself — not surface the raw callable failure the manager cannot act on.
    @Test func aNotFoundCorrectionReconcilesInsteadOfAlertingRaw() async throws {
        let (viewModel, service, _) = try makeHarness()
        service.setChildStatusError = notFound()

        viewModel.beginCorrectChildStatus(
            FamilyChildMemberTarget(memberUserId: "child-1", displayName: "Sam")
        )
        viewModel.applyCorrection(reason: .flagSetInError)
        try await Task.sleep(nanoseconds: 60_000_000)

        #expect(!viewModel.members.contains { $0.userId == "child-1" })
        #expect(!viewModel.isChildMember(memberId: "child-1"))
        #expect(viewModel.errorMessage == "family.child.error.already_removed".localized)
        #expect(viewModel.errorMessage != "Member not found")
    }

    @Test func aNotFoundDeletionReconcilesTheRosterToo() async throws {
        let (viewModel, service, _) = try makeHarness()
        service.deletionError = notFound()

        viewModel.beginRemoveAndDeleteChildData(
            FamilyChildMemberTarget(memberUserId: "child-1", displayName: "Sam")
        )
        viewModel.advanceToFinalDeletionConfirmation()
        viewModel.confirmChildDataDeletion()
        try await Task.sleep(nanoseconds: 60_000_000)

        #expect(!viewModel.members.contains { $0.userId == "child-1" })
        #expect(viewModel.errorMessage == "family.child.error.already_removed".localized)
    }

    @Test func aSuccessfulDeletionDropsTheMemberImmediately() async throws {
        let (viewModel, _, _) = try makeHarness()

        viewModel.beginRemoveAndDeleteChildData(
            FamilyChildMemberTarget(memberUserId: "child-1", displayName: "Sam")
        )
        viewModel.advanceToFinalDeletionConfirmation()
        viewModel.confirmChildDataDeletion()
        try await Task.sleep(nanoseconds: 60_000_000)

        // No snapshot round-trip needed: the roster is already correct.
        #expect(!viewModel.members.contains { $0.userId == "child-1" })
        #expect(!viewModel.isChildMember(memberId: "child-1"))
        #expect(!viewModel.showErrorAlert)
    }

    @Test func realFailuresStillReportThemselves() async throws {
        let (viewModel, service, _) = try makeHarness()
        service.setChildStatusError = NSError(
            domain: FunctionsErrorDomain,
            code: FunctionsErrorCode.unavailable.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "server is down"]
        )

        viewModel.beginCorrectChildStatus(
            FamilyChildMemberTarget(memberUserId: "child-1", displayName: "Sam")
        )
        viewModel.applyCorrection(reason: .flagSetInError)
        try await Task.sleep(nanoseconds: 60_000_000)

        #expect(viewModel.errorMessage == "server is down")
        // The member is still there — nothing was reconciled away on a transient error.
        #expect(viewModel.members.contains { $0.userId == "child-1" })
    }
}

// MARK: - BUG B: membership transition on the child's device

struct FamilyMembershipTransitionPolicyTests {

    @Test func admissionIsAJoin() {
        #expect(
            FamilyMembershipTransitionPolicy.transition(previous: nil, current: "fam-1")
                == .joined(familyId: "fam-1")
        )
    }

    @Test func removalIsALeave() {
        #expect(
            FamilyMembershipTransitionPolicy.transition(previous: "fam-1", current: nil)
                == .left(previousFamilyId: "fam-1")
        )
    }

    @Test func unchangedMembershipIsNoEdge() {
        #expect(FamilyMembershipTransitionPolicy.transition(previous: nil, current: nil) == .none)
        #expect(FamilyMembershipTransitionPolicy.transition(previous: "f", current: "f") == .none)
    }

    @Test func emptyStringsAreTreatedAsNoMembership() {
        #expect(FamilyMembershipTransitionPolicy.transition(previous: "", current: nil) == .none)
        #expect(
            FamilyMembershipTransitionPolicy.transition(previous: "", current: "fam-1")
                == .joined(familyId: "fam-1")
        )
    }

    @Test func onlyAdmissionEdgesResumeGameplaySync() {
        #expect(FamilyMembershipTransition.joined(familyId: "f").resumesGameplaySync)
        #expect(FamilyMembershipTransition.switched(from: "a", to: "b").resumesGameplaySync)
        #expect(!FamilyMembershipTransition.left(previousFamilyId: "f").resumesGameplaySync)
        #expect(!FamilyMembershipTransition.none.resumesGameplaySync)
    }
}

@MainActor
struct FamilyInviteConsumptionStoreTests {

    private func makeStore() -> FamilyInviteConsumptionStore {
        let suite = "FamilyInviteConsumptionStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return FamilyInviteConsumptionStore(defaults: defaults)
    }

    @Test func recordsAndReportsConsumedInvites() {
        let store = makeStore()
        #expect(store.consumedInviteIds.isEmpty)
        store.markConsumed(inviteIds: ["i-1", "i-2", ""])
        #expect(store.consumedInviteIds == ["i-1", "i-2"])
        #expect(store.isConsumed("i-1"))
        #expect(!store.isConsumed("i-3"))
    }

    @Test func hardSignOutClearsTheSlate() {
        let store = makeStore()
        store.markConsumed(inviteIds: ["i-1"])
        store.clear()
        #expect(store.consumedInviteIds.isEmpty)
    }
}

@MainActor
struct FamilyMembershipTransitionServiceTests {

    @MainActor
    private final class World {
        var invitesByFamily: [String: [String]] = [:]
        private(set) var consumed: [String] = []
        private(set) var resumeCount = 0

        func makeService() -> FamilyMembershipTransitionService {
            FamilyMembershipTransitionService(
                dependencies: .init(
                    acceptedInviteIds: { [weak self] familyId in
                        self?.invitesByFamily[familyId] ?? []
                    },
                    markInvitesConsumed: { [weak self] ids in
                        self?.consumed.append(contentsOf: ids)
                    },
                    resumeGameplaySync: { [weak self] in
                        self?.resumeCount += 1
                    }
                )
            )
        }
    }

    @Test func theFirstObservedValueOnlySeedsTheBaseline() async {
        // A membership that already existed at launch is not a fresh admission.
        let world = World()
        world.invitesByFamily["fam-1"] = ["i-1"]
        let service = world.makeService()

        #expect(service.note(activeFamilyId: "fam-1") == .none)
        try? await Task.sleep(nanoseconds: 30_000_000)
        #expect(world.resumeCount == 0)
        #expect(world.consumed.isEmpty)
    }

    /// BUG C's trigger: admission must resume the gameplay queue, not wait for a
    /// debounce that skips backed-off rows.
    @Test func admissionConsumesTheInviteAndResumesSync() async {
        let world = World()
        world.invitesByFamily["fam-1"] = ["i-1"]
        let service = world.makeService()
        service.seed(familyId: nil)

        #expect(service.note(activeFamilyId: "fam-1") == .joined(familyId: "fam-1"))
        try? await Task.sleep(nanoseconds: 60_000_000)
        #expect(world.consumed == ["i-1"])
        #expect(world.resumeCount == 1)
    }

    /// BUG B: removal is the opposite edge — nothing resumes, and the invite consumed at
    /// admission stays consumed so no phantom "waiting for approval" can come back.
    @Test func removalResumesNothingAndKeepsTheInviteConsumed() async {
        let world = World()
        world.invitesByFamily["fam-1"] = ["i-1"]
        let service = world.makeService()
        service.seed(familyId: nil)
        _ = service.note(activeFamilyId: "fam-1")
        try? await Task.sleep(nanoseconds: 60_000_000)

        #expect(service.note(activeFamilyId: nil) == .left(previousFamilyId: "fam-1"))
        try? await Task.sleep(nanoseconds: 30_000_000)
        #expect(world.resumeCount == 1) // unchanged by the removal
        #expect(world.consumed == ["i-1"])
    }

    @Test func repeatedIdenticalReadsAreNoEdges() async {
        let world = World()
        world.invitesByFamily["fam-1"] = ["i-1"]
        let service = world.makeService()
        service.seed(familyId: nil)

        _ = service.note(activeFamilyId: "fam-1")
        _ = service.note(activeFamilyId: "fam-1")
        _ = service.note(activeFamilyId: "fam-1")
        try? await Task.sleep(nanoseconds: 60_000_000)
        #expect(world.resumeCount == 1)
        #expect(world.consumed == ["i-1"])
    }

    @Test func switchingFamiliesIsAFreshAdmission() async {
        let world = World()
        world.invitesByFamily["fam-2"] = ["i-2"]
        let service = world.makeService()
        service.seed(familyId: "fam-1")

        #expect(service.note(activeFamilyId: "fam-2") == .switched(from: "fam-1", to: "fam-2"))
        try? await Task.sleep(nanoseconds: 60_000_000)
        #expect(world.consumed == ["i-2"])
        #expect(world.resumeCount == 1)
    }

    @Test func resetRestoresTheUnseededState() async {
        let world = World()
        let service = world.makeService()
        service.seed(familyId: nil)
        service.reset()
        // First value after a reset seeds again instead of firing an edge.
        #expect(service.note(activeFamilyId: "fam-1") == .none)
        try? await Task.sleep(nanoseconds: 30_000_000)
        #expect(world.resumeCount == 0)
    }
}

// MARK: - BUG C: consent resume must not wait out the child-restriction backoff

@MainActor
struct ChildConsentSyncResumeTests {

    private func makeQueue() throws -> SyncQueueRepository {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: AppMigrationPlan.self,
            configurations: [config]
        )
        let repository = SyncQueueRepository()
        repository.setModelContext(ModelContext(container))
        return repository
    }

    private func enqueueGameplay(_ repository: SyncQueueRepository, eventId: String) throws -> String {
        let id = UUID().uuidString
        try repository.enqueue(
            SyncQueueItem(
                id: id,
                kind: .gameplayEvent,
                state: .pending,
                attemptCount: 0,
                createdAt: .now,
                updatedAt: .now,
                payloadSessionId: UUID().uuidString,
                payloadEventId: eventId
            )
        )
        return id
    }

    /// The bug, reproduced: F-6 parks a child-restriction rejection an hour out. Until
    /// then `fetchFailedRetryDue()` skips it, so the discoveries a child made before
    /// joining stay on the device long after consent.
    @Test func aHeldItemIsInvisibleToTheNormalFlushForAnHour() throws {
        let repository = try makeQueue()
        let id = try enqueueGameplay(repository, eventId: "evt-1")

        // What SyncCoordinator does on `unconsented_child`.
        try repository.markFailed(id: id, nextRetryAt: Date().addingTimeInterval(3600))

        #expect(try repository.fetchPending().isEmpty)
        #expect(try repository.fetchFailedRetryDue().isEmpty)
        #expect(try repository.hasPendingOrRetryDueGameplayItems() == false)
    }

    @Test func clearingTheBackoffMakesHeldItemsDrainImmediately() throws {
        let repository = try makeQueue()
        let first = try enqueueGameplay(repository, eventId: "evt-1")
        let second = try enqueueGameplay(repository, eventId: "evt-2")
        try repository.markFailed(id: first, nextRetryAt: Date().addingTimeInterval(3600))
        try repository.markFailed(id: second, nextRetryAt: Date().addingTimeInterval(3600))
        #expect(try repository.fetchFailedRetryDue().isEmpty)

        let unblocked = try repository.clearGameplayRetryBackoff()

        #expect(unblocked == 2)
        #expect(try repository.fetchFailedRetryDue().count == 2)
        #expect(try repository.hasPendingOrRetryDueGameplayItems())
    }

    @Test func clearingLeavesPendingAndCompletedRowsAlone() throws {
        let repository = try makeQueue()
        _ = try enqueueGameplay(repository, eventId: "evt-pending")
        let held = try enqueueGameplay(repository, eventId: "evt-held")
        try repository.markFailed(id: held, nextRetryAt: Date().addingTimeInterval(3600))
        let done = try enqueueGameplay(repository, eventId: "evt-done")
        try repository.markCompleted(id: done)

        #expect(try repository.clearGameplayRetryBackoff() == 1)
        #expect(try repository.fetchPending().count == 1)
        #expect(try repository.fetchFailedRetryDue().map(\.payloadEventId) == ["evt-held"])
    }

    @Test func clearingIsIdempotentAndCheapWhenNothingIsHeld() throws {
        let repository = try makeQueue()
        _ = try enqueueGameplay(repository, eventId: "evt-1")
        #expect(try repository.clearGameplayRetryBackoff() == 0)
        #expect(try repository.clearGameplayRetryBackoff() == 0)
    }

    @Test func userProfileRowsKeepTheirOwnBackoff() throws {
        let repository = try makeQueue()
        let id = UUID().uuidString
        try repository.enqueue(
            SyncQueueItem(
                id: id,
                kind: .userProfile,
                state: .pending,
                attemptCount: 0,
                createdAt: .now,
                updatedAt: .now,
                payloadData: "uid".data(using: .utf8)
            )
        )
        try repository.markFailed(id: id, nextRetryAt: Date().addingTimeInterval(3600))

        // The consent resume is a gameplay concern; profile retries are untouched.
        #expect(try repository.clearGameplayRetryBackoff() == 0)
        #expect(try repository.fetchFailedRetryDue().isEmpty)
    }

    /// End to end for the reported symptom: a child's queued discoveries are held by the
    /// FR-28 gate, then admission (the `joined` edge) both clears the backoff and asks
    /// for a flush — so they drain in the next pass, not in an hour.
    @Test func admissionUnblocksTheQueuedDiscoveryBacklog() async throws {
        let repository = try makeQueue()
        let first = try enqueueGameplay(repository, eventId: "region_found-1")
        let second = try enqueueGameplay(repository, eventId: "region_found-2")
        try repository.markFailed(id: first, nextRetryAt: Date().addingTimeInterval(3600))
        try repository.markFailed(id: second, nextRetryAt: Date().addingTimeInterval(3600))

        var flushed = false
        let service = FamilyMembershipTransitionService(
            dependencies: .init(
                acceptedInviteIds: { _ in [] },
                markInvitesConsumed: { _ in },
                resumeGameplaySync: {
                    // Exactly what SyncCoordinator.resumeGameplaySyncAfterConsent does
                    // before draining.
                    try? repository.clearGameplayRetryBackoff()
                    flushed = true
                }
            )
        )
        service.seed(familyId: nil)

        #expect(try repository.fetchFailedRetryDue().isEmpty)
        _ = service.note(activeFamilyId: "fam-1")
        try await Task.sleep(nanoseconds: 80_000_000)

        #expect(flushed)
        #expect(try repository.fetchFailedRetryDue().count == 2)
        #expect(try repository.hasPendingOrRetryDueGameplayItems())
    }
}

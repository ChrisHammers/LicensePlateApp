//
//  FamilyPendingApprovalsChildDeclarationTests.swift
//  LicensePlateAppTests
//
//  COPPA F-8 (FR-1/FR-25): the approval-time child declaration. The point of these
//  tests is that the UI refuses exactly what the server refuses — a manager must never
//  reach a raw callable rejection.
//

import Foundation
import SwiftData
import Testing
import FirebaseFunctions
@testable import LicensePlateApp

@MainActor
struct FamilyPendingApprovalsChildDeclarationTests {

    @MainActor
    private final class World {
        var resolvedFlags: [String: Bool?] = [:]
        var respondError: Error?
        private(set) var respondCalls: [(familyId: String, requestId: String, approve: Bool, declaration: ChildApprovalDraft?)] = []

        func dependencies() -> FamilyPendingApprovalsViewModel.Dependencies {
            FamilyPendingApprovalsViewModel.Dependencies(
                resolveIsChildAccount: { [weak self] uid in
                    self?.resolvedFlags[uid] ?? nil
                },
                respondToPendingRequest: { [weak self] familyId, requestId, approve, declaration in
                    self?.respondCalls.append((familyId, requestId, approve, declaration))
                    if let error = self?.respondError { throw error }
                },
                // Hermetic: the post-response refresh reads the local store, never the
                // network. The live seam is `FamilyRepository.fetchPendingRequests`.
                fetchPendingRequests: { _ in throw CancellationError() }
            )
        }

        var respondCallCount: Int { respondCalls.count }
    }

    private struct Harness {
        let viewModel: FamilyPendingApprovalsViewModel
        let world: World
        let analytics: MockAnalyticsService
        let request: PendingJoinRequest
    }

    private func makeHarness(
        targetFlag: Bool?? = .some(false),
        requestId: String = "req-1",
        targetUserId: String = "target-1"
    ) throws -> Harness {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: AppMigrationPlan.self,
            configurations: [config]
        )
        let context = ModelContext(container)
        let familyId = "fam-1"

        let request = PendingJoinRequest(
            requestId: requestId,
            familyId: familyId,
            userId: targetUserId,
            requestedBy: targetUserId,
            method: .code
        )
        context.insert(request)
        try context.save()

        let repository = FamilyRepository()
        repository.setModelContext(context)

        let world = World()
        if let targetFlag {
            world.resolvedFlags[targetUserId] = targetFlag
        }

        let analytics = MockAnalyticsService()
        let viewModel = FamilyPendingApprovalsViewModel(
            familyId: familyId,
            familyRepository: repository,
            userRepository: UserRepository(),
            analytics: analytics,
            dependencies: world.dependencies()
        )
        let authService = FirebaseAuthService()
        authService.currentUser = AppUser(id: "captain", userName: "captain", firebaseUID: "captain")
        viewModel.configure(authService: authService, modelContext: context)
        viewModel.onAppear()

        return Harness(viewModel: viewModel, world: world, analytics: analytics, request: request)
    }

    // MARK: - Adult target (FR-1)

    @Test func adultTargetApprovesWithNoDeclarationCeremony() async throws {
        let harness = try makeHarness(targetFlag: .some(false))
        await harness.viewModel.resolveChildTargetStates()

        #expect(harness.viewModel.childTargetState(for: harness.request) == .notChild)
        #expect(harness.viewModel.canApprove(request: harness.request))
        #expect(!harness.viewModel.showsConsentBlock(for: harness.request))

        _ = await harness.viewModel.approve(request: harness.request)
        #expect(harness.world.respondCallCount == 1)
        #expect(harness.world.respondCalls.last?.declaration?.isChild == false)
    }

    @Test func togglingChildOnBlocksApprovalUntilBothAcknowledgments() async throws {
        let harness = try makeHarness(targetFlag: .some(false))
        await harness.viewModel.resolveChildTargetStates()
        let vm = harness.viewModel

        vm.setIsChild(true, for: harness.request)
        #expect(vm.showsConsentBlock(for: harness.request))
        #expect(!vm.canApprove(request: harness.request))

        vm.setConsentAcknowledged(true, for: harness.request)
        #expect(!vm.canApprove(request: harness.request))

        vm.setGuardianAffirmed(true, for: harness.request)
        #expect(vm.canApprove(request: harness.request))

        vm.setExpectedAgeOutYear(2031, for: harness.request)
        _ = await vm.approve(request: harness.request)

        let declaration = try #require(harness.world.respondCalls.last?.declaration)
        #expect(declaration.isChild == true)
        #expect(declaration.consent.consentAcknowledged)
        #expect(declaration.consent.guardianAffirmed)
        #expect(declaration.consent.expectedAgeOutYear == 2031)
    }

    @Test func approveIsARefusedNoOpWhileTheDeclarationIsIncomplete() async throws {
        let harness = try makeHarness(targetFlag: .some(false))
        await harness.viewModel.resolveChildTargetStates()
        harness.viewModel.setIsChild(true, for: harness.request)

        let approved = await harness.viewModel.approve(request: harness.request)
        #expect(approved == false)
        #expect(harness.world.respondCallCount == 0)
    }

    @Test func turningTheChildToggleBackOffDiscardsCapturedConsent() async throws {
        let harness = try makeHarness(targetFlag: .some(false))
        await harness.viewModel.resolveChildTargetStates()
        let vm = harness.viewModel

        vm.setIsChild(true, for: harness.request)
        vm.setConsentAcknowledged(true, for: harness.request)
        vm.setGuardianAffirmed(true, for: harness.request)
        vm.setIsChild(false, for: harness.request)
        vm.setIsChild(true, for: harness.request)

        #expect(!vm.canApprove(request: harness.request))
        #expect(vm.childDraft(for: harness.request).consent == ChildConsentDraft())
    }

    // MARK: - Sticky target (FR-25)

    @Test func stickyTargetForcesAnExplicitChoiceBeforeApproval() async throws {
        let harness = try makeHarness(targetFlag: .some(true))
        await harness.viewModel.resolveChildTargetStates()
        let vm = harness.viewModel

        #expect(vm.childTargetState(for: harness.request) == .alreadyChild)
        #expect(vm.childDraft(for: harness.request).isChild == nil)
        #expect(!vm.canApprove(request: harness.request))

        let approved = await vm.approve(request: harness.request)
        #expect(approved == false)
        #expect(harness.world.respondCallCount == 0)
    }

    /// FR-66(b): a bare "no" on a flagged target used to approve on the spot. It is now the
    /// start of the correction block, not the end of the decision — the server would refuse
    /// this payload, so the UI must refuse it first.
    @Test func stickyTargetClearedWithoutEvidenceCannotBeApproved() async throws {
        let harness = try makeHarness(targetFlag: .some(true))
        await harness.viewModel.resolveChildTargetStates()
        let vm = harness.viewModel

        vm.setIsChild(false, for: harness.request)
        #expect(!vm.canApprove(request: harness.request))

        let approved = await vm.approve(request: harness.request)
        #expect(approved == false)
        #expect(harness.world.respondCallCount == 0)
    }

    @Test func stickyTargetApprovedAsNotAChildRecordsTheGuardianCorrection() async throws {
        let harness = try makeHarness(targetFlag: .some(true))
        await harness.viewModel.resolveChildTargetStates()
        let vm = harness.viewModel

        vm.setIsChild(false, for: harness.request)
        vm.setCorrectionReason(.childTurned13, for: harness.request)
        vm.setCorrectionAcknowledged(true, for: harness.request)
        vm.setCorrectionGuardianAffirmed(true, for: harness.request)
        #expect(vm.canApprove(request: harness.request))

        _ = await vm.approve(request: harness.request)
        let declaration = harness.world.respondCalls.last?.declaration
        #expect(declaration?.isChild == false)
        #expect(declaration?.correction.reason == .childTurned13)
        #expect(declaration?.correction.statusAcknowledged == true)
        #expect(declaration?.correction.guardianAffirmed == true)
        // FR-66(b): the analytics slug is the manager's chosen reason, matching the server's
        // consent-correction audit row, rather than a fixed "new_guardian_cleared".
        #expect(harness.analytics.loggedEvents.contains { event in
            if case .familyChildStatusCorrected(let reason) = event {
                return reason == "child_turned_13"
            }
            return false
        })
    }

    @Test func answeringYesAfterStartingACorrectionDiscardsTheCorrectionDraft() async throws {
        let harness = try makeHarness(targetFlag: .some(true))
        await harness.viewModel.resolveChildTargetStates()
        let vm = harness.viewModel

        vm.setIsChild(false, for: harness.request)
        vm.setCorrectionReason(.flagSetInError, for: harness.request)
        vm.setCorrectionAcknowledged(true, for: harness.request)

        vm.setIsChild(true, for: harness.request)
        #expect(vm.childDraft(for: harness.request).correction == ChildCorrectionDraft())
    }

    @Test func stickyTargetApprovedAsAChildLogsTheApprovalSource() async throws {
        let harness = try makeHarness(targetFlag: .some(true))
        await harness.viewModel.resolveChildTargetStates()
        let vm = harness.viewModel

        vm.setIsChild(true, for: harness.request)
        vm.setConsentAcknowledged(true, for: harness.request)
        vm.setGuardianAffirmed(true, for: harness.request)
        _ = await vm.approve(request: harness.request)

        #expect(harness.analytics.loggedEvents.contains { event in
            if case .familyChildStatusSet(let source) = event { return source == "approval" }
            return false
        })
        #expect(harness.analytics.loggedEvents.contains { event in
            if case .familyChildConsentAcknowledged = event { return true }
            return false
        })
    }

    // MARK: - Unreadable target (FR-12 consequence)

    @Test func unreadableTargetIsNeverAssumedToBeAnAdult() async throws {
        // FR-12 denies peer reads of a non-family child's user doc — exactly the case
        // where an explicit answer matters most.
        let harness = try makeHarness(targetFlag: .some(nil))
        await harness.viewModel.resolveChildTargetStates()

        #expect(harness.viewModel.childTargetState(for: harness.request) == .unknown)
        #expect(!harness.viewModel.canApprove(request: harness.request))
    }

    @Test func answeringTheUnknownTargetUnblocksApproval() async throws {
        let harness = try makeHarness(targetFlag: .some(nil))
        await harness.viewModel.resolveChildTargetStates()
        harness.viewModel.setIsChild(false, for: harness.request)
        #expect(harness.viewModel.canApprove(request: harness.request))
    }

    @Test func aLateFlagDiscoveryReSeedsAnUntouchedDraft() async throws {
        let harness = try makeHarness(targetFlag: .some(false))
        await harness.viewModel.resolveChildTargetStates()
        #expect(harness.viewModel.childDraft(for: harness.request).isChild == false)

        // The target gets flagged between refreshes.
        harness.world.resolvedFlags["target-1"] = true
        await harness.viewModel.resolveChildTargetStates()

        #expect(harness.viewModel.childTargetState(for: harness.request) == .alreadyChild)
        #expect(harness.viewModel.childDraft(for: harness.request).isChild == nil)
        #expect(!harness.viewModel.canApprove(request: harness.request))
    }

    @Test func aManagersOwnAnswerSurvivesAReResolution() async throws {
        let harness = try makeHarness(targetFlag: .some(false))
        await harness.viewModel.resolveChildTargetStates()
        harness.viewModel.setIsChild(true, for: harness.request)
        harness.viewModel.setConsentAcknowledged(true, for: harness.request)

        await harness.viewModel.resolveChildTargetStates()
        #expect(harness.viewModel.childDraft(for: harness.request).isChild == true)
        #expect(harness.viewModel.childDraft(for: harness.request).consent.consentAcknowledged)
    }

    // MARK: - Server rejection race (FR-25)

    @Test func theServersStickyRejectionBecomesAnExplicitChoiceNotAnError() async throws {
        // The client read said "not a child" (or could not read at all) and the server
        // disagreed. The manager must see the child question, never a raw error.
        let harness = try makeHarness(targetFlag: .some(false))
        await harness.viewModel.resolveChildTargetStates()
        harness.world.respondError = NSError(
            domain: FunctionsErrorDomain,
            code: FunctionsErrorCode.failedPrecondition.rawValue,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "This member is marked as a child; approval must explicitly declare isChild"
            ]
        )

        let approved = await harness.viewModel.approve(request: harness.request)
        #expect(approved == false)
        #expect(harness.viewModel.showError == false)
        #expect(harness.viewModel.errorMessage == nil)
        #expect(harness.viewModel.childTargetState(for: harness.request) == .alreadyChild)
        #expect(harness.viewModel.childDraft(for: harness.request).isChild == nil)
    }

    @Test func otherFailuresStillSurfaceAsErrors() async throws {
        let harness = try makeHarness(targetFlag: .some(false))
        await harness.viewModel.resolveChildTargetStates()
        harness.world.respondError = NSError(
            domain: FunctionsErrorDomain,
            code: FunctionsErrorCode.unavailable.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "server is down"]
        )

        _ = await harness.viewModel.approve(request: harness.request)
        #expect(harness.viewModel.showError)
        #expect(harness.viewModel.errorMessage == "server is down")
    }

    // MARK: - Decline

    @Test func decliningNeverCarriesADeclarationOrChildAnalytics() async throws {
        let harness = try makeHarness(targetFlag: .some(true))
        await harness.viewModel.resolveChildTargetStates()

        _ = await harness.viewModel.decline(request: harness.request)
        let call = try #require(harness.world.respondCalls.last)
        #expect(call.approve == false)
        #expect(call.declaration == nil)
        #expect(!harness.analytics.loggedEvents.contains { event in
            if case .familyChildStatusSet = event { return true }
            if case .familyChildStatusCorrected = event { return true }
            return false
        })
    }
}

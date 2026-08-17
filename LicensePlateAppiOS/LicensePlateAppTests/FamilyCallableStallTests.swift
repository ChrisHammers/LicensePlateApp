//
//  FamilyCallableStallTests.swift
//  LicensePlateAppTests
//
//  THE HANG CLUSTER — device pass 2026-08-17.
//
//  Approving a pending child stalled ~60s and failed "Deadline Exceeded". Declining the same
//  row failed. Creating a new share code timed out and never produced a code. Every one of
//  them succeeded instantly after killing and relaunching the app — and `firebase
//  functions:log` recorded NO invocation for any stuck attempt, against a slowest-ever real
//  invocation of 6.7s. The request never left the device.
//
//  Two independent client defects made that a DEAD SCREEN rather than one slow tap, and both
//  are pinned here:
//
//    1. Nothing bounded a family callable. The only timer in play was the Functions SDK's own
//       ~60s fetcher timeout, and the SDK's async `call` is a continuation wrapper with no
//       cancellation support — so a caller that hit the pre-network stall waited on it with no
//       way out. `FamilyCallable.bounded` now abandons the await at 25s.
//    2. The approvals surface serialised itself on ONE `busyRequestId`, and released it only
//       after a post-success reconcile of unbounded Firestore reads. So a second row silently
//       no-op'd while the first was in flight, and a SUCCESSFUL approve could leave its own row
//       disabled indefinitely.
//

import Foundation
import SwiftData
import Testing
import FirebaseFunctions
@testable import LicensePlateApp

@MainActor
struct FamilyCallableStallTests {

    /// An operation that never completes on its own — the 2026-08-17 stall, reproduced without
    /// a poisoned device. Resumed at the end of each test so nothing is left parked.
    @MainActor
    private final class NeverReturns {
        private var continuation: CheckedContinuation<Void, Never>?
        private(set) var started = false

        func run() async {
            started = true
            await withCheckedContinuation { continuation in
                self.continuation = continuation
            }
        }

        func release() {
            continuation?.resume()
            continuation = nil
        }
    }

    // MARK: - The deadline

    @Test("A callable that never returns does not hold its caller")
    func boundedAbandonsAStalledCall() async throws {
        let stuck = NeverReturns()

        let start = Date()
        await #expect(throws: (any Error).self) {
            try await FamilyCallable.bounded(name: "approveFamilyJoinRequest_CaptainStep", seconds: 0.2) {
                await stuck.run()
            }
        }

        // The caller came back on OUR clock, not the SDK's 60s one.
        #expect(Date().timeIntervalSince(start) < 5)
        #expect(stuck.started)
        stuck.release()
    }

    @Test("The abandon error is retryable, localized, and marked as client-side")
    func stalledErrorIsActionable() async throws {
        let stuck = NeverReturns()
        var captured: Error?
        do {
            _ = try await FamilyCallable.bounded(name: "createShareCode", seconds: 0.2) {
                await stuck.run()
            }
        } catch {
            captured = error
        }
        stuck.release()

        let error = try #require(captured)
        #expect(FamilyCallable.isStalled(error))

        let nsError = error as NSError
        #expect(nsError.domain == FunctionsErrorDomain)
        #expect(nsError.code == FunctionsErrorCode.deadlineExceeded.rawValue)
        // Real copy, not the raw key, and never the bare "unavailable" claim: an abandoned call
        // may still have landed, so the message says "try again", not "it failed".
        #expect(!nsError.localizedDescription.isEmpty)
        #expect(nsError.localizedDescription != "family.callable.error.timed_out")
    }

    @Test("A genuine server deadline is still mapped; only the client abandon passes through")
    func errorMappersDistinguishTheTwo() async throws {
        let stuck = NeverReturns()
        var clientStall: Error?
        do {
            _ = try await FamilyCallable.bounded(name: "setFamilyMemberChildStatus", seconds: 0.2) {
                await stuck.run()
            }
        } catch {
            clientStall = error
        }
        stuck.release()

        let stalled = try #require(clientStall)
        let stalledMessage = (stalled as NSError).localizedDescription
        #expect(
            (FamilyRepository.childStatusCallableError(stalled) as NSError).localizedDescription
                == stalledMessage
        )
        #expect(
            (FamilyRepository.userFacingCallableError(stalled) as NSError).localizedDescription
                == stalledMessage
        )

        // The server's own deadline still gets the "server unavailable" copy.
        let serverDeadline = NSError(
            domain: FunctionsErrorDomain,
            code: FunctionsErrorCode.deadlineExceeded.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "DEADLINE_EXCEEDED"]
        )
        #expect(!FamilyCallable.isStalled(serverDeadline))
        #expect(
            (FamilyRepository.childStatusCallableError(serverDeadline) as NSError)
                .localizedDescription == "family.child.error.unavailable".localized
        )
    }

    @Test("A completed call is unaffected by the watchdog")
    func boundedPassesThroughASuccess() async throws {
        let value = try await FamilyCallable.bounded(name: "createFamily", seconds: 5) { 42 }
        #expect(value == 42)
    }

    @Test("A thrown error is delivered as itself, not as a timeout")
    func boundedPropagatesTheRealFailure() async throws {
        struct Boom: Error {}
        var captured: Error?
        do {
            _ = try await FamilyCallable.bounded(name: "removeFamilyMember", seconds: 5) {
                throw Boom()
            }
        } catch {
            captured = error
        }
        #expect(captured is Boom)
        #expect(!FamilyCallable.isStalled(try #require(captured)))
    }

    // MARK: - The surface no longer serialises on one row

    private func makeViewModel(
        requestIds: [String],
        dependencies: FamilyPendingApprovalsViewModel.Dependencies
    ) throws -> FamilyPendingApprovalsViewModel {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: AppMigrationPlan.self,
            configurations: [config]
        )
        let context = ModelContext(container)
        for requestId in requestIds {
            context.insert(
                PendingJoinRequest(
                    requestId: requestId,
                    familyId: "fam-1",
                    userId: "user-\(requestId)",
                    requestedBy: "user-\(requestId)",
                    method: .code
                )
            )
        }
        try context.save()

        let repository = FamilyRepository()
        repository.setModelContext(context)
        let viewModel = FamilyPendingApprovalsViewModel(
            familyId: "fam-1",
            familyRepository: repository,
            analytics: MockAnalyticsService(),
            dependencies: dependencies
        )
        viewModel.configure(authService: FirebaseAuthService(), modelContext: context)
        viewModel.onAppear()
        return viewModel
    }

    @Test("A stalled row does not block a decision on a different row")
    func rowsAreIndependent() async throws {
        let stuck = NeverReturns()
        var resolved: [String] = []

        let deps = FamilyPendingApprovalsViewModel.Dependencies(
            resolveIsChildAccount: { _ in false },
            respondToPendingRequest: { _, requestId, _, _ in
                if requestId == "req-stuck" {
                    await stuck.run()
                } else {
                    resolved.append(requestId)
                }
            },
            fetchPendingRequests: { _ in throw CancellationError() }
        )
        let viewModel = try makeViewModel(requestIds: ["req-stuck", "req-other"], dependencies: deps)
        let stuckRequest = try #require(
            viewModel.pendingRequests.first { $0.requestId == "req-stuck" }
        )
        let otherRequest = try #require(
            viewModel.pendingRequests.first { $0.requestId == "req-other" }
        )

        // Row A goes in flight and stays there.
        let inFlight = Task { await viewModel.decline(request: stuckRequest) }
        while !stuck.started { await Task.yield() }
        #expect(viewModel.isBusy(requestId: "req-stuck", kind: .decline))

        // Row B must still reach the server. Before the fix this returned false without
        // calling anything, with the button still looking enabled.
        let accepted = await viewModel.decline(request: otherRequest)

        #expect(accepted)
        #expect(resolved == ["req-other"])
        // ...and row B released its own state without touching row A's.
        #expect(!viewModel.isBusy(requestId: "req-other", kind: .decline))
        #expect(viewModel.isBusy(requestId: "req-stuck", kind: .decline))

        stuck.release()
        _ = await inFlight.value
        #expect(!viewModel.isProcessing)
    }

    @Test("A failed decision releases its row instead of wedging it")
    func failureReleasesTheRow() async throws {
        struct Boom: Error {}
        let deps = FamilyPendingApprovalsViewModel.Dependencies(
            resolveIsChildAccount: { _ in false },
            respondToPendingRequest: { _, _, _, _ in throw Boom() },
            fetchPendingRequests: { _ in throw CancellationError() }
        )
        let viewModel = try makeViewModel(requestIds: ["req-1"], dependencies: deps)
        let request = try #require(viewModel.pendingRequests.first)

        _ = await viewModel.decline(request: request)

        #expect(!viewModel.isProcessing)
        #expect(!viewModel.isRowDisabled(requestId: "req-1"))
        // A second attempt is genuinely possible — the wedge was that it was not.
        #expect(viewModel.showError)
    }

    /// THE "restart fixes it" REGRESSION. The busy flag used to live in a `defer`, so it was
    /// released only after the whole function returned — reconcile included. The reconcile is a
    /// chain of Firestore reads with no client deadline, so a SUCCESSFUL approve whose reconcile
    /// never came back left its row disabled for the life of the process.
    @Test("The row is released before the post-decision reconcile is awaited")
    func busyStateIsReleasedBeforeReconcile() async throws {
        var busyDuringReconcile: [String: InviteBusyKind]?
        var viewModelRef: FamilyPendingApprovalsViewModel?

        let deps = FamilyPendingApprovalsViewModel.Dependencies(
            resolveIsChildAccount: { _ in false },
            respondToPendingRequest: { _, _, _, _ in },
            fetchPendingRequests: { _ in
                busyDuringReconcile = viewModelRef?.busyKindByRequestId
                return []
            }
        )
        let viewModel = try makeViewModel(requestIds: ["req-1"], dependencies: deps)
        viewModelRef = viewModel
        let request = try #require(viewModel.pendingRequests.first)

        #expect(await viewModel.decline(request: request))

        #expect(busyDuringReconcile == [:])
        #expect(!viewModel.isProcessing)
    }
}

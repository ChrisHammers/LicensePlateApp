//
//  FamilyPendingRequestLifetimeTests.swift
//  LicensePlateAppTests
//
//  Device pass 2026-08-17: a share code expired and its pending row stayed exactly as it was —
//  still approvable, with nothing on screen to say the window had moved. The server fix gives
//  the row its own 7-day decision window, decoupled from the code's 15-minute redemption
//  window (`functions/src/pendingJoinRequestExpiry.ts` carries the argument). This is the
//  captain's half: the deadline is visible from the start, and past it the row goes terminal
//  rather than offering an Approve the server refuses.
//

import Foundation
import SwiftData
import Testing
@testable import LicensePlateApp

@MainActor
struct FamilyPendingRequestLifetimeTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func created(daysAgo: Double) -> Date {
        now.addingTimeInterval(-daysAgo * 24 * 60 * 60)
    }

    // MARK: - The window itself

    @Test("The redemption window is not the decision window")
    func aRowOutlivesItsFifteenMinuteCode() {
        // One hour old: the code and the invite behind it lapsed 45 minutes ago.
        #expect(
            FamilyPendingRequestLifetime.remaining(createdAt: created(daysAgo: 1.0 / 24), now: now)
                == .days(6)
        )
        #expect(!FamilyPendingRequestLifetime.isExpired(createdAt: created(daysAgo: 1.0 / 24), now: now))
    }

    @Test("Seven days is the boundary")
    func boundary() {
        #expect(!FamilyPendingRequestLifetime.isExpired(createdAt: created(daysAgo: 6.9), now: now))
        #expect(FamilyPendingRequestLifetime.isExpired(createdAt: created(daysAgo: 7.1), now: now))
    }

    @Test("The last day reads as today, not as zero days")
    func lastDay() {
        #expect(
            FamilyPendingRequestLifetime.remaining(createdAt: created(daysAgo: 6.5), now: now)
                == .lastDay
        )
        #expect(
            FamilyPendingRequestLifetime.remaining(createdAt: created(daysAgo: 5.5), now: now)
                == .days(1)
        )
    }

    @Test("Every state produces real copy, never a raw key")
    func labelsAreLocalized() {
        for daysAgo in [0.0, 5.5, 6.5, 8.0] {
            let label = FamilyPendingRequestLifetime.localizedLabel(
                createdAt: created(daysAgo: daysAgo),
                now: now
            )
            #expect(!label.isEmpty)
            #expect(!label.hasPrefix("family.pending."))
        }
    }

    // MARK: - What the captain's surface does with it

    private func makeViewModel(createdAt: Date) throws -> (
        FamilyPendingApprovalsViewModel, PendingJoinRequest
    ) {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: AppMigrationPlan.self,
            configurations: [config]
        )
        let context = ModelContext(container)
        let request = PendingJoinRequest(
            requestId: "req-1",
            familyId: "fam-1",
            userId: "kid",
            requestedBy: "kid",
            method: .code,
            createdAt: createdAt
        )
        context.insert(request)
        try context.save()

        let repository = FamilyRepository()
        repository.setModelContext(context)
        let viewModel = FamilyPendingApprovalsViewModel(
            familyId: "fam-1",
            familyRepository: repository,
            analytics: MockAnalyticsService(),
            dependencies: FamilyPendingApprovalsViewModel.Dependencies(
                resolveIsChildAccount: { _ in false },
                respondToPendingRequest: { _, _, _, _ in },
                fetchPendingRequests: { _ in throw CancellationError() }
            )
        )
        viewModel.configure(authService: FirebaseAuthService(), modelContext: context)
        viewModel.onAppear()
        return (viewModel, request)
    }

    @Test("A row inside its window stays approvable and shows its deadline")
    func liveRowIsActionable() throws {
        let (viewModel, request) = try makeViewModel(createdAt: Date.now.addingTimeInterval(-2 * 24 * 60 * 60))

        #expect(!viewModel.isExpired(request))
        #expect(!viewModel.isRowDisabled(requestId: "req-1"))
        #expect(!viewModel.expiryLabel(for: request).isEmpty)
    }

    /// The reported symptom, from the other side: past the window the row is TERMINAL and says
    /// so, rather than offering the approval the owner found he could still tap.
    @Test("A row past its window is terminal, not silently approvable")
    func elapsedRowIsTerminal() throws {
        let (viewModel, request) = try makeViewModel(createdAt: Date.now.addingTimeInterval(-8 * 24 * 60 * 60))

        #expect(viewModel.isExpired(request))
        #expect(viewModel.isRowDisabled(requestId: "req-1"))
        #expect(!viewModel.canApprove(request: request))
        #expect(viewModel.expiryLabel(for: request) == "family.pending.expired".localized)
    }

    @Test("An elapsed row refuses to send an approval at all")
    func elapsedRowDoesNotCallTheServer() async throws {
        let (viewModel, request) = try makeViewModel(createdAt: Date.now.addingTimeInterval(-9 * 24 * 60 * 60))

        #expect(await viewModel.approve(request: request) == false)
    }
}

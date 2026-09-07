import Foundation
import Testing
@testable import LicensePlateApp

private final class ReviewPresenterSpy: ReviewPromptPresenting {
    private(set) var requestCount = 0

    func requestReview() {
        requestCount += 1
    }
}

@MainActor
struct ReviewPromptServiceTests {
    @Test func firstCompletedTripCanPromptWhenEnabled() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let presenter = ReviewPresenterSpy()
        let service = ReviewPromptService(
            remoteConfig: MockRemoteConfigValues(
                bools: [.reviewPromptEnabled: true],
                ints: [.reviewPromptMinimumCompletedTrips: 1, .reviewPromptCooldownDays: 120]
            ),
            presenter: presenter,
            defaults: defaults,
            now: { Date(timeIntervalSince1970: 1_000) },
            posture: { .confirmedNonChild }
        )

        service.considerPromptAfterTripCompleted(sessionId: UUID())

        #expect(presenter.requestCount == 1)
    }

    @Test func cooldownSuppressesPrompt() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let presenter = ReviewPresenterSpy()
        let service = ReviewPromptService(
            remoteConfig: MockRemoteConfigValues(
                bools: [.reviewPromptEnabled: true],
                ints: [.reviewPromptMinimumCompletedTrips: 1, .reviewPromptCooldownDays: 120]
            ),
            presenter: presenter,
            defaults: defaults,
            now: { Date(timeIntervalSince1970: 1_000) },
            posture: { .confirmedNonChild }
        )

        service.considerPromptAfterTripCompleted(sessionId: UUID())
        service.considerPromptAfterTripCompleted(sessionId: UUID())

        #expect(presenter.requestCount == 1)
    }

    @Test func remoteConfigSuppressesPrompt() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let presenter = ReviewPresenterSpy()
        let service = ReviewPromptService(
            remoteConfig: MockRemoteConfigValues(bools: [.reviewPromptEnabled: false]),
            presenter: presenter,
            defaults: defaults,
            // Adult posture so this deny stays attributable to remote config, not
            // to the F-35 posture gate that would otherwise no-op first.
            posture: { .confirmedNonChild }
        )

        service.considerPromptAfterTripCompleted(sessionId: UUID())

        #expect(presenter.requestCount == 0)
    }

    // MARK: - FR-79 (F-35): non-confirmedNonChild postures no-op in full

    @Test func childDirectedPostureNeverPrompts() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let presenter = ReviewPresenterSpy()
        let service = ReviewPromptService(
            remoteConfig: MockRemoteConfigValues(
                bools: [.reviewPromptEnabled: true],
                ints: [.reviewPromptMinimumCompletedTrips: 1, .reviewPromptCooldownDays: 120]
            ),
            presenter: presenter,
            defaults: defaults,
            now: { Date(timeIntervalSince1970: 1_000) },
            posture: { .childDirected }
        )

        service.considerPromptAfterTripCompleted(sessionId: UUID())

        #expect(presenter.requestCount == 0)
        // Full no-op: the completed-trip counter itself must not move either, so a
        // later posture resolution to confirmedNonChild starts counting fresh rather
        // than inheriting trip completions from a child-directed session.
        #expect(defaults.integer(forKey: "reviewPrompt.completedTripCount") == 0)
    }

    @Test func ratchetedAnonymousPostureNeverPrompts() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let presenter = ReviewPresenterSpy()
        let service = ReviewPromptService(
            remoteConfig: MockRemoteConfigValues(
                bools: [.reviewPromptEnabled: true],
                ints: [.reviewPromptMinimumCompletedTrips: 1, .reviewPromptCooldownDays: 120]
            ),
            presenter: presenter,
            defaults: defaults,
            posture: { .ratchetedAnonymous }
        )

        service.considerPromptAfterTripCompleted(sessionId: UUID())

        #expect(presenter.requestCount == 0)
    }

    @Test func unresolvedPostureNeverPrompts() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let presenter = ReviewPresenterSpy()
        let service = ReviewPromptService(
            remoteConfig: MockRemoteConfigValues(
                bools: [.reviewPromptEnabled: true],
                ints: [.reviewPromptMinimumCompletedTrips: 1, .reviewPromptCooldownDays: 120]
            ),
            presenter: presenter,
            defaults: defaults,
            posture: { .unresolved }
        )

        service.considerPromptAfterTripCompleted(sessionId: UUID())

        #expect(presenter.requestCount == 0)
    }

    @Test func confirmedNonChildPostureCanStillPrompt() {
        // Guards against a regression that accidentally inverts the new posture gate
        // and silences the prompt for the one posture that must keep it.
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let presenter = ReviewPresenterSpy()
        let service = ReviewPromptService(
            remoteConfig: MockRemoteConfigValues(
                bools: [.reviewPromptEnabled: true],
                ints: [.reviewPromptMinimumCompletedTrips: 1, .reviewPromptCooldownDays: 120]
            ),
            presenter: presenter,
            defaults: defaults,
            now: { Date(timeIntervalSince1970: 1_000) },
            posture: { .confirmedNonChild }
        )

        service.considerPromptAfterTripCompleted(sessionId: UUID())

        #expect(presenter.requestCount == 1)
    }
}

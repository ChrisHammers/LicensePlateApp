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
            now: { Date(timeIntervalSince1970: 1_000) }
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
            now: { Date(timeIntervalSince1970: 1_000) }
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
            defaults: defaults
        )

        service.considerPromptAfterTripCompleted(sessionId: UUID())

        #expect(presenter.requestCount == 0)
    }
}

//
//  ReturnStreakViewModel.swift
//  LicensePlateApp
//
//  Home return-streak chip: reads ReturnStreakService.currentState, never duplicates streak math.
//

import Foundation
import Combine

struct ReturnStreakPresentation: Equatable {
    let currentStreak: Int
    let isVisible: Bool
    let accessibilityLabel: String
    let accessibilityHint: String
}

@MainActor
final class ReturnStreakViewModel: ObservableObject {

    @Published private(set) var presentation = ReturnStreakPresentation(
        currentStreak: 0,
        isVisible: false,
        accessibilityLabel: "",
        accessibilityHint: ""
    )
    @Published var isShowingExplanation = false

    private let streakService: ReturnStreakService
    private let rewardPresenter: RewardPresenter
    private var cancellables = Set<AnyCancellable>()
    private var activeUserId: String?
    private var hasLoggedDisplayThisSession = false
    private var wasVisible = false

    init(
        streakService: ReturnStreakService = .shared,
        rewardPresenter: RewardPresenter = .shared
    ) {
        self.streakService = streakService
        self.rewardPresenter = rewardPresenter

        streakService.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleServiceChange()
            }
            .store(in: &cancellables)
    }

    func bind(userId: String?) {
        activeUserId = userId
        streakService.setActiveUserId(userId)
        hasLoggedDisplayThisSession = false
        refresh()
    }

    func refresh() {
        guard let userId = activeUserId, !userId.isEmpty else {
            applyPresentation(streak: 0, visible: false)
            return
        }

        guard streakService.isEnabled else {
            applyPresentation(streak: 0, visible: false)
            return
        }

        let state = streakService.currentState(for: userId)
        let visible = state.currentStreak >= streakService.minDisplayStreak
        applyPresentation(streak: state.currentStreak, visible: visible)

        if visible, !wasVisible, !hasLoggedDisplayThisSession {
            AnalyticsService.shared.log(
                .returnStreakDisplayed(currentStreak: state.currentStreak, surface: "home")
            )
            hasLoggedDisplayThisSession = true
        }
        wasVisible = visible
    }

    func openExplanation() {
        isShowingExplanation = true
        AnalyticsService.shared.log(
            .returnStreakExplanationOpened(currentStreak: presentation.currentStreak)
        )
    }

    // MARK: - Private

    private func handleServiceChange() {
        if let outcome = streakService.consumeLastRecordOutcome() {
            handleRecordOutcome(outcome)
        }
        refresh()
    }

    private func handleRecordOutcome(_ outcome: ReturnStreakRecordOutcome) {
        let currentStreak: Int
        switch outcome {
        case .continued(_, let streak), .started(let streak):
            currentStreak = streak
        case .brokenThenStarted:
            currentStreak = 1
        case .disabled, .noOp:
            return
        }

        guard streakService.celebrationEnabled,
              currentStreak >= streakService.celebrationMinStreak else {
            return
        }

        rewardPresenter.show(.returnStreak(days: currentStreak))
        AnalyticsService.shared.log(.returnStreakCelebrationShown(currentStreak: currentStreak))
    }

    private func applyPresentation(streak: Int, visible: Bool) {
        presentation = ReturnStreakPresentation(
            currentStreak: streak,
            isVisible: visible,
            accessibilityLabel: String(format: "return_streak.a11y.label".localized, streak),
            accessibilityHint: "return_streak.a11y.hint".localized
        )
    }
}

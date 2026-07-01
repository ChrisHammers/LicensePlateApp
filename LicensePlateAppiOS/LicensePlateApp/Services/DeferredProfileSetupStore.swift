//
//  DeferredProfileSetupStore.swift
//  LicensePlateApp
//
//  Tracks optional profile setup steps deferred from first-session quick path.
//

import Foundation
import Combine

enum DeferredSetupStep: String, CaseIterable, Identifiable {
    case avatar
    case account
    //case family
    case notifications

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .avatar: return "Choose your avatar".localized
        case .account: return "Create account".localized
        //case .family: return "Friends & Family".localized
        case .notifications: return "Notifications".localized
        }
    }

    var systemImage: String {
        switch self {
        case .avatar: return "person.crop.circle"
        case .account: return "person.badge.plus"
        //case .family: return "person.2.fill"
        case .notifications: return "bell.fill"
        }
    }
}

@MainActor
final class DeferredProfileSetupStore: ObservableObject {
    static let shared = DeferredProfileSetupStore()

    @Published private(set) var revision = 0

    private let state: FirstSessionStateStoring
    private let accountStateProvider: AccountStateProviding

    init(
        state: FirstSessionStateStoring = FirstSessionState.shared,
        accountStateProvider: AccountStateProviding = FirebaseAccountStateProvider.shared
    ) {
        self.state = state
        self.accountStateProvider = accountStateProvider
    }

    func pendingSteps(for user: AppUser?) -> [DeferredSetupStep] {
        let completed = state.deferredSetupStepsCompleted
        var steps: [DeferredSetupStep] = []

        if !completed.contains(DeferredSetupStep.avatar.rawValue) {
            steps.append(.avatar)
        }

        let accountState = accountStateProvider.currentAccountState(for: user)
        if accountState.isGuestLike, !completed.contains(DeferredSetupStep.account.rawValue) {
            steps.append(.account)
        }

//        if !accountState.isGuestLike,
//           user?.activeFamilyId == nil,
//           !completed.contains(DeferredSetupStep.family.rawValue) {
//            steps.append(.family)
//        }

        if !completed.contains(DeferredSetupStep.notifications.rawValue) {
            steps.append(.notifications)
        }

        return steps
    }

    func markCompleted(_ step: DeferredSetupStep) {
        var completed = state.deferredSetupStepsCompleted
        guard completed.insert(step.rawValue).inserted else { return }
        state.deferredSetupStepsCompleted = completed
        revision += 1
    }

    func shouldShowPostFirstFindPrompt(for user: AppUser?) -> Bool {
        guard state.hasLoggedFirstFind else { return false }
        if state.deferredSetupPromptDismissedAt != nil { return false }
        return !pendingSteps(for: user).isEmpty
    }

    func dismissPostFirstFindPrompt() {
        guard state.deferredSetupPromptDismissedAt == nil else { return }
        state.deferredSetupPromptDismissedAt = Date()
        revision += 1
    }
}

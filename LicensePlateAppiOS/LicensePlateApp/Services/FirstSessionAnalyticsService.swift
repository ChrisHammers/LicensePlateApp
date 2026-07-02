//
//  FirstSessionAnalyticsService.swift
//  LicensePlateApp
//
//  First-session funnel analytics with elapsed-time tracking.
//

import Foundation

@MainActor
final class FirstSessionAnalyticsService {
    static let shared = FirstSessionAnalyticsService()

    private let analytics: AnalyticsLogging
    private let state: FirstSessionStateStoring
    private var didLogOnboardingStarted = false

    init(
        analytics: AnalyticsLogging = AnalyticsService.shared,
        state: FirstSessionStateStoring = FirstSessionState.shared
    ) {
        self.analytics = analytics
        self.state = state
    }

    func recordOnboardingStarted(flowVariant: FirstSessionFlowVariant, offline: Bool) {
        guard !didLogOnboardingStarted else { return }
        didLogOnboardingStarted = true
        if state.onboardingStartedAt == nil {
            state.onboardingStartedAt = Date()
        }
        state.activeFlowVariant = flowVariant
        analytics.log(.onboardingStarted(flowVariant: flowVariant.rawValue, offline: offline))
    }

    func recordOnboardingStepViewed(stepId: String, stepIndex: Int, flowVariant: FirstSessionFlowVariant) {
        state.lastOnboardingStepId = stepId
        analytics.log(.onboardingStepViewed(
            stepId: stepId,
            stepIndex: stepIndex,
            flowVariant: flowVariant.rawValue
        ))
    }

    func recordOnboardingAbandoned(flowVariant: FirstSessionFlowVariant) {
        let elapsed = state.elapsedMs(since: state.onboardingStartedAt)
        analytics.log(.onboardingAbandoned(
            lastStepId: state.lastOnboardingStepId ?? "unknown",
            flowVariant: flowVariant.rawValue,
            elapsedMs: elapsed
        ))
    }

    func recordOnboardingCompleted(flowVariant: FirstSessionFlowVariant, offline: Bool) {
        let elapsed = state.elapsedMs(since: state.onboardingStartedAt)
        analytics.log(.onboardingCompleted(
            flowVariant: flowVariant.rawValue,
            elapsedMs: elapsed,
            offline: offline
        ))
        analytics.setUserProperty(flowVariant.rawValue, forName: "first_session_flow_variant")
    }

    func recordQuickSoloTripStarted(intent: QuickSoloLaunchIntent, offline: Bool) {
        state.quickTripStartedAt = Date()
        let elapsed = state.elapsedMs(since: state.onboardingStartedAt)
        analytics.log(.quickSoloTripStarted(
            tripSessionId: intent.sessionId.uuidString,
            gameInstanceId: intent.gameId.uuidString,
            offline: offline,
            elapsedMs: elapsed
        ))
    }

    func recordFirstFindIfNeeded(
        tripSessionId: UUID,
        gameInstanceId: UUID,
        targetId: String,
        inputMethod: String
    ) {
        guard !state.hasLoggedFirstFind else { return }
        state.hasLoggedFirstFind = true
        let elapsed = state.elapsedMs(since: state.onboardingStartedAt)
        analytics.log(.firstFindCompleted(
            tripSessionId: tripSessionId.uuidString,
            gameInstanceId: gameInstanceId.uuidString,
            targetId: targetId,
            elapsedMs: elapsed,
            inputMethod: inputMethod
        ))
    }

    func recordDeferredSetupPromptShown(pendingSteps: [DeferredSetupStep]) {
        let joined = pendingSteps.map(\.rawValue).joined(separator: ",")
        analytics.log(.deferredSetupPromptShown(pendingSteps: joined))
    }

    func recordDeferredSetupStepOpened(stepId: String, source: String) {
        analytics.log(.deferredSetupStepOpened(stepId: stepId, source: source))
    }

    func recordDeferredSetupStepCompleted(stepId: String) {
        analytics.log(.deferredSetupStepCompleted(stepId: stepId))
    }

    func recordDeferredSetupStepTouched(stepId: String, source: String) {
        analytics.log(.deferredSetupStepTouched(stepId: stepId, source: source))
    }
}

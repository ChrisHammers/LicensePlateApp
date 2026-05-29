//
//  AnalyticsServiceTests.swift
//  LicensePlateAppTests
//
//  Step 10 — Event names, parameters, and AnalyticsLoggingSpy for feature tests.
//

import Foundation
import Testing
@testable import LicensePlateApp

// MARK: - AnalyticsLoggingSpy

@MainActor
final class AnalyticsLoggingSpy: AnalyticsLogging {
    struct LoggedEvent {
        let name: String
        let parameters: [String: Any]?
    }

    private(set) var loggedEvents: [LoggedEvent] = []

    func log(_ event: AnalyticsService.Event) {
        loggedEvents.append(LoggedEvent(name: event.name, parameters: event.parameters))
    }

    func log(_ name: String, parameters: [String: Any]) {
        loggedEvents.append(LoggedEvent(name: name, parameters: parameters.isEmpty ? nil : parameters))
    }

    func clear() {
        loggedEvents.removeAll()
    }
}

// MARK: - Event name tests (snake_case)

struct AnalyticsServiceTests {

    @Test @MainActor func eventNamesAreSnakeCase() async throws {
        let expectations: [(AnalyticsService.Event, String)] = [
            (.friendsScreenOpened, "friends_screen_opened"),
            (.familyScreenOpened, "family_screen_opened"),
            (.travelLogOpened, "travel_log_opened"),
            (.tripInvitesScreenOpened, "trip_invites_screen_opened"),
            (.paywallViewed(source: nil), "paywall_viewed"),
            (.paywallDismissed, "paywall_dismissed"),
            (.tripLimitHit(source: "trip_limit_create", activeTripCount: 1, activeTripLimit: 1, tier: "signedUp"), "trip_limit_hit"),
            (.savedTripLimitHit(source: "travel_log", savedTripCount: 6, savedTripLimit: 3, tier: "guest"), "saved_trip_limit_hit"),
            (.avatarPickerOpened(source: "test"), "avatar_picker_opened"),
            (.avatarSaved(avatarId: "id", source: "profile"), "avatar_saved"),
            (.notificationDeliveryFailed(error: "err"), "notification_delivery_failed"),
            (.remoteConfigFetchSucceeded, "remote_config_fetch_succeeded"),
            (.adEligibilityEvaluated(surface: "travel_log", eligible: true, reason: "free_tier"), "ad_eligibility_evaluated"),
            (.reviewPromptPresented(sessionId: "session-1"), "review_prompt_presented"),
            (.reminderScheduled(sessionId: "session-1", hours: 24), "reminder_scheduled"),
            (.returnStreakUpdated(currentStreak: 2, reason: "consecutive_return"), "return_streak_updated"),
            (.screenView(screenName: "test", screenClass: nil), "screen_view"),
            (.combinedTripCreated(gameTypes: ["lp"]), "combined_trip_created"),
            (.userSearchPerformed(queryType: "all"), "user_search_performed"),
        ]
        for (event, expectedName) in expectations {
            #expect(event.name == expectedName)
        }
    }

    @Test @MainActor func eventParametersContainExpectedKeys() async throws {
        // userSearchPerformed uses query_type (snake_case)
        let searchEvent = AnalyticsService.Event.userSearchPerformed(queryType: "username")
        #expect(searchEvent.parameters?["query_type"] as? String == "username")

        // avatar events
        let savedEvent = AnalyticsService.Event.avatarSaved(avatarId: "av1", source: "onboarding")
        #expect(savedEvent.parameters?["avatar_id"] as? String == "av1")
        #expect(savedEvent.parameters?["source"] as? String == "onboarding")

        let lockedEvent = AnalyticsService.Event.avatarLockedTapped(avatarId: "av2", unlockSource: "gold")
        #expect(lockedEvent.parameters?["avatar_id"] as? String == "av2")
        #expect(lockedEvent.parameters?["unlock_source"] as? String == "gold")

        // notification_delivery_failed
        let notifEvent = AnalyticsService.Event.notificationDeliveryFailed(error: "permission denied")
        #expect(notifEvent.parameters?["error"] as? String == "permission denied")

        let adEvent = AnalyticsService.Event.adEligibilityEvaluated(surface: "travel_log", eligible: true, reason: "free_tier")
        #expect(adEvent.parameters?["surface"] as? String == "travel_log")
        #expect(adEvent.parameters?["eligible"] as? Bool == true)
        #expect(adEvent.parameters?["reason"] as? String == "free_tier")

        let reviewEvent = AnalyticsService.Event.reviewPromptSuppressed(reason: "cooldown", completedTripCount: 2)
        #expect(reviewEvent.parameters?["reason"] as? String == "cooldown")
        #expect(reviewEvent.parameters?["completed_trip_count"] as? Int == 2)

        let reminderEvent = AnalyticsService.Event.reminderScheduled(sessionId: "session-1", hours: 24)
        #expect(reminderEvent.parameters?["session_id"] as? String == "session-1")
        #expect(reminderEvent.parameters?["hours"] as? Int == 24)

        let streakEvent = AnalyticsService.Event.returnStreakUpdated(currentStreak: 3, reason: "consecutive_return")
        #expect(streakEvent.parameters?["current_streak"] as? Int == 3)

        // screen_view
        let screenEvent = AnalyticsService.Event.screenView(screenName: "travel_log", screenClass: "TravelLogView")
        #expect(screenEvent.parameters?["screen_name"] as? String == "travel_log")
        #expect(screenEvent.parameters?["screen_class"] as? String == "TravelLogView")

        // combined_trip_created (optional params when provided)
        let combinedEvent = AnalyticsService.Event.combinedTripCreated(gameTypes: ["license_plate", "other"])
        let gameTypesParam = combinedEvent.parameters?["game_types"] as? String
        #expect(gameTypesParam == "license_plate,other")

        let combinedWithContext = AnalyticsService.Event.combinedTripCreated(
            gameTypes: ["lp"],
            tripSessionId: "session-1",
            participantCount: 1,
            gameCount: 1,
            gameModes: ["collaborative"],
            hasTeams: false
        )
        #expect(combinedWithContext.parameters?["trip_session_id"] as? String == "session-1")
        #expect(combinedWithContext.parameters?["participant_count"] as? Int == 1)
        #expect(combinedWithContext.parameters?["game_count"] as? Int == 1)
        #expect(combinedWithContext.parameters?["game_modes"] as? String == "collaborative")
        #expect(combinedWithContext.parameters?["has_teams"] as? Bool == false)

        let limitHit = AnalyticsService.Event.tripLimitHit(
            source: "trip_limit_invite_accept",
            activeTripCount: 1,
            activeTripLimit: 1,
            tier: "signedUp"
        )
        #expect(limitHit.parameters?["source"] as? String == "trip_limit_invite_accept")
        #expect(limitHit.parameters?["active_trip_count"] as? Int == 1)
        #expect(limitHit.parameters?["active_trip_limit"] as? Int == 1)
        #expect(limitHit.parameters?["tier"] as? String == "signedUp")

        let savedTripLimitHit = AnalyticsService.Event.savedTripLimitHit(
            source: "travel_log",
            savedTripCount: 6,
            savedTripLimit: 3,
            tier: "guest"
        )
        #expect(savedTripLimitHit.parameters?["source"] as? String == "travel_log")
        #expect(savedTripLimitHit.parameters?["saved_trip_count"] as? Int == 6)
        #expect(savedTripLimitHit.parameters?["saved_trip_limit"] as? Int == 3)
        #expect(savedTripLimitHit.parameters?["tier"] as? String == "guest")
    }

    @Test @MainActor func spyRecordsTypedEvents() async throws {
        let spy = AnalyticsLoggingSpy()
        spy.log(.travelLogOpened)
        spy.log(.tripSummaryViewed(sessionId: "sid-123"))

        #expect(spy.loggedEvents.count == 2)
        #expect(spy.loggedEvents[0].name == "travel_log_opened")
        #expect(spy.loggedEvents[0].parameters == nil)
        #expect(spy.loggedEvents[1].name == "trip_summary_viewed")
        #expect(spy.loggedEvents[1].parameters?["session_id"] as? String == "sid-123")
    }

    @Test @MainActor func spyRecordsRawNameAndParameters() async throws {
        let spy = AnalyticsLoggingSpy()
        spy.log("custom_event", parameters: ["key": "value"])

        #expect(spy.loggedEvents.count == 1)
        #expect(spy.loggedEvents[0].name == "custom_event")
        #expect(spy.loggedEvents[0].parameters?["key"] as? String == "value")
    }

    // MARK: - Step 10.5 new event names and parameters

    @Test @MainActor func lifecycleEventNamesAndParameters() async throws {
        let started = AnalyticsService.Event.gameInstanceStarted(
            gameInstanceId: "gi-1",
            gameType: "license_plate",
            gameLifecycleState: "started",
            configLockReason: "game_started",
            tripSessionId: "session-1"
        )
        #expect(started.name == "game_instance_started")
        #expect(started.parameters?["game_instance_id"] as? String == "gi-1")
        #expect(started.parameters?["game_type"] as? String == "license_plate")
        #expect(started.parameters?["config_lock_reason"] as? String == "game_started")
        #expect(started.parameters?["trip_session_id"] as? String == "session-1")

        let combinedStarted = AnalyticsService.Event.combinedTripStartedWithGameCount(
            tripId: "trip-1",
            combinedGameCount: 2,
            combinedGameTypes: ["license_plate", "other"]
        )
        #expect(combinedStarted.name == "combined_trip_started_with_game_count")
        #expect(combinedStarted.parameters?["trip_session_id"] as? String == "trip-1")
        #expect(combinedStarted.parameters?["combined_game_count"] as? Int == 2)
        #expect(combinedStarted.parameters?["combined_game_types"] as? String == "license_plate,other")

        let compSummary = AnalyticsService.Event.tripSummaryCompetitiveRankingsPresented(tripSessionId: "t-1")
        #expect(compSummary.name == "trip_summary_competitive_rankings_presented")
        #expect(compSummary.parameters?["trip_session_id"] as? String == "t-1")

        let compStandings = AnalyticsService.Event.competitiveInGameStandingsPresented(tripSessionId: "t-2", gameInstanceId: "g-2")
        #expect(compStandings.name == "competitive_in_game_standings_presented")
        #expect(compStandings.parameters?["trip_session_id"] as? String == "t-2")
        #expect(compStandings.parameters?["game_instance_id"] as? String == "g-2")

        let tripDash = AnalyticsService.Event.tripDashboardCompetitiveLeaderboardPresented(tripSessionId: "t-3")
        #expect(tripDash.name == "trip_dashboard_competitive_leaderboard_presented")
        #expect(tripDash.parameters?["trip_session_id"] as? String == "t-3")
    }

    @Test @MainActor func tripSessionCreatedAndGameInstanceEndedParameters() async throws {
        let created = AnalyticsService.Event.tripSessionCreated(
            tripId: "sid-1",
            tripStatus: "active",
            tripParticipantCount: 1,
            tripActiveGameCount: 2,
            tripSource: "combined_setup"
        )
        #expect(created.parameters?["trip_session_id"] as? String == "sid-1")
        #expect(created.parameters?["trip_participant_count"] as? Int == 1)
        #expect(created.parameters?["trip_active_game_count"] as? Int == 2)

        let ended = AnalyticsService.Event.gameInstanceEnded(gameInstanceId: "g1", gameType: "lp", tripSessionId: "s1")
        #expect(ended.parameters?["game_instance_id"] as? String == "g1")
        #expect(ended.parameters?["game_type"] as? String == "lp")
        #expect(ended.parameters?["trip_session_id"] as? String == "s1")

        let completed = AnalyticsService.Event.gameInstanceCompleted(gameInstanceId: "g2", gameType: "license_plate", tripSessionId: "s2")
        #expect(completed.name == "game_instance_completed")
        #expect(completed.parameters?["game_instance_id"] as? String == "g2")
        #expect(completed.parameters?["game_type"] as? String == "license_plate")
        #expect(completed.parameters?["trip_session_id"] as? String == "s2")

        let deleted = AnalyticsService.Event.gameInstanceDeleted(
            tripSessionId: "s3",
            gameInstanceId: "g3",
            gameType: "license_plate",
            remainingGameCount: 1
        )
        #expect(deleted.name == "game_instance_deleted")
        #expect(deleted.parameters?["trip_session_id"] as? String == "s3")
        #expect(deleted.parameters?["game_instance_id"] as? String == "g3")
        #expect(deleted.parameters?["remaining_game_count"] as? Int == 1)
    }

    @Test @MainActor func tripInviteSentEvent() async throws {
        let sent = AnalyticsService.Event.tripInviteSent(tripSessionId: "trip-abc", tripNameLength: 12)
        #expect(sent.name == "trip_invite_sent")
        #expect(sent.parameters?["invite_trip_id"] as? String == "trip-abc")
        #expect(sent.parameters?["trip_name_length"] as? Int == 12)

        let failed = AnalyticsService.Event.tripInviteSendFailed(tripSessionId: "trip-abc", error: "network")
        #expect(failed.name == "trip_invite_send_failed")
        #expect(failed.parameters?["invite_trip_id"] as? String == "trip-abc")
        #expect(failed.parameters?["error"] as? String == "network")

        let viewed = AnalyticsService.Event.tripParticipantsViewed(tripSessionId: "trip-abc")
        #expect(viewed.name == "trip_participants_viewed")
        #expect(viewed.parameters?["trip_session_id"] as? String == "trip-abc")
    }

    @Test @MainActor func inviteContextEvents() async throws {
        let inviteAccepted = AnalyticsService.Event.tripInviteAcceptedWithContext(
            inviteTripId: "inv-trip-1",
            inviteGameCount: 2,
            participantCountAfterJoin: 3
        )
        #expect(inviteAccepted.name == "trip_invite_accepted")
        #expect(inviteAccepted.parameters?["invite_trip_id"] as? String == "inv-trip-1")
        #expect(inviteAccepted.parameters?["invite_game_count"] as? Int == 2)
        #expect(inviteAccepted.parameters?["participant_count_after_join"] as? Int == 3)
    }

    @Test @MainActor func errorEventParameters() async throws {
        let buildFailed = AnalyticsService.Event.analyticsPropertyBuildFailed(eventName: "test_event", error: "decode failed")

        let gameplayAccepted = AnalyticsService.Event.gameplayEventServerAccepted(
            tripSessionId: "t1",
            gameInstanceId: "g1",
            eventKind: "region_found"
        )
        #expect(gameplayAccepted.parameters?["trip_session_id"] as? String == "t1")
        #expect(gameplayAccepted.parameters?["event_kind"] as? String == "region_found")

        let gameplaySuperseded = AnalyticsService.Event.gameplayEventServerSuperseded(
            tripSessionId: "t1",
            gameInstanceId: "g1",
            serverRejectionEventId: "srvrej_x",
            reason: "server_rejected_late_competitive"
        )
        #expect(gameplaySuperseded.parameters?["server_rejection_event_id"] as? String == "srvrej_x")

        let gameplayRejected = AnalyticsService.Event.gameplayEventServerRejected(
            tripSessionId: "t1",
            eventKind: "region_found",
            errorCode: 9,
            errorDomain: "FIRFunctionsErrorDomain"
        )
        #expect(gameplayRejected.parameters?["error_code"] as? Int == 9)

        let appendTimedOut = AnalyticsService.Event.gameplayEventAppendTimedOut(
            tripSessionId: "t1",
            gameInstanceId: "g1",
            eventKind: "region_found",
            attemptCount: 2,
            timeoutSeconds: 45
        )
        #expect(appendTimedOut.name == "gameplay_event_append_timed_out")
        #expect(appendTimedOut.parameters?["trip_session_id"] as? String == "t1")
        #expect(appendTimedOut.parameters?["game_instance_id"] as? String == "g1")
        #expect(appendTimedOut.parameters?["attempt_count"] as? Int == 2)
        #expect(appendTimedOut.parameters?["timeout_seconds"] as? Int == 45)
        #expect(buildFailed.name == "analytics_property_build_failed")
        #expect(buildFailed.parameters?["error"] as? String == "decode failed")
    }
}

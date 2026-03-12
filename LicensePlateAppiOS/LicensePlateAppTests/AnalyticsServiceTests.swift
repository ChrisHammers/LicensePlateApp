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
            (.avatarPickerOpened(source: "test"), "avatar_picker_opened"),
            (.avatarSaved(avatarId: "id", source: "profile"), "avatar_saved"),
            (.notificationDeliveryFailed(error: "err"), "notification_delivery_failed"),
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

        // screen_view
        let screenEvent = AnalyticsService.Event.screenView(screenName: "travel_log", screenClass: "TravelLogView")
        #expect(screenEvent.parameters?["screen_name"] as? String == "travel_log")
        #expect(screenEvent.parameters?["screen_class"] as? String == "TravelLogView")

        // combined_trip_created
        let combinedEvent = AnalyticsService.Event.combinedTripCreated(gameTypes: ["license_plate", "other"])
        let gameTypesParam = combinedEvent.parameters?["game_types"] as? String
        #expect(gameTypesParam == "license_plate,other")
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
            configLockReason: "game_started"
        )
        #expect(started.name == "game_instance_started")
        #expect(started.parameters?["game_instance_id"] as? String == "gi-1")
        #expect(started.parameters?["game_type"] as? String == "license_plate")
        #expect(started.parameters?["config_lock_reason"] as? String == "game_started")

        let combinedStarted = AnalyticsService.Event.combinedTripStartedWithGameCount(
            tripId: "trip-1",
            combinedGameCount: 2,
            combinedGameTypes: ["license_plate", "other"]
        )
        #expect(combinedStarted.name == "combined_trip_started_with_game_count")
        #expect(combinedStarted.parameters?["trip_id"] as? String == "trip-1")
        #expect(combinedStarted.parameters?["combined_game_count"] as? Int == 2)
        #expect(combinedStarted.parameters?["combined_game_types"] as? String == "license_plate,other")
    }

    @Test @MainActor func legacyAdapterAndInviteContextEvents() async throws {
        let legacyUsed = AnalyticsService.Event.legacyTripAdapterUsed(legacyTripId: "legacy-1", sessionId: "sess-1")
        #expect(legacyUsed.name == "legacy_trip_adapter_used")
        #expect(legacyUsed.parameters?["legacy_trip_id"] as? String == "legacy-1")
        #expect(legacyUsed.parameters?["session_id"] as? String == "sess-1")

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
        let adapterFailed = AnalyticsService.Event.legacyTripAdapterFailed(error: "decode failed")
        #expect(adapterFailed.name == "legacy_trip_adapter_failed")
        #expect(adapterFailed.parameters?["error"] as? String == "decode failed")
    }
}

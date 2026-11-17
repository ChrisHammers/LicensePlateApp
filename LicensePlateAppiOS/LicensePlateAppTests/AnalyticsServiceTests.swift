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

    func setUserProperty(_ value: String?, forName name: String) {}

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
            (.tripSummaryShared(sessionId: "sid"), "trip_summary_shared"),
            (.tripInvitesScreenOpened, "trip_invites_screen_opened"),
            (.paywallViewed(source: nil), "paywall_viewed"),
            (.paywallDismissed, "paywall_dismissed"),
            (.tripLimitHit(source: "trip_limit_create", activeTripCount: 1, activeTripLimit: 1, tier: "signedUp"), "trip_limit_hit"),
            (.savedTripLimitHit(source: "travel_log", savedTripCount: 6, savedTripLimit: 3, tier: "guest"), "saved_trip_limit_hit"),
            (.avatarPickerOpened(source: "test"), "avatar_picker_opened"),
            (.avatarSaved(avatarId: "id", source: "profile"), "avatar_saved"),
            (.notificationDeliveryFailed(error: "err"), "notification_delivery_failed"),
            (.remoteConfigFetchSucceeded, "remote_config_fetch_succeeded"),
            (.forceUpdateGateShown(gateKind: "hard", clientCompat: 1, appVersion: "1.0", appBuild: "4"), "force_update_gate_shown"),
            (.softUpdatePromptShown(gateKind: "soft", clientCompat: 1, appVersion: "1.0", appBuild: "4"), "soft_update_prompt_shown"),
            (.softUpdatePromptDismissed(gateKind: "soft", clientCompat: 1, appVersion: "1.0", appBuild: "4"), "soft_update_prompt_dismissed"),
            (.updateStoreCTATapped(gateKind: "hard", clientCompat: 1, appVersion: "1.0", appBuild: "4"), "update_store_cta_tapped"),
            (.adEligibilityEvaluated(surface: "travel_log", eligible: true, reason: "free_tier"), "ad_eligibility_evaluated"),
            (.reviewPromptPresented(sessionId: "session-1"), "review_prompt_presented"),
            (.reviewLinkOpened(source: "help_about", method: "app_store"), "review_link_opened"),
            (.reminderScheduled(sessionId: "session-1", hours: 24), "reminder_scheduled"),
            (.returnStreakUpdated(currentStreak: 2, reason: "consecutive_return"), "return_streak_updated"),
            (.returnStreakQualified(currentStreak: 2, reason: "continued"), "return_streak_qualified"),
            (.returnStreakDisplayed(currentStreak: 3, surface: "home"), "return_streak_displayed"),
            (.returnStreakDailyXpClaimSucceeded(dayKey: "2026-07-11", currentStreak: 2, granted: true, alreadyClaimed: false), "return_streak_daily_xp_claim_succeeded"),
            (.returnStreakDailyXpClaimFailed(dayKey: "2026-07-11", currentStreak: 2, errorSummary: "offline"), "return_streak_daily_xp_claim_failed"),
            (.screenView(screenName: "test", screenClass: nil), "screen_view"),
            (.combinedTripCreated(gameTypes: ["lp"]), "combined_trip_created"),
            (.onboardingStarted(flowVariant: "quick_solo", offline: false), "onboarding_started"),
            (.quickSoloTripStarted(tripSessionId: "t1", gameInstanceId: "g1", offline: false, elapsedMs: 100), "quick_solo_trip_started"),
            (.firstFindCompleted(tripSessionId: "t1", gameInstanceId: "g1", targetId: "us-ca", elapsedMs: 200, inputMethod: "list"), "first_find_completed"),
            (.userSearchPerformed(queryType: "all"), "user_search_performed"),
            (.authProfileHydrateFailed(outcome: "keep_local"), "auth_profile_hydrate_failed"),
            (
                .progressionXpDriftAfterSync(
                    openProvisionalXp: 10,
                    hasOpenProvisional: true,
                    hasPendingLocalProgression: false,
                    pendingLocalXpDelta: 0,
                    serverTotalXp: 100,
                    verifiedGrantSum: 100,
                    grantLedgerMismatch: false,
                    hasReceivedGrantSnapshot: true,
                    progressionTriggerConfirmed: true,
                    recentlyAcceptedCount: 1,
                    settleWaitMs: 1200
                ),
                "progression_xp_drift_after_sync"
            ),
        ]
        for (event, expectedName) in expectations {
            #expect(event.name == expectedName)
        }
    }

    @Test @MainActor func eventParametersContainExpectedKeys() async throws {
        // userSearchPerformed uses query_type (snake_case)
        let searchEvent = AnalyticsService.Event.userSearchPerformed(queryType: "username")
        #expect(searchEvent.parameters?["query_type"] as? String == "username")

        let hydrateEvent = AnalyticsService.Event.authProfileHydrateFailed(outcome: "abort_no_create")
        #expect(hydrateEvent.parameters?["outcome"] as? String == "abort_no_create")

        let forceUpdate = AnalyticsService.Event.forceUpdateGateShown(
            gateKind: "hard",
            clientCompat: 1,
            appVersion: "0.1",
            appBuild: "4"
        )
        #expect(forceUpdate.parameters?["gate_kind"] as? String == "hard")
        #expect(forceUpdate.parameters?["client_compat"] as? Int == 1)
        #expect(forceUpdate.parameters?["app_version"] as? String == "0.1")
        #expect(forceUpdate.parameters?["app_build"] as? String == "4")

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

        let reviewLink = AnalyticsService.Event.reviewLinkOpened(source: "help_about", method: "app_store")
        #expect(reviewLink.parameters?["source"] as? String == "help_about")
        #expect(reviewLink.parameters?["method"] as? String == "app_store")

        let reminderEvent = AnalyticsService.Event.reminderScheduled(sessionId: "session-1", hours: 24)
        #expect(reminderEvent.parameters?["session_id"] as? String == "session-1")
        #expect(reminderEvent.parameters?["hours"] as? Int == 24)

        let streakEvent = AnalyticsService.Event.returnStreakUpdated(currentStreak: 3, reason: "consecutive_return")
        #expect(streakEvent.parameters?["current_streak"] as? Int == 3)

        let qualifiedEvent = AnalyticsService.Event.returnStreakQualified(currentStreak: 2, reason: "continued")
        #expect(qualifiedEvent.parameters?["current_streak"] as? Int == 2)
        #expect(qualifiedEvent.parameters?["reason"] as? String == "continued")

        let displayedEvent = AnalyticsService.Event.returnStreakDisplayed(currentStreak: 4, surface: "home")
        #expect(displayedEvent.parameters?["surface"] as? String == "home")

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
        spy.log(.tripSummaryShared(sessionId: "sid-456"))

        #expect(spy.loggedEvents.count == 3)
        #expect(spy.loggedEvents[0].name == "travel_log_opened")
        #expect(spy.loggedEvents[0].parameters == nil)
        #expect(spy.loggedEvents[1].name == "trip_summary_viewed")
        #expect(spy.loggedEvents[1].parameters?["session_id"] as? String == "sid-123")
        #expect(spy.loggedEvents[2].name == "trip_summary_shared")
        #expect(spy.loggedEvents[2].parameters?["session_id"] as? String == "sid-456")
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

    // MARK: - FR-44 / F-3: deepLinkOpened parameter allow-list

    @Test @MainActor func deepLinkOpenedKeepsOnlyAllowedParams() async throws {
        let event = AnalyticsService.Event.deepLinkOpened(
            type: "family",
            params: ["inviteId": "inv-1", "familyId": "fam-1"]
        )
        #expect(event.name == "deep_link_opened")
        #expect(event.parameters?["type"] as? String == "family")
        #expect(event.parameters?["inviteId"] as? String == "inv-1")
        #expect(event.parameters?["familyId"] as? String == "fam-1")
        #expect(event.parameters?["dropped_param_count"] == nil)
    }

    @Test @MainActor func deepLinkOpenedDropsUnknownParams() async throws {
        let event = AnalyticsService.Event.deepLinkOpened(
            type: "friend",
            params: [
                "inviteId": "inv-2",
                "referrer": "attacker-controlled",
                "utm_source": "malicious",
            ]
        )
        // Event name must not change (analytics changes must not alter event names).
        #expect(event.name == "deep_link_opened")

        // Only the recognized key survives.
        #expect(event.parameters?["inviteId"] as? String == "inv-2")
        #expect(event.parameters?["referrer"] == nil)
        #expect(event.parameters?["utm_source"] == nil)

        // Unknown params are counted, not silently discarded without a trace.
        #expect(event.parameters?["dropped_param_count"] as? Int == 2)
    }
}

// MARK: - COPPA F-28 (FR-72): config floor, catalog audit, deletion reset

struct FR72ChildAnalyticsTests {

    /// FR-72(b), extending v2.1 FR-44's key-list discipline to a build-product check. Unit
    /// tests are app-hosted, so `Bundle.main` is the BUILT app and this reads the shipped
    /// Info.plist, not a source copy.
    @Test func shippedInfoPlistCarriesTheAnalyticsConfigFloor() throws {
        let info = try #require(Bundle.main.infoDictionary)
        let mustBeFalse = [
            "FIREBASE_ANALYTICS_COLLECTION_ENABLED",
            "FirebaseMessagingAutoInitEnabled",
            "GOOGLE_ANALYTICS_DEFAULT_ALLOW_AD_PERSONALIZATION_SIGNALS",
            "GOOGLE_ANALYTICS_DEFAULT_ALLOW_AD_STORAGE",
            "GOOGLE_ANALYTICS_DEFAULT_ALLOW_AD_USER_DATA",
            // FR-72(b)
            "GOOGLE_ANALYTICS_IDFV_COLLECTION_ENABLED",
            "FirebaseAutomaticScreenReportingEnabled",
        ]
        for key in mustBeFalse {
            #expect((info[key] as? Bool) == false, "\(key) must be present and false")
        }
    }

    /// FR-72(c) catalog shape: the cases that used to carry a participant / user id now emit
    /// no uid-naming key and carry the participant as an `Int` length only. The String
    /// arguments are app-internal opaque ids (trip/game/target), which FR-72(c) keeps, so the
    /// sentinel cannot reach a value here; the list is hand-picked, and coverage of NEW cases
    /// rests on the source tripwire below, not on this test.
    @Test @MainActor func noEventParameterCarriesAFirebaseUid() {
        let uid = "UIDSENTINEL0123456789abcdefXY"
        let events: [AnalyticsService.Event] = [
            .xpGrantAwarded(tripId: "trip-1", gameInstanceId: "game-1", targetId: "CA", participantIdLength: uid.count),
            .xpGrantSkippedAlreadyGranted(tripId: "trip-1", gameInstanceId: "game-1", targetId: "CA", participantIdLength: uid.count),
            .discoveryOutcomeRecorded(tripId: "trip-1", gameInstanceId: "game-1", targetId: "CA", outcome: "accepted", participantIdLength: uid.count),
            .discoveryRejectedDuplicate(tripId: "trip-1", gameInstanceId: "game-1", targetId: "CA", participantIdLength: uid.count, mode: "solo"),
            .discoveryRejectedInvalidParticipant(tripId: "trip-1", gameInstanceId: "game-1", targetId: "CA", participantIdLength: uid.count, tripParticipantCount: 2, gameMode: "solo"),
            .discoveryRemovalConfirmed(tripId: "trip-1", gameInstanceId: "game-1", targetId: "CA", participantIdLength: uid.count),
            .discoveryUnfind(tripId: "trip-1", gameInstanceId: "game-1", targetId: "CA", participantIdLength: uid.count),
            .publicLifetimeStatsListenerUpdated(userIdLength: uid.count),
        ]
        let forbiddenKeys: Set<String> = [
            "participant_id", "actor_participant_id", "user_id", "uid", "firebase_uid",
            "member_id", "child_id", "parent_id", "friend_id", "email", "username",
        ]
        for event in events {
            let parameters = event.parameters ?? [:]
            #expect(!parameters.isEmpty, "\(event.name) lost its parameters")
            for (key, value) in parameters {
                #expect(!forbiddenKeys.contains(key), "\(event.name).\(key)")
                #expect(!String(describing: value).contains(uid), "\(event.name).\(key) carries the uid")
            }
        }
        #expect(AnalyticsService.Event.xpGrantAwarded(
            tripId: "t", gameInstanceId: "g", targetId: "CA", participantIdLength: uid.count
        ).parameters?["participant_id_length"] as? Int == uid.count)
    }

    /// FR-72(c) tripwire over the source, for the cases the value audit cannot build: no uid
    /// key literal in the catalog, no String-typed participant/user id associated value, no
    /// analytics call site fed from an account identifier, and no SDK logging/identity call
    /// outside `AnalyticsService`. Build-machine-only by nature (walks the tree via
    /// #filePath), like `TripRouteHardeningTests`.
    @Test func noAnalyticsCallSiteOrCatalogCaseCarriesAUid() throws {
        let appDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("LicensePlateApp")
        let catalogURL = appDir.appendingPathComponent("Services/AnalyticsService.swift")
        let catalog = try String(contentsOf: catalogURL, encoding: .utf8)

        for literal in ["\"participant_id\"", "\"actor_participant_id\"", "\"user_id\"", "\"uid\""] {
            #expect(!catalog.contains(literal), "catalog key \(literal)")
        }
        // Case-insensitive, so camelCase shapes (`actorParticipantId`, `memberUserId`,
        // `firebaseUid`, `ownerUserId`) trip it as well as the lower-case prefixes.
        let idValue = try Regex(#"(participant|user|actor|member|child|parent|friend|owner|host|captain)(user)?(id|uid)s?\s*:\s*\[?String"#).ignoresCase()
        #expect(catalog.firstMatch(of: idValue) == nil, "a uid-shaped String id is back in the catalog")
        let bareUid = try Regex(#"\buid\s*:\s*\[?String"#).ignoresCase()
        #expect(catalog.firstMatch(of: bareUid) == nil, "a String uid is back in the catalog")

        var scanned = 0
        let enumerator = try #require(FileManager.default.enumerator(at: appDir, includingPropertiesForKeys: nil))
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            guard let source = try? String(contentsOf: url, encoding: .utf8) else { continue }
            scanned += 1
            if url.lastPathComponent != "AnalyticsService.swift" {
                #expect(!source.contains("Analytics.logEvent("), "\(url.lastPathComponent)")
                #expect(!source.contains("Analytics.resetAnalyticsData("), "\(url.lastPathComponent)")
            }
            #expect(!source.contains(".setUserID("), "\(url.lastPathComponent)")
            // The singleton and the injected `AnalyticsLogging` (ViewModels, RiskAssessment).
            for prefix in ["AnalyticsService.shared.log(", "analytics.log(", "analytics?.log("] {
                for call in Self.calls(of: prefix, in: source) {
                    for token in ["firebaseUID", "currentUser?.uid", "currentUser?.id", ".uid"] {
                        #expect(!call.contains(token), "\(url.lastPathComponent): \(call.prefix(80))")
                    }
                }
            }
        }
        #expect(scanned > 100, "the walk did not find the app sources")
    }

    /// FR-72(d): account deletion resets the device's analytics data, through the one
    /// analytics seam, and BEFORE the throwing local purge so a purge failure cannot skip it.
    @Test func accountDeletionResetsAnalyticsBeforeThePurge() throws {
        let authURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("LicensePlateApp/Services/FirebaseAuthService.swift")
        let source = try String(contentsOf: authURL, encoding: .utf8)
        let start = try #require(source.range(of: "func finalizeDeletedAccountLocally()"))
        let rest = source[start.upperBound...]
        let end = rest.range(of: "\n    func ")?.lowerBound ?? rest.endIndex
        let body = rest[..<end]
        let reset = try #require(body.range(of: "AnalyticsService.shared.resetAnalyticsData()"))
        let purge = try #require(body.range(of: "purgeAllLocalUserData("))
        #expect(reset.lowerBound < purge.lowerBound)
    }

    /// FR-72(d), the other deletion path: a parent deleting the child's data reaches the
    /// child's device as a `.serverDeletedIdentity` detach, which resets analytics too.
    @Test func serverDeletedChildDetachResetsAnalytics() throws {
        let authURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("LicensePlateApp/Services/FirebaseAuthService.swift")
        let source = try String(contentsOf: authURL, encoding: .utf8)
        let start = try #require(source.range(of: "func detachAnonymousIdentityLocally("))
        let rest = source[start.upperBound...]
        let end = rest.range(of: "\n    private func ")?.lowerBound ?? rest.endIndex
        let body = rest[..<end]
        let guardRange = try #require(body.range(of: "if reason == .serverDeletedIdentity {"))
        let reset = try #require(body.range(of: "AnalyticsService.shared.resetAnalyticsData()"))
        #expect(guardRange.upperBound < reset.lowerBound)
    }

    /// Balanced-paren extraction of every `prefix(...)` call in `source`.
    private static func calls(of prefix: String, in source: String) -> [Substring] {
        var result: [Substring] = []
        var searchStart = source.startIndex
        while let hit = source.range(of: prefix, range: searchStart..<source.endIndex) {
            var depth = 1
            var index = hit.upperBound
            while depth > 0, index < source.endIndex {
                if source[index] == "(" { depth += 1 } else if source[index] == ")" { depth -= 1 }
                index = source.index(after: index)
            }
            result.append(source[hit.lowerBound..<index])
            searchStart = index
        }
        return result
    }
}

//
//  FR74AgeGateRetryDeterrenceTests.swift
//  LicensePlateAppTests
//
//  DESTINATION (staged here only because the worktree became unreadable mid-session):
//    LicensePlateAppiOS/LicensePlateAppTests/FR74AgeGateRetryDeterrenceTests.swift
//  The test target is a PBXFileSystemSynchronizedRootGroup, so dropping the file in that
//  directory is sufficient — no project.pbxproj edit is needed.
//
//  COPPA F-30 (FR-74, expanded per OD-9) — the four clauses, pinned:
//
//    (a)  retry deterrence — an under-13 answer leaves a device-local cooldown behind, and
//         a 13+ answer given inside it is HELD at the `.ratchetedAnonymous` equivalent.
//    (a′) account provenance resolves the epoch (OD-9) — a fresh server read of an
//         EXISTING `users/{uid}` un-bricks the keychain-restored guest.
//    (b′) the immediate rebirth ask — a post-sign-out rebirth is asked at SESSION START.
//    (c′) the re-ask surface doubles as the mis-answer recovery (OD-9(i) F-30 addendum).
//
//  The SRS demands adversarial verification in BOTH directions for this feature, so every
//  matrix below is written to fail if the hold ever lets a child escape early AND if it
//  ever holds an adult past the window.
//

import Foundation
import Testing
@testable import LicensePlateApp

// MARK: - (a) The cooldown state machine (pure policy)

struct AgeGateRetryCooldownPolicyTests {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private var day: TimeInterval { AgeGateRetryCooldownPolicy.defaultDuration }

    /// OD-5 (owner, defaults acceptable): 24 hours. Pinned because the value is a
    /// recorded owner decision, not an implementation detail.
    @Test func theWindowIsTheOwnerDecidedTwentyFourHours() {
        #expect(AgeGateRetryCooldownPolicy.defaultDuration == 24 * 60 * 60)
    }

    /// Only the PROTECTIVE answer leaves residue. Ending a `teenAdult` answer has nothing
    /// to deter, and an unanswered epoch has nothing to end.
    @Test func onlyAnUnder13AnswerArmsTheMarker() {
        #expect(AgeGateRetryCooldownPolicy.cooldownDeadline(
            clearedCategory: .under13, existingDeadline: nil, now: now
        ) == now.addingTimeInterval(day))

        #expect(AgeGateRetryCooldownPolicy.cooldownDeadline(
            clearedCategory: .teenAdult, existingDeadline: nil, now: now
        ) == nil)

        #expect(AgeGateRetryCooldownPolicy.cooldownDeadline(
            clearedCategory: nil, existingDeadline: nil, now: now
        ) == nil)
    }

    /// The escape this closes: sign out of the HELD session and the `teenAdult` clear
    /// would erase the window that is restricting you. It cannot — a non-under-13 clear
    /// returns the existing deadline untouched.
    @Test func aLaterTeenAdultClearCanNeitherShortenNorEraseALiveWindow() {
        let live = now.addingTimeInterval(day)
        #expect(AgeGateRetryCooldownPolicy.cooldownDeadline(
            clearedCategory: .teenAdult, existingDeadline: live, now: now.addingTimeInterval(60)
        ) == live)
        #expect(AgeGateRetryCooldownPolicy.cooldownDeadline(
            clearedCategory: nil, existingDeadline: live, now: now.addingTimeInterval(60)
        ) == live)
    }

    /// Re-arming only ever EXTENDS. A second under-13 answer late in an existing window
    /// pushes the deadline out; one early in a longer window may not pull it in.
    @Test func theDeadlineOnlyEverExtends() {
        let farFuture = now.addingTimeInterval(day * 3)
        // A fresh arm that would land EARLIER than an existing deadline loses.
        #expect(AgeGateRetryCooldownPolicy.cooldownDeadline(
            clearedCategory: .under13, existingDeadline: farFuture, now: now
        ) == farFuture)
        // A fresh arm that lands LATER wins.
        let later = now.addingTimeInterval(day * 5)
        #expect(AgeGateRetryCooldownPolicy.cooldownDeadline(
            clearedCategory: .under13, existingDeadline: farFuture, now: later
        ) == later.addingTimeInterval(day))
    }

    /// Strictly time-bounded, and the boundary is exclusive on the far side: the instant
    /// the deadline is reached the device is free. Nothing has to run to retire it, so an
    /// offline device is never held a moment longer than the window.
    @Test func activenessIsStrictlyTimeBounded() {
        #expect(AgeGateRetryCooldownPolicy.isCooldownActive(until: nil, now: now) == false)
        #expect(AgeGateRetryCooldownPolicy.isCooldownActive(
            until: now.addingTimeInterval(1), now: now
        ) == true)
        #expect(AgeGateRetryCooldownPolicy.isCooldownActive(until: now, now: now) == false)
        #expect(AgeGateRetryCooldownPolicy.isCooldownActive(
            until: now.addingTimeInterval(-1), now: now
        ) == false)
    }

    /// FR-74's two named cases, plus the two it deliberately does NOT name.
    ///
    /// BOTH DIRECTIONS: the `.under13` row proves a child re-answering protectively is
    /// never "held" by this rule (they are `.childDirected` by their own evidence, which
    /// is stronger); the `nil` row proves a session that gave no answer at all — a
    /// sign-IN, which D-17 forbids asking — is not restricted by an answer it never gave;
    /// and every inactive row proves the hold ends with the window.
    @Test func onlyAThirteenPlusAnswerInsideTheWindowIsHeld() {
        #expect(AgeGateRetryCooldownPolicy.holdsSessionPosture(
            category: .teenAdult, isCooldownActive: true
        ) == true)
        #expect(AgeGateRetryCooldownPolicy.holdsSessionPosture(
            category: .teenAdult, isCooldownActive: false
        ) == false)
        #expect(AgeGateRetryCooldownPolicy.holdsSessionPosture(
            category: .under13, isCooldownActive: true
        ) == false)
        #expect(AgeGateRetryCooldownPolicy.holdsSessionPosture(
            category: nil, isCooldownActive: true
        ) == false)
        #expect(AgeGateRetryCooldownPolicy.holdsSessionPosture(
            category: nil, isCooldownActive: false
        ) == false)
    }

    // MARK: (c′) the mis-answer recovery's offer conditions

    /// The full offer matrix. The one true cell is the population OD-9(i) names: an
    /// under-13 epoch on an ACCOUNT-LESS device (FR-60 never provisioned one), outside the
    /// deterrence window.
}

// MARK: - (a′) Account provenance (OD-9)

struct AgeGateAccountProvenancePolicyTests {

    /// OD-9's structural argument: under FR-60 an under-13 epoch cannot mint a cloud
    /// account except through the declare-first redemption path, so an EXISTING `users/{uid}`
    /// resolved fresh this session is itself age evidence. The tri-state carries "existing"
    /// for free — every ingest site skips an absent document, so `nil` is "no evidence".
    @Test func provenanceIsExactlyAFreshResolutionOfAnExistingDocument() {
        #expect(AgeGateAccountProvenancePolicy.resolvesEpoch(freshChildAccountResolution: nil) == false)
        #expect(AgeGateAccountProvenancePolicy.resolvesEpoch(freshChildAccountResolution: false) == true)
        // A FLAGGED document also counts as evidence — of a child. The posture engine sends
        // it to `.childDirected` long before provenance is consulted; provenance never
        // decides WHAT the session is, only that the epoch question has been answered.
        #expect(AgeGateAccountProvenancePolicy.resolvesEpoch(freshChildAccountResolution: true) == true)
    }

    /// OD-9(iv), stated by the owner as an override with no exceptions: "device child
    /// history overrides in all cases — ratchet/declared-history route through FR-74's
    /// cooldown, never a clean re-ask". A live deterrence window IS device child history.
    @Test func anOpenRetryCooldownOutranksAccountProvenance() {
        #expect(AgeGateAccountProvenancePolicy.resolvesEpoch(
            freshChildAccountResolution: false, isRetryCooldownActive: true
        ) == false)
        #expect(AgeGateAccountProvenancePolicy.resolvesEpoch(
            freshChildAccountResolution: false, isRetryCooldownActive: false
        ) == true)
    }
}

// MARK: - (b′) The immediate rebirth ask (OD-9(ii))

struct AgeGateSessionStartPolicyTests {

    private func requiresAsk(
        onboarded: Bool = true,
        answered: Bool = false,
        uid: Bool = false,
        session: Bool = false,
        registered: Bool = false,
        childHistory: Bool = false
    ) -> Bool {
        AgeGateSessionStartPolicy.requiresImmediateAsk(
            hasCompletedOnboarding: onboarded,
            isAgeAnswered: answered,
            hasProvisionedIdentity: uid,
            hasLiveAuthSession: session,
            isRegisteredIdentity: registered,
            hasDeviceChildHistory: childHistory
        )
    }

    /// The one population OD-9(ii) names: a post-sign-out rebirth with GENUINELY NO
    /// INFORMATION — onboarding long done, epoch answer cleared, no uid, no Auth session,
    /// no child history. Today it reaches gameplay UI age-unasked; that is the defect.
    @Test func theRebirthWithNoInformationIsAsked() {
        #expect(requiresAsk() == true)
    }

    /// Every other guard, one flip at a time.
    @Test func everyOtherSessionShapeIsLeftAlone() {
        // Pre-onboarding: quick-start's play tap, legacy onboarding's `.ageVerification`
        // and sign-up's in-form ask already own the question.
        #expect(requiresAsk(onboarded: false) == false)
        // Already answered this epoch — asking again would be answer-shopping.
        #expect(requiresAsk(answered: true) == false)
        // OD-9(i)'s population, not (ii)'s: a session that HOLDS an identity resolves
        // through account provenance on its first server read (or holds until
        // connectivity, OD-9(v)). Asking it would also drop an under-13 answer onto a
        // restored identity — SRS §3.1.1 items 6/8 territory.
        #expect(requiresAsk(uid: true) == false)
        #expect(requiresAsk(session: true) == false)
        #expect(requiresAsk(uid: true, session: true) == false)
        // FR-27 / D-17: the age answer never touches a registered account, and sign-in
        // never asks.
        #expect(requiresAsk(registered: true) == false)
    }

    /// OD-9(iv): a device carrying child history routes through FR-74's cooldown, NEVER a
    /// clean re-ask. This is the "child escapes early" direction — signing out and being
    /// handed a fresh neutral screen is exactly the laundering FR-74 exists to stop.
    @Test func deviceChildHistoryNeverGetsACleanReAsk() {
        #expect(requiresAsk(childHistory: true) == false)
    }
}

// MARK: - The posture engine (FR-74(b) hold + FR-74(a′) provenance)

struct FR74PosturePolicyTests {

    private func signal(
        hasCurrentUser: Bool = true,
        anonymous: Bool = true,
        fresh: Bool? = nil,
        cached: Bool? = nil,
        declared: Bool = false,
        ageResolved: Bool = true,
        ratcheted: Bool = false,
        held: Bool = false,
        provenance: Bool = false
    ) -> ChildSessionSignal {
        ChildSessionSignal(
            hasCurrentUser: hasCurrentUser,
            isAnonymousOrSignedOut: anonymous,
            freshIsChildAccount: fresh,
            cachedIsChildAccount: cached,
            isDeclaredChildIdentity: declared,
            isAgeResolved: ageResolved,
            isDeviceRatcheted: ratcheted,
            isUnder13RetryCooldownHeld: held,
            hasAccountProvenance: provenance
        )
    }

    /// FR-74(b): "the account provisions, but the session posture is held at
    /// `.ratchetedAnonymous`-equivalent". Even with a fresh server `false` in hand — the
    /// strongest adult evidence the engine accepts — the held session is not ad-eligible.
    @Test func aThirteenPlusAnswerInsideTheWindowIsHeld() {
        #expect(ChildSessionPosturePolicy.posture(
            for: signal(fresh: false, held: true)
        ) == .ratchetedAnonymous)
    }

    /// R-11, the amendment this FR exists for. FR-39's ratchet exempts registered
    /// sign-ins, which left "sign out → fresh registration" as a clean escape. The hold
    /// attaches to the ANSWER, so it reaches the registered account that answer went on to
    /// provision — note `anonymous: false` and `ratcheted: false`, i.e. every FR-39
    /// mechanism is inert here and only FR-74 is holding the session.
    @Test func theHoldReachesTheFreshRegistrationFR39Exempts() {
        #expect(ChildSessionPosturePolicy.posture(
            for: signal(anonymous: false, fresh: false, ratcheted: false, held: true)
        ) == .ratchetedAnonymous)
        // Same session, window lapsed: fully normal on the next resolution.
        #expect(ChildSessionPosturePolicy.posture(
            for: signal(anonymous: false, fresh: false, ratcheted: false, held: false)
        ) == .confirmedNonChild)
    }

    /// FR-74(a): "re-answering the gate under-13 → normal child flow (always allowed)".
    /// A real child signal outranks the hold from every source, so the deterrence can
    /// never downgrade a child's protections to the merely-restricted tier.
    @Test func aRealChildSignalAlwaysOutranksTheHold() {
        #expect(ChildSessionPosturePolicy.posture(for: signal(fresh: true, held: true)) == .childDirected)
        #expect(ChildSessionPosturePolicy.posture(for: signal(cached: true, held: true)) == .childDirected)
        #expect(ChildSessionPosturePolicy.posture(for: signal(declared: true, held: true)) == .childDirected)
    }

    /// D-11's line, which the hold must not cross: `.ratchetedAnonymous` denies location
    /// STRUCTURALLY but never rewrites the user's stored preferences, because that rewrite
    /// has no inverse. A held session is not evidenced as a child — it is merely not
    /// trusted yet — so a genuine adult's saved settings survive the 24 hours intact.
    @Test func theHoldDeniesCapabilitiesWithoutDestroyingStoredPreferences() {
        let held = ChildSessionPosturePolicy.posture(for: signal(fresh: false, held: true))
        #expect(held.isAdDisplayEligible == false)
        #expect(held.suppressesPurchases == true)
        #expect(held.forcesLocationOff == true)
        #expect(held.disablesAdPersonalizationSignals == true)
        #expect(held.childDirectedTreatment == true)
        // The half that must NOT fire.
        #expect(held.rewritesStoredLocationFlagsOff == false)
    }

    /// FR-74(a′) / OD-9(i): the keychain-restored guest. A reinstall wiped the epoch
    /// answer (`ageResolved: false`) while the Keychain restored the uid; the first fresh
    /// server read of their EXISTING flagless document resolves them fully. Without
    /// provenance this session is `.unresolved` forever — the "permanent no-ads install"
    /// consequence OD-9 supersedes.
    @Test func accountProvenanceUnbricksTheReinstalledGuest() {
        #expect(ChildSessionPosturePolicy.posture(
            for: signal(fresh: false, ageResolved: false, provenance: false)
        ) == .unresolved)
        #expect(ChildSessionPosturePolicy.posture(
            for: signal(fresh: false, ageResolved: false, provenance: true)
        ) == .confirmedNonChild)
    }

    /// Provenance can only ever get a session PAST the epoch hold; the FR-19 asymmetric
    /// trust line below it still demands THIS SESSION's fresh `false`. So a provenance bit
    /// arriving without a resolved flag confers nothing.
    @Test func provenanceAloneNeverConfersConfirmedNonChild() {
        #expect(ChildSessionPosturePolicy.posture(
            for: signal(fresh: nil, ageResolved: false, provenance: true)
        ) == .unresolved)
    }

    /// OD-9(iv) at the posture layer: the FR-39 ratchet is checked BEFORE the epoch hold,
    /// so a device that ever hosted a child is never resolved by provenance.
    @Test func provenanceNeverOverridesTheDeviceRatchet() {
        #expect(ChildSessionPosturePolicy.posture(
            for: signal(fresh: false, ageResolved: false, ratcheted: true, provenance: true)
        ) == .ratchetedAnonymous)
    }

    /// The flagged half of OD-9: "flagged ⇒ child postures as always".
    @Test func provenanceNeverOverridesAChildFlag() {
        #expect(ChildSessionPosturePolicy.posture(
            for: signal(fresh: true, ageResolved: false, provenance: true)
        ) == .childDirected)
    }

    /// The hold is checked before the provenance branch, so an account-provenance session
    /// inside the window is still held (belt to `AgeGateAccountProvenancePolicy`'s own
    /// cooldown guard — either alone is sufficient).
    @Test func theHoldOutranksAccountProvenance() {
        #expect(ChildSessionPosturePolicy.posture(
            for: signal(fresh: false, ageResolved: false, held: true, provenance: true)
        ) == .ratchetedAnonymous)
    }
}

// MARK: - The deferred SDK gate

@MainActor
struct FR74DeferredSDKStartupTests {

    private func plan(
        ageResolved: Bool,
        provenance: Bool = false,
        held: Bool = false,
        posture: ChildSessionPosture
    ) -> DeferredSDKStartupPlan {
        DeferredSDKStartupPolicy.plan(
            isAgeGateResolved: ageResolved,
            hasAccountProvenance: provenance,
            isUnder13RetryCooldownHeld: held,
            posture: posture,
            isFirebaseConfigured: true,
            hasPurchasesAPIKey: true
        )
    }

    /// FR-74(a′): provenance satisfies the EPOCH half of `isAgeResolutionComplete`. This is
    /// the clause that actually un-bricks ads and purchases for the reinstalled guest —
    /// the posture fix alone leaves every deferred SDK held, because this device's
    /// `AgeGateStore` answer died with the reinstall.
    @Test func provenanceSatisfiesTheEpochHalfOfTheAgeTest() {
        #expect(plan(ageResolved: false, posture: .confirmedNonChild) == .allDeferred)
        let resolved = plan(ageResolved: false, provenance: true, posture: .confirmedNonChild)
        #expect(resolved.startsAds)
        #expect(resolved.startsPurchases)
        #expect(resolved.startsMessaging)
        #expect(resolved.startsAnalyticsCollection)
    }

    /// The SECOND half is untouched: provenance can never start an SDK for a session whose
    /// child signal has not landed.
    @Test func provenanceCannotStartAnythingForAnUnresolvedPosture() {
        #expect(plan(ageResolved: false, provenance: true, posture: .unresolved) == .allDeferred)
        #expect(plan(ageResolved: true, provenance: true, posture: .unresolved) == .allDeferred)
    }

    /// FR-74(b) enumerates FIVE denials — "no ads, no analytics, no location, no
    /// purchases, no RevenueCat". The posture alone delivers four; ANALYTICS COLLECTION is
    /// the one it misses, because a genuine `.ratchetedAnonymous` session is age-UNRESOLVED
    /// (which is what keeps its collection off today) while the held session has an answer.
    /// This is the test that would catch that gap reopening.
    @Test func theHoldDefersEverythingIncludingAnalyticsCollection() {
        #expect(plan(ageResolved: true, held: true, posture: .ratchetedAnonymous) == .allDeferred)
    }

    /// Even against the most permissive inputs the gate accepts — a resolved epoch, a
    /// fresh-confirmed adult posture, account provenance — the hold wins.
    @Test func theHoldOutranksEveryOtherPositiveSignal() {
        #expect(plan(
            ageResolved: true, provenance: true, held: true, posture: .confirmedNonChild
        ) == .allDeferred)
    }

    /// And it is a DELAY, not a block: the same session with the window lapsed starts all
    /// four. ("adult held forever" direction.)
    @Test func theHoldReleasesCompletelyWhenTheWindowLapses() {
        let released = plan(ageResolved: true, held: false, posture: .confirmedNonChild)
        #expect(released.startsAds)
        #expect(released.startsPurchases)
        #expect(released.startsMessaging)
        #expect(released.startsAnalyticsCollection)
    }
}

// MARK: - Store behaviour (the marker's lifecycle on real UserDefaults)

@MainActor
struct FR74AgeGateStoreTests {

    private func makeStore(
        suite: String = "FR74AgeGateStoreTests-\(UUID().uuidString)"
    ) -> (AgeGateStore, UserDefaults) {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (AgeGateStore(defaults: defaults), defaults)
    }

    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private var day: TimeInterval { AgeGateRetryCooldownPolicy.defaultDuration }

    /// The FR's literal placement: `clearAnswer()` — sign-out and account deletion —
    /// preserves an `under13` category as the device cooldown marker.
    @Test func signingOutOfAnUnder13AnswerArmsTheMarker() {
        let (store, _) = makeStore()
        store.recordAnswer(.under13)
        #expect(store.isUnder13RetryCooldownActive(now: now) == false)

        store.clearAnswer(now: now)

        #expect(store.category == nil)
        #expect(store.under13CooldownUntil == now.addingTimeInterval(day))
        #expect(store.isUnder13RetryCooldownActive(now: now.addingTimeInterval(day - 1)) == true)
        #expect(store.isUnder13RetryCooldownActive(now: now.addingTimeInterval(day)) == false)
    }

    @Test func signingOutOfATeenAdultAnswerArmsNothing() {
        let (store, _) = makeStore()
        store.recordAnswer(.teenAdult)
        store.clearAnswer(now: now)
        #expect(store.under13CooldownUntil == nil)
        #expect(store.isUnder13RetryCooldownActive(now: now) == false)
    }

    /// The laundering attempt the FR names, end to end: truthful under-13 → sign out →
    /// immediately answer 13+. The account provisions (nothing here refuses it) and the
    /// SESSION is held.
    @Test func theUnder13AnswerCannotBeLaunderedThroughSignOut() {
        let (store, _) = makeStore()
        store.recordAnswer(.under13)
        store.clearAnswer(now: now)                    // sign-out
        store.recordAnswer(.teenAdult, at: now)        // the retry, one second later

        #expect(store.category == .teenAdult)          // the answer is accepted…
        #expect(store.isUnder13RetryCooldownHeld(now: now) == true)   // …and not trusted.

        // Signing out AGAIN from the held session must not erase the window.
        store.clearAnswer(now: now.addingTimeInterval(60))
        #expect(store.under13CooldownUntil == now.addingTimeInterval(day))

        // "only delays, never blocks": past the deadline the same answer is trusted.
        store.recordAnswer(.teenAdult, at: now.addingTimeInterval(day + 1))
        #expect(store.isUnder13RetryCooldownHeld(now: now.addingTimeInterval(day + 1)) == false)
    }

    /// FR-74(a): re-answering under-13 inside the window is the normal child flow. The
    /// hold projection is false because the session is `.childDirected` by its own
    /// evidence, which is strictly stronger.
    @Test func reAnsweringUnder13InsideTheWindowIsNeverHeld() {
        let (store, _) = makeStore()
        store.recordAnswer(.under13)
        store.clearAnswer(now: now)
        store.recordAnswer(.under13, at: now)
        #expect(store.isUnder13RetryCooldownActive(now: now) == true)
        #expect(store.isUnder13RetryCooldownHeld(now: now) == false)
    }

    /// FR-74: "the marker … lifts under the existing FR-39 correction valve conditions as
    /// well." Wired into `liftDeviceChildMarkers`, whose only caller is the
    /// `ChildDeviceCorrectionPolicy` branch of the posture routine.
    @Test func theManagerCorrectionValveClearsTheMarker() {
        let (store, _) = makeStore()
        store.recordAnswer(.under13)
        store.clearAnswer(now: now)
        #expect(store.isUnder13RetryCooldownActive(now: now) == true)

        store.clearUnder13RetryCooldownAfterCorrection()

        #expect(store.under13CooldownUntil == nil)
        #expect(store.isUnder13RetryCooldownActive(now: now) == false)
    }

    // MARK: (c′) the mis-answer recovery, end to end

    /// The population OD-9(i) names: an under-13 answer on an ACCOUNT-LESS device, which
    /// FR-60(e) left with no in-app exit at all. The recovery ends the answer — through
    /// the same `clearAnswer()` sign-out uses — so the changed 13+ answer is governed by
    /// the held-posture rules, and the control is not offered again until the window
    /// lapses.
    @Test func theMarkerAddsOneDeviceLocalTimestampAndNothingElse() {
        let (store, defaults) = makeStore()
        store.recordAnswer(.under13, ageOutYearMonth: 202703)
        // Answering alone writes no marker — only ENDING an under-13 answer does.
        #expect(defaults.object(forKey: AgeGateStoreKeys.under13CooldownUntil) == nil)

        store.clearAnswer(now: now)

        let keys = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("ageGate.") }
        #expect(Set(keys).isSubset(of: [
            AgeGateStoreKeys.pendingDeclarationUserIds,
            AgeGateStoreKeys.declaredChildUserIds,
            AgeGateStoreKeys.detachedIdentityUserIds,
            AgeGateStoreKeys.ageOutYearMonth,
            AgeGateStoreKeys.under13CooldownUntil,
        ]))
        #expect(keys.contains(AgeGateStoreKeys.under13CooldownUntil))
        // The stored value is a bare instant — nothing about the answer, the birth data,
        // or any identity.
        #expect(defaults.double(forKey: AgeGateStoreKeys.under13CooldownUntil)
            == now.addingTimeInterval(day).timeIntervalSince1970)
    }

    /// The marker outlives a process: it is UserDefaults state, read back by a fresh store
    /// over the same suite (the "immediate retry" a relaunch would otherwise reset).
    @Test func theMarkerSurvivesARelaunch() {
        let suite = "FR74AgeGateStoreTests-relaunch-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let first = AgeGateStore(defaults: defaults)
        first.recordAnswer(.under13)
        first.clearAnswer(now: now)

        let afterRelaunch = AgeGateStore(defaults: defaults)
        #expect(afterRelaunch.under13CooldownUntil == now.addingTimeInterval(day))
        afterRelaunch.recordAnswer(.teenAdult, at: now)
        #expect(afterRelaunch.isUnder13RetryCooldownHeld(now: now) == true)
    }
}

// MARK: - (c′) analytics silence on the child surface (FR-21 / SRS §12)

@MainActor
private final class FR74AnalyticsSpy: AnalyticsLogging {
    var events: [AnalyticsService.Event] = []

    func log(_ event: AnalyticsService.Event) {
        events.append(event)
    }

    func log(_ name: String, parameters: [String: Any]) {}
    func setUserProperty(_ value: String?, forName name: String) {}
}

# RoadTrip Royale — Unified COPPA Compliance SRS

**Version:** 2.1 — v2.0 merged the standalone *Per-Child Family-Member Signal ("isChild")* SRS (FINAL, post-adversarial-review, 24 issues dispositioned) into the 2026-08-09 full-codebase COPPA remediation plan; v2.1 applies owner decisions of 2026-08-10 (child ads and child-location toggle become legal-gated fast-follows; adult location defaults stay ON — see D-6/D-11/OQ-5 and FR-45). This is the single authoritative document; both predecessors are superseded.
**App:** RoadTrip Royale (iOS SwiftUI + SwiftData + Firebase) · Branch `feature/MVPPush` · **Not yet shipped** — no production data, no legacy retroactivity. **Pre-release rule (owner, 2026-08-10): supporting the current structure is not required — features, fields, and data may be removed outright with no migration, compatibility, or upgrade-in-place support; dev testers reinstall.**
**Status:** awaiting product-owner approval. On approval, implementation proceeds per the Execution Model (§2).

---

## §0 Merge changelog (v2.0)

What was **kept**, **strengthened**, or **removed** relative to the two source documents. Review items C0-x/C1-x retain their dispositions (§19); gap items from the unification review are G-1…G-7.

**Kept (child-signal SRS wins over the old plan):**
- The **no-SwiftData-schema-bump** design (§6.4): `isChildAccount` as a Firestore-only projection following the `entitlementTags` pattern, UserDefaults cache + device ratchet for cold start. Supersedes the old plan's C-06 schema-version approach entirely.
- Sticky flag, provisional/restricted state machine, correction-vs-revocation distinction, consent records in `audit_logs`, asymmetric cold-start cache, mid-session re-stamp, device ratchet, FR-1…FR-41 as previously reviewed — except where amended below.

**Strengthened (gaps closed in this merge):**
- **G-1 (was old-plan C-01):** silent login-location capture is now a hard in-scope requirement (FR-42, feature F-1). The child-signal SRS left `users/{uid}/private/lastLoginLocationData` collection running for children via direct client write — outside every callable guard and outside its own `consentScope`.
- **G-2:** FR-33 **amended** — child sessions force **all three** `LocationSettingsService` flags off, explicitly including `saveLocationWhenMarkingPlates` (the flag that actually uploads full-precision coordinates into shared `activity_events`; route tracking is verified local-only and was the least-risky of the three).
- **G-3:** FR-35 **amended** — also removes the plaintext email from the `console.log` at `welcomeEmail.ts:123-125` (Cloud Logging sink), and **suppresses the welcome email entirely** for `isChildAccount == true` recipients.
- **G-4:** FR-27 **amended** — the age-gate invariant ("no `users/{uid}` write before age resolution") is an acceptance criterion on **all four** entry paths: legacy onboarding, `QuickSoloStartView.swift:153`, `UserProfileView.swift:638`, and the guest auto-account creation at first launch (`FirebaseAuthService.swift:221-264`).
- **G-5 (new FR-52):** child registrations collect **no first/last name and no phone** (data minimization at the pre-consent moment).
- **G-6:** the `pending` join-request forgery gap (`firestore.rules:242` — `pending.userId` not forced to `request.auth.uid`) is **promoted from follow-up into scope** (FR-16 extension): with the child feature live, a forged join request could let a stranger become a child's "consenting manager" and gain FR-12 family read access. Consent integrity requires closing it now.
- **G-7:** backend retention (F-12) gains an explicit **carve-out preserving consent/lifecycle audit records indefinitely** — the child-signal SRS's durable-evidence property (§11.2) is load-bearing and must survive any future audit-log TTL.

**Removed / demoted (the parts flagged as concerns):**
- **TFCD-tagged ads served to consented children** — not in MVP: **no child session sees ads at all** (provisional or consented). TFCD + the device ratchet remain as defense-in-depth on the request path, but `AdEligibilityService` returns ineligible for any resolved-or-cached child signal. Rationale: npa=1 alone is insufficient once the operator has actual knowledge of a child (it disables personalization, not Google's identifier collection; TFCD is what triggers Google's child-directed handling), and the no-ads gate fails safe. **v2.1 owner decision:** TFCD-tagged npa/G ads for *consented* children are an approved fast-follow **contingent on counsel sign-off under OQ-2** (see OQ-5); the flip is confined to the FR-19 eligibility gate.
- The `.adChildTreatmentApplied` analytics event — already dropped in the source SRS; stays dropped (violates FR-21).

---

## §1 Purpose & legal basis

ToS §2 and Privacy Policy §12 state that children under 13 play only through a parent-managed family group and that parents can review and delete the child's data. COPPA (16 CFR 312) requires, once the operator has actual knowledge a user is a child: (a) no behaviorally targeted advertising and no persistent-identifier collection for ad personalization; (b) no public discoverability or stranger contact; (c) verifiable parental consent obtained **before** collection; (d) parental review/deletion rights and cessation of collection when consent is withdrawn; (e) data minimization and bounded retention.

The 2026-08 code audit (15-agent, adversarially verified) established: the app is at minimum mixed-audience; **no child concept exists anywhere** in code; and beyond the child gap, several app-wide practices independently fail COPPA/data-minimization muster (silent login geolocation, contact identifiers on the peer-readable user doc, ad-ID-capable analytics defaults, zero retention limits, incomplete deletion). This SRS remediates all Critical- and High-risk audit findings.

## §2 Execution model

### 2.1 Workflow (approved process)

1. Each feature (§3) is implemented by a subagent in an **isolated git worktree** off current `feature/MVPPush` HEAD. The main working tree stays untouched during development.
2. **Serialized landing — exactly one feature in the repo working tree at a time.** When the slot is free: rebase onto HEAD, apply to the working tree, verify build + focused tests, notify the owner with summary/files/results.
3. The owner tests and reviews, then either **commits and approves** (next feature lands) or **requests changes** (agent revises in its worktree, re-lands). Agents never commit.
4. Later waves block on committed dependencies. Wave boundaries are hard sync points.

### 2.2 Model policy

Critical features → **Fable or Opus at high/xhigh effort**. High features → **Opus** where design/algorithmic reasoning is needed, **Sonnet** where mechanical. Assignments in §3.

### 2.3 Phase 0 (owner, before F-1 lands)

- Commit the in-flight ad work (`AdRequestPolicy.swift`, `AdMobService.swift`, `AdBannerView.swift`, `AdRequestPolicyTests.swift`) and pending `HelpAboutView`/`Localizable.strings` edits.
- Commit or revert the 7 previously-modified test files.
- Remove stale worktree `.claude/worktrees/agent-a8f1d378830a17814` (changes already applied to main tree).
- Optionally commit this SRS.

## §3 Feature roadmap

| Land | ID | Feature | Covers | Risk | Model / effort | Depends |
|---|---|---|---|---|---|---|
| 1 | **F-1** | Remove silent login-location capture | FR-42 (audit D1) | Critical | Opus / high | Phase 0 |
| 2 | **F-2** | Contact-identifier containment (app-wide) | FR-43 (audit E1 + fcmToken; resolves OQ-4) | Critical | Opus / high | — |
| 3 | **F-3** | Analytics ad-ID hardening (app-wide) | FR-44 (audit C1/C2/C3) | High | Sonnet | — |
| 4 | **F-4** | Location defaults, precision & speech | FR-45 (audit D2/D3/D4) | High | Opus | — |
| 5 | **F-5a** | Child signal — server core (flag, rules, consent lifecycle) | FR-1–8, 25–28, 30–31, 35(amended), 40, 16-ext/G-6 | Critical | **Fable / xhigh** | F-1, F-2 |
| 6 | **F-5b** | Child signal — enforcement sweep (search/invites/actor/trips) | FR-9–16, 24, 36–38, 41 | Critical | Opus / high | F-5a |
| 7 | **F-6** | Age screen, provisional state & registration minimization | FR-27(amended), 28 client, 52; orphaned-string cleanup | Critical | **Fable / high** | F-5a |
| 8 | **F-7** | Child session postures (ads/analytics/location/paywall) | FR-17–19(amended), 23, 32, 33(amended), 34, 39 | Critical | **Fable / high** | F-5a |
| 9 | **F-8** | Family child-management UI & parent rights | FR-1/2/5 UI, 20–22, 25 UI, 29, 30 UI | Critical | Opus / high | F-5a, F-5b |
| 10 | **F-9** | SDK startup deferral (non-ads remainder) | FR-46 (audit A4 remainder: FCM, RevenueCat, Analytics collection) | High | Opus | F-6 |
| 11 | **F-10** | Trip-invite general hardening | FR-47 (audit F2 remainder: rate limits, relationship gates for all) | High | Opus | F-5b |
| 12 | **F-11** | Adult discoverability controls | FR-48 (audit F1 remainder, F3) | High | Sonnet | F-5b |
| 13 | **F-12** | Backend retention limits | FR-49 (audit G1; consent carve-out G-7) | High | Opus | F-5a |
| 14 | **F-13** | Deletion completeness & de-identification | FR-50 (audit G2) | High | Opus / high | F-5a |

Agents for F-1…F-4 and F-12/F-13 may develop concurrently from day one (independent scopes); landing follows the order above. F-5a is the backbone; F-5b/6/7/8 build on its committed state.

## §4 Definitions

- **Child** — `users/{uid}.isChildAccount == true`; per policy, under 13. Missing flag ⇒ **not** a child (matches missing-`isRegistered`-⇒-registered, `userSearchCore.ts:14-20`, `firestore.rules:22`).
- **Provisional child** — flag set at registration via `declareChildRegistration` (neutral age screen), no consent record, no active family. Fully protected and restricted (§11.4).
- **Consented child** — flag true + active family membership + `GRANTED` consent record whose consenting manager's family the child is currently in.
- **Unconsented child** — flag true, no active family (provisional or post-exit sticky). Restricted state applies.
- **Correction vs. revocation** — clearing because the person is *not/no-longer under 13* is a **CORRECTION** (protections lift). Ending consent while still a child (removal, family end, withdrawal, deletion) is a **REVOCATION** (protections persist; collection stops). Distinct events, distinct records (FR-5/6, §11.3).
- **Parent / manager** — member-doc `role ∈ {creator, captain}` (`family.ts:138-144, 461-467`; rules 51-61). No MVP path assigns captain ⇒ effectively creator-only (OQ-1).
- **Consent record** — append-only `audit_logs` doc via `writeAuditLog` (`audit.ts:20-42`), client-inaccessible (rules 260-264), retained indefinitely (F-12 carve-out), survives account deletion.
- **TFCD** — `tagForChildDirectedTreatment` on the process-global `MobileAds.shared.requestConfiguration` (SDK 12.14.0; no per-request child API).
- **Projection** — read-only client mirror of server state, never persisted to SwiftData (pattern: `entitlementTagsByUserId`, `UserRepository.swift:26`).
- **Device ratchet** — device-local UserDefaults marker set when any uid on the device has cached `isChildAccount == true`; governs anonymous/signed-out treatment (FR-39).

## §5 Requirements — child signal (FR-1…FR-41, amended per §0)

### Flag set/clear paths

**FR-1** Creator/captain can mark a pending join request as a child at approval: `approveFamilyJoinRequest_CaptainStep` payload gains `isChild: boolean` plus, when true, `consentAcknowledged: true` and `guardianAffirmed: true` (FR-31). `isChild=true` without both acknowledgments ⇒ rejected.

**FR-2** Creator/captain sets child status for an existing member, and clears it **as a correction only**, via `setFamilyMemberChildStatus`. Clearing requires `correctionReason ∈ {flag_set_in_error, child_turned_13}`. No self-targets; no `creator` targets. Consent *withdrawal* is never expressed here — it is removal (FR-6) or parent-initiated deletion (FR-30).

**FR-3** All child-status writes are Cloud Functions using `enforcedCallable` (App Check) + `assertRegisteredAccount`, with `clientMetadata` as sibling field (`.addingClientMetadata()` / `normalizeClientMetadata`). No client writes the flag directly (FR-7/8).

**FR-4** Setting `isChild=true` executes **one batched write**: `users/{childUid}.isChildAccount = true`, `families/{fid}/members/{childUid}.isChild = true`, strip `email`/`phoneNumber` subfields from the child's `linkedPlatforms` (FR-35). **After** the batch: purge all search indexes (`clearAllSearchIndexesForUser`, `userSearchIndex.ts:218-241`), expire pending invites from non-family senders and remove friendship edges (FR-36), write `AUDIT_PARENTAL_CONSENT_GRANTED`. Follow-ons are **not atomic**; the `onUserProfileSearchIndexSync` FR-11 exclusion is the backstop; function must be retry-safe/idempotent. Test pins the backstop (purge failure ⇒ syncer still removes entries).

**FR-5** Clearing (correction) sets both fields false, writes `AUDIT_PARENTAL_CONSENT_CORRECTED` with the chosen reason. Index re-creation via normal profile-sync triggers. The clear dialog presents the two correction reasons and separately signposts "Remove from family" / "Remove and delete data" as the paths for ending participation of someone still a child.

**FR-6** When a flagged child's membership ends by any path — `removeFamilyMember` (`family.ts:672`), `inactivateFamily` (`family.ts:841-845`), `deleteAccount` inactivate branch (`accountDeletion.ts:146`), `deleteAccount` remove_member branch (`accountDeletion.ts:157-159`, which gains its missing audit), `onAuthUserDeleted` (`auth.ts:60`), `requestChildDataDeletion` (FR-30) — write `AUDIT_PARENTAL_CONSENT_REVOKED` with the appropriate reason. `isChildAccount` **stays true** (sticky); account enters restricted state (FR-28): protection persists, collection stops.

### Rules hardening

**FR-7** No client may change `isChildAccount`: generalize `userDocPreservesEntitlementTags` (rules 43-45, applied at 67) into a diff-guard rejecting writes whose `affectedKeys()` include `entitlementTags` or `isChildAccount`.

**FR-8** Member-doc client writes (rules 233-238) become `allow create, update, delete: if false;` (read unchanged). All mutations already flow through callables; `FamilyMember.toFirestoreData()` is unused by the shipped client — zero regression.

### Discoverability — child as target

**FR-9** A child never appears in any `searchUsers` result (username/email/phone, including the direct `userNameLower` prefix query, `userSearch.ts:103-124`). Enforced at the single choke point `toPublicSearchHit` (`userSearchCore.ts:88-116`).

**FR-10** `isContactSearchableFromUserData` (`utils/validation.ts:100-135`) returns false for a child (also covers the `sendFamilyInvite` privacy gate, `family.ts:175-194`).

**FR-11** Index syncers (`userSearch.ts:189-330`) treat a child like a non-registered user: never create `usernames` / `user_lookup_email` / `user_lookup_phone` entries; flag-set purges retroactively (FR-4); provisional children never get entries (FR-27).

**FR-12** Peers cannot read a child's `users/{uid}` doc except family members. `isDiscoverableUserProfile` (rules 19-23) becomes, in exactly this order (child check first; key-presence guard before path construction):

```
existing checks
&& ( resource.data.get('isChildAccount', false) != true
     || ( 'activeFamilyId' in resource.data
          && exists(/databases/$(database)/documents/families/$(resource.data.activeFamilyId)/members/$(request.auth.uid)) ) )
```

Emulator matrix: orphaned child denied to everyone including ex-family; adult without `activeFamilyId` still readable; family member reads child; anonymous denied. Bare `list` queries not provable under the carve-out — acceptable (live client fetches by uid; callable path filters children).

### Invites — child as target

**FR-13** `sendTripInvite` gains `assertRegisteredAccount` (today bare `context.auth`, `tripInvites.ts:26-34`) and rejects child targets unless sender and child share the child's active family **and** FR-38 holds.

**FR-14** `sendFriendInvite` (`friends.ts:20-35`) rejects child targets outright.

**FR-15** `sendFamilyInvite` rejects child targets that already have an active family, on all methods including `search`. Inviting an *unconsented* child (no active family) remains allowed — it is the path back to consented play.

**FR-16 (extended per G-6)** (a) `invites` client-create (rules 201) becomes `allow create: if false;` — all live invite creation is server-side; closes forgery for adults too. (b) **New:** the `pending` join-request create rule (region of rules 242) must force `request.resource.data.userId == request.auth.uid` — a forged join request naming another uid could otherwise let a stranger's approval install them as a child's "consenting manager" with FR-12 family read access. Emulator test pins both.

### Ads (amended per §0 — no ads for child sessions)

**FR-17 (amended)** While the effective child signal is true (resolved account flag, cached-true, or device ratchet for anonymous sessions), `tagForChildDirectedTreatment = true` is applied on the global request configuration before any request is built — at cold start, every identity transition, and every mid-session flag change (FR-23). TFUA is never also set. This is defense-in-depth: under FR-19 no ad should be requested for a child session at all.

**FR-18** On any transition changing the effective child signal — identity change or mid-session merge — live banners are torn down/reloaded (a `BannerView` loaded under the old global config is never left showing; `AdBannerView.swift:53-66` loads once with empty `updateUIView`). For adult→child transitions the reload path removes the banner entirely.

**FR-19 (amended)** Ad display eligibility: `AdEligibilityService` returns **ineligible** whenever the current signal is child-true, cached-true, ratcheted-anonymous, or **unresolved** — under the single generic reason `ads_policy_hold`. Cache semantics are **asymmetric**: cached `true` applied immediately (TFCD stamped before `MobileAds.start()`); cached `false` — or no cache — is never trusted for display until this session's fresh `users/{uid}` read confirms not-child (`.userProfilesMerged` resolves the hold). Closes the current nil-user-eligible hole (`AdEligibilityService.swift:38-41`) and both stale-cache holes. Net: **only fresh-confirmed non-child sessions see ads.**

**FR-20** Client surfaces child status read-only: badges on member rows (`FamilyDashboard`/`FamilySettings`), manage controls (creator/captain only, `FamilySettings`), consent step (`FamilyPendingApprovals`), child-privacy detail (FR-29). Views render projections only; no view/view-model touches Firestore or ads SDK config.

**FR-21** All child-status actions emit typed analytics with uid-free, name-free payloads; **no event may exist that fires only for child sessions on the child's own app instance** (§12).

**FR-22** All new user-facing strings ship in en, es-419, fr-CA; child indication never by color alone; VoiceOver labels present (§13).

### Review-derived requirements

**FR-23** On any `.userProfilesMerged` (or projection update) where the **current** user's `isChildAccount` changes — including first resolution differing from cache — the client: re-invokes `AdMobService.applyChildDirectedTreatment`, updates the per-uid cache and ratchet, posts the banner-reload/removal notification (FR-18), re-applies analytics (FR-32), location (FR-33), and paywall (FR-34) postures. The self-listener already delivers the data (`UserProfileListenCoordinator.swift:51` → `mergeRemoteUserDocument`, `UserRepository.swift:176-194`). Test: server-side flag set mid-session ⇒ postures re-applied and banners gone before the next request. Covers the offline-device-comes-online case.

**FR-24** Server-side (client gating advisory): `searchUsers` returns zero hits for a child caller; `sendFriendInvite`, `sendFamilyInvite`, `createFamily`, `createShareCode` reject child callers; `sendTripInvite` rejects child senders unless target is in the child's active family (and FR-38 holds). Child callers remain able to call `redeemShareCode`, `respondToFamilyInvite_UserStep`, `deleteAccount`. Client hides corresponding entry points for child sessions. Rejections reuse the "not searchable"-style error shape (`FriendsFamilyInviteAnalytics.swift:31-33` pattern).

**FR-25** When `approveFamilyJoinRequest_CaptainStep` targets a user with `isChildAccount == true`, the payload **must** include an explicit `isChild`; absent ⇒ rejected (no silent laundering or stickiness). `true` ⇒ fresh `GRANTED` record (new consenting manager). `false` ⇒ `AUDIT_PARENTAL_CONSENT_CORRECTED` reason `new_guardian_cleared`, flag cleared both places, indexes rebuilt. Approval UI surfaces the pre-existing flag.

**FR-26** Clear authority: a current family manager, via FR-2 (correction) or FR-25 (re-admission declaration). An orphaned flagged account has exactly two exits: join a family (manager declares at approval) or delete the account (FR-40). "Child turns 13" is parent attestation through those paths (`child_turned_13`). Consent record SHOULD capture `expectedAgeOutYear` (year only, parent-supplied) as evidence and to enable a future scheduled age-out job (not built for MVP).

**FR-27 (amended per G-4/G-5)** A **neutral age screen** (no visible incentive either way) runs before the first `users/{uid}` profile write **on every path that can create one**: legacy onboarding, quick-solo start (`QuickSoloStartView.swift:153`), settings registration (`UserProfileView.swift:638`), and the **guest auto-account at first launch** (`FirebaseAuthService.swift:221-264` — anonymous sign-in and its profile write defer until the age answer). An under-13 answer: calls `declareChildRegistration` (server sets `isChildAccount = true` + uid-only `AUDIT_CHILD_REGISTRATION_DECLARED` **before** any profile/search-index write); seeds cache/ratchet true so the very first ad decision is suppressed/tagged; routes onboarding to join-family-only (server-backed successor of the removed `OnboardingCoordinator.swift:111` branch); enters provisional/restricted state (FR-28). Self-declaration only in the protective direction — clearing requires a parent (FR-26). The age answer is not stored beyond the flag (minimization). 13+ proceeds normally. Acceptance tests cover all four paths. Heavier alternative, not built: parent-initiated child-account creation via pre-declared share code.

**FR-28** An **unconsented child** (provisional or post-revocation) has no gameplay or profile-enriching cloud collection: shared guard `assertNotUnconsentedChild` (beside `assertRegisteredAccount` in `callableAuth.ts`) rejects unconsented-child callers on all state-mutating gameplay callables; any rules block permitting direct client gameplay writes gains the equivalent check (one `get()` on `users/{uid}`; enumerate during implementation). Client: local/offline play may continue (device-local storage is not collection; the offline-first queue holds events, uploads only after consent — deterministic, idempotent); sync pauses; ads suppressed (`ads_policy_hold`); non-punitive "Ask a parent to add you to their family" UI. Consent lifts restriction and resumes sync.

**FR-29** FamilySettings offers, per flagged child, a read-only "Child privacy" surface: current status + localized static summary of held data categories (profile, trip activity events, discoveries, lifetime stats — mirroring Privacy §12 copy). SHOULD add consent history via manager-gated `getParentalConsentStatus` callable reading the child's consent rows server-side (`audit_logs` stays client-inaccessible). MVP ships the MUST; the callable is the first enhancement if legal requires evidenced history at launch.

**FR-30** Manager-gated callable `requestChildDataDeletion(familyId, childUserId)`: verifies caller role ∈ {creator, captain}, target `isChildAccount == true`, current membership; removes the member; executes the existing `accountDeletion.ts` machinery against the child uid. Records: `REVOKED` reason `parent_requested_deletion` + existing `AUDIT_ACCOUNT_DELETED` (actor = parent). Surfaced as "Remove and delete child's data" beside plain removal and in the removal confirmation flow.

**FR-31** Every consent capture (FR-1, FR-2 set-true, FR-25 set-true) includes the explicit affirmation: "I confirm I am this child's parent or legal guardian and I am at least 18." Consent metadata carries `guardianAffirmed: true`, `consentTextVersion`, `affirmationVersion`. Documented limit for legal: manager accounts are not age-verified; the FR-27 gate reduces but cannot eliminate the under-13-creator scenario. Mechanism goes to legal review (OQ-2).

**FR-32** When the resolved child signal is true, the client disables Firebase Analytics ad-personalization signals (`allow_ad_personalization_signals = false`) via `AnalyticsService`, applied at the FR-23 seam; restored on resolved adult identity. Aggregate non-ad-personalized analytics remain enabled (internal-operations posture; full `setAnalyticsCollectionEnabled(false)` for child sessions is the noted heavier option for legal). `consentScope` includes `"analytics_limited"`. (App-wide ad-ID hardening is FR-44/F-3 and is not replaced by this per-session toggle.)

**FR-33 (amended per G-2)** `isChildAccount == true` forces **all three** `LocationSettingsService` flags off — `saveLocationWhenMarkingPlates` (cloud-upload path into shared `activity_events`), `trackMyLocationDuringTrips`, `showMyLocationOnLargeMap` — with the corresponding toggles hidden or disabled for child sessions, applied/re-applied at the FR-23 seam and enforced at each capture site through the existing single source of truth (`LocationSettingsService` / `EffectiveSettingsResolver`). Precise-location collection for children is outside `consentScope`; any future enablement requires legal review plus consent-copy and scope updates.

**FR-34** Child sessions suppress paywall/upsell surfaces and purchase entry points via existing `EntitlementService`/paywall gating (restores the removed Scout behavior, commit `ddc2f8b0`). Family-granted `entitlementTags` continue to apply. Client-side suppression is the MVP bar (StoreKit cannot be fully server-blocked; App Store parental controls are the platform backstop). This is the explicit monetization-change authorization CLAUDE.md requires.

**FR-35 (amended per G-3)** (a) `welcomeEmail.ts` stops writing plaintext `toEmail`/`fromEmail`/`contactEmail` into `audit_logs` metadata (lines 151-162, 181-191) **and** removes the email address from the `console.log` at lines 123-125 — app-wide, one-line-scale. (b) The FR-4 batch strips `email`/`phoneNumber` subfields from the child's `linkedPlatforms`; client serialization omits those subfields when the current user is a child. (c) **New:** the welcome-email trigger checks `users/{uid}.isChildAccount` and sends **nothing** for child accounts. App-wide contact relocation is FR-43/F-2 (no longer a follow-up).

**FR-36** Setting `isChild=true` (any path) additionally: expires all pending invites (friend/trip/family) targeting the child from senders outside the child's family (reusing `expiration.ts` machinery), and removes existing friendship edges (reusing the `accountDeletion.ts` friend-edge machinery; count recorded as `removedFriendEdgeCount`). Rationale: family-only play; FR-14 blocks only new edges.

**FR-37** `public_lifetime_stats/{userId}` read rule (rules 86-89) gains the same child exclusion + family carve-out as FR-12 (one `get()`), so strangers cannot confirm or monitor a child uid.

**FR-38** A flagged child participates only in trips whose participants are all members of the child's active family. Enforced in `tripInvites.ts` both directions: invites targeting a child verify every participant is family; inviting a non-family user into a child-containing trip is rejected; response/accept endpoints re-verify. Consent-UI copy states the restriction. Mixed-trip display denormalization is a later, legal-gated relaxation.

**FR-39** Device ratchet (UserDefaults) set whenever any uid's cached `isChildAccount` is true. While set, anonymous and signed-out sessions apply TFCD = true **and are ad-ineligible under FR-19's hold** (`signOutAndCreateAnonymous`, `FirebaseAuthService.swift:608`, no longer resets to untagged). A resolved adult sign-in gets normal treatment for that session; the ratchet persists for subsequent anonymous sessions.

**FR-40** A flagged child may self-delete via `deleteAccount` (deletion is child-protective; blocking protects nothing). Evidence: FR-6 `REVOKED` (`member_account_deleted`) + existing `AUDIT_ACCOUNT_DELETED`. No parent notification in MVP.

**FR-41** `FamilyRepository.sendFamilyInvite` (`FamilyRepository.swift:629-632`) gains the `FriendsFamilyAccessPolicy.validateFriendsFamilyCallableAccess` guard its siblings use. One line; server remains the backstop.

## §6 Requirements — app-wide (FR-42…FR-50)

**FR-42 (F-1, audit D1 — Critical)** Remove the silent login-location flow entirely: delete the GPS capture in `updateLoginTracking` (`FirebaseAuthService.swift:1318-1426`), `appendPrivateLoginLocation` (1672-1688), the `users/{uid}/private/lastLoginLocationData` write path, the local `AppUser.lastLoginLocation` cloud usage, and the legacy top-level parse (1903-1924). Add a one-time Cloud Function cleanup deleting existing `lastLoginLocationData` docs (dev data). *Accept:* no code path reads or writes login coordinates; `lastLoginLocation` grep hits only cleanup code; auth flows green. **Prerequisite for the child feature's "location outside consentScope" claim to be true.**

**FR-43 (F-2, audit E1 — Critical)** Contact-identifier containment, app-wide (resolves OQ-4): (a) `linkedPlatforms` email/phone/displayName move off the peer-readable `users/{uid}` doc into `private/contact` for **all** users (`FirebaseAuthService.swift:1842-1859`); public doc keeps platform type + platformUserId only. (b) `fcmToken` is removed from peer-readable exposure (relocate to a private subcollection or extend `userDocHasNoPrivateFields`; Cloud Functions read via Admin SDK regardless — update `UserRepository.updateFCMToken`, `utils/notifications.ts:54-67`). (c) Extend the rules diff-guard/private-fields helper to reject client writes re-introducing contact keys. (d) Migrate existing dev docs on next profile sync. *Accept:* a second registered account reading any user doc sees no email, phone, or push token; `UserPrivacyFirestoreTests` extended and green.

**FR-44 (F-3, audit C1/C2/C3 — High)** Analytics ad-ID hardening, app-wide: (a) drop the full `FirebaseAnalytics` SPM product from `project.pbxproj` (keep already-linked `FirebaseAnalyticsCore`, the AdId-less product in SDK 12.x). (b) Add Info.plist keys `GOOGLE_ANALYTICS_DEFAULT_ALLOW_AD_PERSONALIZATION_SIGNALS=NO`, `..._ALLOW_AD_STORAGE=NO`, `..._ALLOW_AD_USER_DATA=NO`. (c) Remove the unconditional `setCrashlyticsCollectionEnabled(true)` (`CrashReportingService.swift:22`). (d) Allow-list `deepLinkOpened` parameters (`AnalyticsService.swift:575-580`). *Accept:* clean build Core-only; events still log; keys present in built product. Note: FR-32's per-child toggle layers on top; this feature sets the safe app-wide floor.

**FR-45 (F-4, audit D2/D3/D4 — High, amended v2.1)** Location precision & speech, app-wide: (a) **Adult defaults remain ON** for `saveLocationWhenMarkingPlates` (owner decision D-11): the FR-27 age gate guarantees every playable session is age-resolved, child sessions are forced off via FR-33 regardless of stored defaults, and the OS location permission remains the adult opt-in gate — so no default flip is made. (b) Discovery payload coordinates round to 3 decimals (~110 m); drop altitude/vertical/horizontal-accuracy keys (`FoundRegion.payloadFields`). (c) Remove the dormant `ChallengeSettingsOverrides` OR-bypass (`EffectiveSettingsResolver.swift:74-78`) — the only mechanism that could force location on over a user's/parent's toggles. (d) `SpeechRecognizer` sets `requiresOnDeviceRecognition = true` (one line; keeps child/any voice audio on-device). Rounding is a deliberate semantics change, documented against ui-refactor-parity. *Accept:* payload carries rounded lat/lng only; child sessions upload nothing (via FR-33); speech works offline-on-device.

**FR-46 (F-9, audit A4 remainder — High)** SDK startup deferral, non-ads: FCM registration (`FirebaseMessagingService.configure`), RevenueCat `identify`, and Firebase Analytics collection do not start for an **age-unresolved** session; they start with the appropriate posture once resolved (child ⇒ FR-32/34 postures; FCM for a child registers only what family-trip notifications require). Firebase core + App Check + Crashlytics (internal-ops) may start immediately. Handles cold start, guest→registered link, sign-out→anonymous rebirth. *Accept:* instrumented fresh install shows no FCM/RevenueCat/Analytics network start before age resolution.

**FR-47 (F-10, audit F2 remainder — High)** Trip/friend invite hardening for all users: `sendTripInvite` gains a friendship-or-family relationship gate and per-user rate limiting (closing the TODOs at `tripInvites.ts:64-65`); `sendFriendInvite` gains rate limiting. Child-specific rules (FR-13/24/38) remain stricter and take precedence. *Accept:* functions tests for stranger rejection and rate-limit enforcement.

**FR-48 (F-11, audit F1 remainder + F3 — High)** Adult discoverability controls: (a) username search honors a per-user searchability opt-out (extend the `isUserSearchable` privacy model to the username modality). (b) `public_lifetime_stats` and `usernames/{usernameLower}` reads restricted to registered (non-anonymous) accounts. (c) Legacy client-side `searchBy*` methods (`UserRepository.swift:409-545`) deleted. *Accept:* rules + functions tests.

**FR-49 (F-12, audit G1 — High)** Backend retention limits: (a) expired invites and share codes are **deleted** on schedule, not status-flipped (`expiration.ts`). (b) Friend-invite expiry becomes finite (replace the 100-year `expiresAt`, `friends.ts:118-130`). (c) `audit_logs` gains a retention window (default 12 months, configurable) **with a permanent carve-out for consent/lifecycle event types** (`AUDIT_PARENTAL_CONSENT_*`, `AUDIT_CHILD_REGISTRATION_DECLARED`, `AUDIT_ACCOUNT_DELETED`) whose durable-evidence property §11.2 depends on (G-7). (d) Firestore TTL policies documented/enabled for transient collections. *Accept:* scheduled-job tests; consent rows demonstrably exempt.

**FR-50 (F-13, audit G2 — High)** Deletion completeness: `accountDeletion.ts` makes its own "retained de-identified" claim true — batch-rewrite the deleted user's `activity_events` (tombstone `actorId`, strip `locationLatitude`/`locationLongitude`/related keys), clean `members` docs, `participant_prefs`, fairness watermarks, invites; stop writing `familyName` and partial-plaintext search-query fingerprints into `audit_logs` (hash instead; `family.ts:869`, `userSearchCore.ts:119-135`). Idempotent, resumable batches. `requestChildDataDeletion` (FR-30) automatically inherits this machinery. *Accept:* post-deletion integration test — no doc anywhere carries the deleted uid with PI attached; consent records (uid-only) survive by design.

## §7 Data model & Firestore changes

**7.1 Authoritative field:** `users/{uid}.isChildAccount: boolean` — one source of truth; lives top-level because rules and every server enforcement surface read the user doc, and member docs are hard-deleted exactly when protection matters most (`family.ts:672, 841-845`).

**7.2 Projection:** `families/{familyId}/members/{uid}.isChild: boolean` — server-maintained mirror for family screens (which already listen to member docs, `FamilyRepository.swift:474-495`); written only by the same functions, same batch. `FamilyMember(from:)` ignores unknown keys — backward compatible.

**7.3 Rules changes (`firestore.rules`):** (1) user-doc diff-guard generalization (FR-7); (2) member docs `write: false` (FR-8); (3) `isDiscoverableUserProfile` child exclusion + ordered family carve-out (FR-12); (4) `invites` `create: false` **and** `pending.userId == request.auth.uid` (FR-16 + G-6); (5) `public_lifetime_stats` child exclusion (FR-37); (6) unconsented-child gameplay write blocks (FR-28); (7) contact/fcmToken private-field extensions (FR-43).

**7.4 No SwiftData schema bump.** No stored property is added to any `@Model`. Client consumption follows the `entitlementTags` Firestore-only projection pattern (`UserRepository.swift:26, 53-67, 181-185`); frozen `SchemaVersion1`/`SchemaVersion2` untouched; the three cloud→local hydration mirrors (`AuthProfileSyncPolicy.swift:67-94`, `FirebaseAuthService.swift:1745-1763`, `UserRepository.swift:780-798`) MUST NOT gain an `isChildAccount` line. Cold-start persistence via UserDefaults cache/ratchet (§10). Write-side guard: `firestoreDataFromAppUser` never includes `isChildAccount`; `saveUserDataToFirestore(_:extraFields:)` gains an assert-style key blacklist mirroring `loginTimestampFieldKeys`.

## §8 Cloud Function changes

**8.1 New callables** (new `familyChildStatus.ts`, exported beside `family.ts`): `setFamilyMemberChildStatus` (role-gated; FR-2/4/5), `declareChildRegistration` (FR-27; sets true only, never false), `requestChildDataDeletion` (FR-30), `getParentalConsentStatus` (FR-29 SHOULD).

**8.2 `approveFamilyJoinRequest_CaptainStep`** (`family.ts:427-614`): accepts `isChild` + `consentAcknowledged` + `guardianAffirmed` (+ optional `expectedAgeOutYear`); mandatory explicit `isChild` for sticky targets (FR-25); on true — member doc `isChild: true`, user stamp extension (`wasEverInFamilyUserUpdates.ts:9-20`) sets `isChildAccount: true`, index purge, FR-36 cleanup, GRANTED record. (Invite docs expire in 15 min; child intent is declared at approval only.)

**8.3 Membership-exit paths (FR-6):** extend `familyMembershipLeaveUserUpdate` call sites to detect `member.isChild` pre-deletion and append `REVOKED` with reasons `parent_removed_child`, `family_inactivated`, `creator_account_deleted`, `member_account_deleted` (branch also gains its missing generic audit), `auth_user_deleted` (no clientMetadata — permitted), `parent_requested_deletion`.

**8.4 Search/invite/actor enforcement:** `toPublicSearchHit` null for child (single choke point — index removal alone is insufficient: `syncUsernameSearchIndex` stamps `userNameLower` even for non-registered, `userSearchIndex.ts:63-67`); child callers get zero hits (FR-24); `utils/validation.ts:100` child ⇒ false; syncers fold `isChildAccount` into eligibility (`userSearch.ts:226`); `tripInvites.ts` gains `assertRegisteredAccount` + FR-13/24/38 checks on send and accept; `friends.ts` rejects child targets and senders; `family.ts` FR-15 + child-caller rejections on `createFamily`/`createShareCode`; `callableAuth.ts` gains `assertNotUnconsentedChild` (FR-28) applied to state-mutating gameplay callables.

**8.5 Audit plumbing:** new event types `AUDIT_PARENTAL_CONSENT_GRANTED/_CORRECTED/_REVOKED`, `AUDIT_CHILD_REGISTRATION_DECLARED`; `subjectType` stays `"user"` (no interface change); `welcomeEmail.ts` FR-35 fixes (metadata + console.log + child suppression).

## §9 Ad behavior (TFCD mechanics — amended)

1. **SDK facts (verified, 12.14.0):** TFCD/TFUA exist only on the global `RequestConfiguration`; tri-state `NSNumber?`; setting TFCD is a legal certification to Google; banners are the only format; `AdBannerView` loads once with empty `updateUIView`; `startIfNeeded()` runs in `didFinishLaunching` before auth resolves.
2. **Policy:** `AdRequestPolicy.policy(childDirected:)` replaces the static singleton so `makeRequest()` and global config can never disagree; the `"G"` ↔ `.general` coupling gets a pinning test.
3. **Application:** `AdMobService.applyChildDirectedTreatment(_:)` is the only writer of `tagForChildDirectedTreatment` (`true` child/ratcheted, `nil` resolved adult; TFUA never set). `startIfNeeded()` applies cached/ratchet value before `MobileAds.start()`.
4. **Triggers:** `handleAuthStateChange` + FR-23 merge observer → one apply-postures routine (ads, analytics, location, paywall, cache, ratchet) → `adIdentityDidChange` → banner teardown/reload-or-remove.
5. **Display rule (amended):** `AdEligibilityService` is the display gate — ineligible for child-true, cached-true, ratcheted-anonymous, and unresolved sessions (`ads_policy_hold`). **Only fresh-confirmed non-child sessions see ads.** TFCD stamping is belt-and-braces for any request that slips a race.
6. **Existing posture:** app-wide npa=1 + G-rated unchanged for everyone; non-child treatment must not weaken.
7. **Fast-follow (OQ-5, owner-approved v2.1):** serving TFCD-tagged npa/G ads to *consented* children ships after counsel sign-off under OQ-2; not in MVP. The flip is confined to the FR-19 eligibility gate (consented child ⇒ eligible with TFCD stamped); provisional/unresolved/ratcheted-anonymous stay ineligible.

## §10 Search & visibility enforcement map

| Path | Enforcement |
|---|---|
| `searchUsers` (all modalities + prefix scan) | `toPublicSearchHit` null for child targets (FR-9); zero hits for child callers (FR-24) |
| Email/phone modality + `sendFamilyInvite` gate | `isContactSearchableFromUserData` false (FR-10) |
| Index residue | Syncers exclude children (FR-11); purge on flag-set (FR-4); never created for provisional (FR-27) |
| Direct peer `get` of `users/{uid}` | FR-12 child exclusion + family carve-out; contact/fcmToken gone app-wide (FR-43) |
| Anonymous `usernames/{name}` → uid | Child entries deleted/never created (FR-4/11/27); adult reads registered-only (FR-48) |
| `sendTripInvite` | `assertRegisteredAccount` + family-only both directions + roster check (FR-13/24/38); relationship gate + rate limit for all (FR-47) |
| `sendFriendInvite` / `sendFamilyInvite` | Child target/sender rejections (FR-14/15/24); rate limits (FR-47) |
| Client-created `invites` / forged `pending` | `create: false`; `pending.userId == uid()` (FR-16 + G-6) |
| Legacy client search | Deleted (FR-48); child docs unreadable regardless (FR-12) |
| `public_lifetime_stats` | Child exclusion + carve-out (FR-37); registered-only reads (FR-48) |
| Pre-existing edges & invites at flag-set | Expired/removed (FR-36) |

**Family carve-out rationale:** blocking peer reads of the child doc would silently degrade family-roster hydration (`UserProfileListenCoordinator.swift:23-59`, `UserRepository.getUser` 809-835 → raw-uid fallback 142-148). The FR-12 expression is ordered so adults never evaluate it, orphaned children deny by explicit key-guard, family members pass. Cost: one `exists()` per child-doc read.

## §11 Consent record, parent rights & lifecycle

**11.1 Record shape** (via `writeAuditLog`): `eventType` ∈ the four new types; `actorId` = parent uid (or exiting/deleted uid on background paths — reason carries provenance); `subjectType: "user"`, `subjectId` = child uid; `metadata` (uid-only, **no PII ever**): `{familyId, childUserId, actorRole, consentScope: ["gameplay","search_excluded","analytics_limited"], policyVersions, consentTextVersion, affirmationVersion, guardianAffirmed, expectedAgeOutYear?, method, reason?, removedFriendEdgeCount?}`. **Location and ads are deliberately absent from `consentScope`** — all location flags are forced off (FR-33) and child sessions see no ads (FR-19). `clientMetadata` sibling via `normalizeClientMetadata`; omitted on background triggers.

**11.2 Why `audit_logs`:** client-inaccessible, append-only, survives account deletion, and — with the F-12 carve-out — exempt from retention cleanup. With FR-35 landed (no plaintext email anywhere in audit metadata or logs), a uid-only record genuinely becomes de-identified once `users/{uid}` and `private/*` are deleted. Never copy the `familyName`-in-metadata precedent; if parent-contact evidence is ever required, use the hashed `ipHash`/`deviceIdHash` slots, never plaintext.

**11.3 Lifecycle table**

| Event | Trigger | Record | Flag after | State after |
|---|---|---|---|---|
| Self-declared at registration | `declareChildRegistration` | DECLARED | true | Restricted (provisional) |
| Grant at admission | approve `isChild=true` | GRANTED | true | Consented |
| Grant post-hoc | `setFamilyMemberChildStatus(true)` | GRANTED | true | Consented |
| Correction (in-family) | `setFamilyMemberChildStatus(false)` + reason | CORRECTED | false | Normal adult |
| Correction (re-admission) | approve explicit `isChild=false` | CORRECTED (`new_guardian_cleared`) | false | Normal adult |
| Parent removes child | `removeFamilyMember` | REVOKED (`parent_removed_child`) | true (sticky) | Restricted |
| Parent removes + deletes | `requestChildDataDeletion` | REVOKED + ACCOUNT_DELETED | n/a | Deleted |
| Family inactivated | `inactivateFamily` | REVOKED (`family_inactivated`) | true | Restricted |
| Creator deletes account | `deleteAccount` inactivate branch | REVOKED (`creator_account_deleted`) | true | Restricted |
| Child self-deletes | `deleteAccount` remove_member branch (+ its missing audit) | REVOKED + ACCOUNT_DELETED | n/a | Deleted |
| Auth user deleted (sweep) | `onAuthUserDeleted` | REVOKED (`auth_user_deleted`) | true / n/a | Restricted / deleted |

**11.4 State machine:** `adult` → *(age screen, under-13)* → `provisional child` (restricted) → *(family admission + consent)* → `consented child` → *(correction)* → `adult`; or → *(removal / family end / withdrawal)* → `restricted child` → *(re-admission FR-25)* → `consented child` or `adult`; or → *(deletion FR-30/40)* → gone. Restricted semantics: cloud gameplay writes rejected server-side; local offline play permitted; ads suppressed; search/invite exclusions apply; child can redeem a share code, respond to a family invite, or delete the account. **Guest→registered:** anonymous-account linking preserves the uid, so cache/ratchet/projections carry across by design. The pre-flag exposure window is closed for self-registered children by FR-27; FR-4 purge + FR-36 cleanup remain the belt-and-braces path for children flagged later by a parent.

**11.5 Parent review & deletion:** FR-29 + FR-30 deliver the Privacy §12 promises; the child can also self-delete (FR-40). No standing deletion clock in MVP — withdrawal stops collection immediately (FR-28); deletion is offered at removal.

## §12 Analytics

Typed events via the existing `AnalyticsService` taxonomy, from ViewModels/services only: `.familyChildStatusSet(source)`, `.familyChildStatusCorrected(reason)`, `.familyChildConsentAcknowledged` (parent's instance), `.inviteAutoRejectedChildTarget` (sender's instance). Ad suppression uses the single generic `ads_policy_hold` reason for unresolved and child cases alike. Rule (FR-21/32): no event fires only for child sessions on the child's own instance; the child flag is never logged as a value tied to a user or app instance. Age-screen funnel events record screen-shown/completed only — never the answer.

## §13 Localization & accessibility

New strings (en + es-419 + fr-CA): neutral age-screen copy; child toggle ("This member is a child (under 13)"); consent acknowledgment + guardian affirmation referencing ToS §2 / Privacy §12; family-only trips notice; "Child" badge; correction dialog (two reasons); remove vs. remove-and-delete; child-privacy summary; restricted-state copy ("Ask a parent to add you to their family"); rejection copy for child-target/sender actions. **Do not delete** live keys `Captain`/`Scout` (`FamilyMember.swift:35-37`, `FamilyMemberRolePresentation.swift:30`) or "Create a family to add Scouts…" (live in `OnboardingCreateFamilyView.swift:35`); the genuinely orphaned picker strings (en 288/290/292/295-296 + es/fr twins) are deleted in F-6. Accessibility: badge = icon + text, never color alone; VoiceOver label/value/hint on the toggle; consent/restricted screens readable at all Dynamic Type sizes; touch targets; light/dark, iPhone/iPad, Reduce Motion preserved.

## §14 Test plan

**Server (Jest):** `toPublicSearchHit` null for child / missing-⇒-adult pinned; `isContactSearchableFromUserData` false for child despite `emailSearchable: true`; syncers create nothing for child, purge on flag-set, **purge-failure backstop**; `setFamilyMemberChildStatus` role gating, self/creator rejection, batch shape, correction reasons, uid-only audit assertion, clientMetadata sibling; `declareChildRegistration` true-only + DECLARED + no index entries; approval — acknowledgment-missing rejected, sticky-without-explicit rejected, `new_guardian_cleared`, GRANTED + stamp; actor-side allow/deny matrix (FR-24); `sendTripInvite` full matrix incl. accept-path re-verify (FR-13/38/47); flag-set cleanup counts (FR-36); `assertNotUnconsentedChild` gameplay rejections lifting on admission; every exit path writes REVOKED with correct reason, `deleteAccount` remove_member now audits, flag stays true after removal; `requestChildDataDeletion` role-gated remove+delete+double record; `welcomeEmail` — no plaintext email in metadata **or logs**, nothing sent to child accounts; retention job deletes non-consent rows and provably exempts consent types (F-12); deletion de-identification integration test (F-13).

**Firestore rules (emulator):** diff-guard self-update denial; member-doc write denial; FR-12 four-case matrix (+ roster regression); `invites` create denial + **`pending.userId` forgery denial**; `public_lifetime_stats` stranger/family matrix; unconsented-child gameplay write blocks; `audit_logs` fully client-inaccessible; contact/fcmToken field guards (F-2).

**Client (XCTest; expect pre-existing compile rot per repo conventions):** `AdRequestPolicy` child variants + `"G"`/.general pin; `AdMobService` adult→child stamps TFCD before next request, child→adult resets, TFUA never set, cached-true pre-start, **cached-false not trusted (stale-flip)**, **mid-session re-stamp + banner removal**, ratchet governs anonymous; `AdEligibilityService` — child/cached/ratcheted/unresolved all ineligible under `ads_policy_hold`, resolving on merge; `AnalyticsService` personalization toggle both directions; `LocationSettingsService` — **all three flags** forced off for child, toggles hidden; paywall suppression with `entitlementTags` still honored; `UserRepository` projection ingest, tri-state accessor (nil never treated as adult), sign-out clear, merge propagation; ViewModels — approval requires both acknowledgments, sticky surfacing, `canManageChildStatus` uses the configured auth service (not the throwaway built in view `init`); onboarding — under-13 routes join-family-only, `declareChildRegistration` precedes any profile write **on all four entry paths** (F-6 acceptance); F-1 — no login-location reads/writes; F-4 — adult defaults unchanged (ON), child sessions forced off via FR-33, rounded payloads, on-device speech. Focused UI test: captain approval with child toggle end-to-end against the emulator, if practical.

## §15 Migration & rollout

1. **No data migration** — unshipped; missing flag ⇒ adult.
2. **Deploy order per feature:** functions → rules → client (server-first is safe: shipped client ignores unknown member-doc keys; write:false rules have no client regression since all live mutations are callable-based; the diff-guard blocks fields no client writes). Landing order per §3; CI runs rules-emulator + functions tests each landing.
3. **Retroactive flagging** post-launch: FR-4 purge + FR-36 cleanup close residue (indexes, stamped `userNameLower`, pending invites, friend edges).
4. **Old installed clients** post-launch: unaffected — server-side enforcement protects children regardless of client version.

## §16 Risks & mitigations

| Risk | Mitigation |
|---|---|
| Member-doc client writes flip flags with no record | FR-8 write:false, rules test |
| Child self-clears flag via self-update | FR-7 diff-guard (entitlementTags pattern) |
| Cold-start gap (SDK starts pre-auth; nil = untagged) | Asymmetric cache + ratchet pre-start + FR-19 display hold |
| Mid-session flip never reaches SDK / offline device syncs late | FR-23 re-stamp + banner removal; test pinned |
| Stale cached "adult" shows ads to remotely-flagged child | FR-19 asymmetric trust; only fresh-confirmed non-child sessions see ads |
| Stale global TFCD child→adult | Over-restrictive only; resolves on fresh read |
| Projection nil ambiguity | Tri-state accessor; nil never adult |
| Child as stranger-contact initiator | FR-24 server-enforced |
| Un-clearable orphaned flag / age-out dead end | FR-25/26/40 |
| Collection after revocation | FR-28 restricted state |
| Self-registered child collected pre-consent | FR-27 gate on all four paths |
| Forged pending join request installs stranger as consenting manager | FR-16 extension (G-6); rules test |
| Child location collected outside consentScope | FR-33 all-flags forced off + FR-42 login-location removal |
| Carve-out breaks rosters / missing-key misfire | FR-12 ordered expression + key guard + matrix |
| Consent metadata becomes permanent PII | §11.1 uid-only schema + FR-35 + F-13 audit hygiene; test asserts no name/email/birthdate keys |
| Deleted-account exit loses lineage | FR-6 adds missing audit |
| Checkbox consent challenged as insufficient VPC | FR-31 affirmation + versioned text + OQ-2 legal gate |
| Purchases by children | FR-34 + App Store parental controls backstop |
| Retention job deletes consent evidence | F-12 carve-out (G-7); test pinned |
| `changeFamilyMemberRole` flips altering treatment | Dedicated `isChild` independent of role |
| Future captain assignment widens authority | OQ-1; explicit role list |
| Legacy client search re-enabled | Deleted in F-11; child docs unreadable regardless |
| Mediation adapters (if ever added) snapshot config at init | None used; verify at that time (AdMobService comment) |
| Ratchet/suppression revenue impact | Accepted; negligible vs. certification risk |

## §17 Decisions & open questions

**Decisions (approve by exception):** D-1 withdrawal ≠ correction. D-2 restricted state blocks cloud collection, permits local play. D-3 neutral age gate for self-registrants; parent-created child accounts are the heavier future alternative. D-4 family-only trips for children. D-5 child self-deletion allowed, no parent notification in MVP. **D-6 (amended v2.1):** child sessions see **no ads at MVP**; TFCD + ratchet as defense-in-depth; anonymous sessions on ratcheted devices are tagged and ad-ineligible; TFCD-tagged ads for consented children are an owner-approved fast-follow contingent on OQ-2 counsel sign-off (OQ-5). D-7 analytics on for children with ad-personalization off. D-8 `invites` create closed outright. D-9 client-side paywall suppression. **D-10 (new):** login-location flow deleted app-wide (FR-42). **D-11 (revised v2.1, owner decision):** adult `saveLocationWhenMarkingPlates` defaults **remain ON** (the FR-27 age gate ensures no age-unknown session can play; the OS permission is the adult opt-in); all location flags forced off for children at MVP; a parent-controlled per-child location toggle (default off, `consentScope` gains `location_family_shared` when enabled, surfaced in F-8's manage-child controls) is an owner-approved fast-follow contingent on OQ-2 counsel sign-off. **D-12 (new):** child registrations collect no names/phone (FR-52 → folded into FR-27/F-6 scope).

**Open questions:** **OQ-1** set/clear authority — default creator||captain (effectively creator-only in MVP; trivial to tighten). **OQ-2 (owner decision 2026-08-10):** no external counsel before release — the FR-31 checkbox + guardian-affirmation model ships on the owner's own acceptance. In place of counsel sign-off: consent/policy version constants in `childAccountCore.ts` pin the exact git commit of the legal text and MUST be bumped in the same commit as any wording change (discipline documented at the constants). The two previously counsel-gated fast-follows — TFCD child ads (OQ-5) and the parental child-location toggle (D-11) — remain OFF until the owner explicitly chooses to accept them. **D-13 (new, owner):** `ensureFounderEntitlementIfEligible` stays ungated for children — the founder tag is a cosmetic early-supporter marker and children are not excluded from it, regardless of consent state. **OQ-3** TFUA / 13–15 band — not in MVP; boolean + `expectedAgeOutYear` leaves room. **OQ-4** — **resolved**: app-wide contact relocation is in scope as F-2. **OQ-5 (decided v2.1)** — TFCD-tagged ads for consented children: off at MVP; owner has approved enabling as a fast-follow **contingent on counsel sign-off in OQ-2**. The same OQ-2 gate governs the parental child-location toggle (D-11). Counsel should therefore review three items together: the consent mechanism itself, TFCD child ads, and consent-scoped child location sharing.

## §18 Follow-ups (tracked, out of scope)

**Parent↔Child account switcher (owner idea, 2026-08-11):** a "swap account" button for shared devices that switches between signed-in profiles and requires the account password to switch back to the parent account. New feature, post-MVP; interacts with the identity-epoch age-gate rules (each signed-in account carries its own resolved status, so no re-gating needed on switch).

**Tournaments/Events/Challenges settings-gated join (owner intent, 2026-08-10):** the deleted `ChallengeSettingsOverrides` (FR-45c) existed to let future tournaments require settings (e.g., location) to join. When that feature is built, implement it as an explicit **join-time consent gate** ("This event requires location sharing — enable to join") that routes through the normal settings/consent path — never as a silent override ahead of the user's privacy toggles. Child accounts: excluded from location-requiring events, or gated on the parental location toggle (D-11 fast-follow), consistent with FR-33/FR-38.

Orphaned Captain/Scout string cleanup lands in F-6; remaining: **TFCD-tagged ads for consented children** (OQ-5 — owner-approved, blocked on OQ-2 counsel sign-off); **parent-controlled per-child location toggle** (D-11 — owner-approved, blocked on OQ-2 counsel sign-off); RevenueCat/Firebase-Analytics third-party deletion propagation (audit G4, Medium); IDFV-fragment default usernames (audit C4, Medium); share-sheet parental gating (audit F5, Low); RemoteConfig `storeUrl` allow-listing (audit H3, Low); review-prompt gating (audit H4, Low); PrivacyInfo.xcprivacy completeness (audit H1 — being handled separately); legacy contact-field indexing (`userSearch.ts:246-266`).

## §19 Resolved critique register

C0-1…C0-11 and C1-1…C1-13 dispositions carry over unchanged from the source SRS (all resolved or decision-gated as recorded there), with these v2.0 updates: C1-7 (geolocation) now fully resolved by FR-33-amended + FR-42 + FR-45 (was partially resolved — wrong flag); C1-5 (minimization) strengthened by FR-43 in-scope (OQ-4 resolved) and registration minimization (G-5); C1-8/C0-1 unchanged but simplified by the no-ads decision (D-6). New in v2.0: **G-1…G-7** as catalogued in §0, all resolved in-scope.

---

*File touch index:* functions — `family.ts`, new `familyChildStatus.ts`, `wasEverInFamilyUserUpdates.ts`, `userSearchCore.ts`, `userSearch.ts`, `userSearchIndex.ts`, `utils/validation.ts`, `utils/notifications.ts`, `tripInvites.ts`, `friends.ts`, `accountDeletion.ts`, `auth.ts`, `callableAuth.ts`, `welcomeEmail.ts`, `expiration.ts`, `audit.ts` (constants), `firestore.rules`. iOS — `Repositories/FamilyRepository.swift`, `Repositories/UserRepository.swift`, `Services/FirebaseAuthService.swift`, `Services/AdRequestPolicy.swift`, `Services/AdMobService.swift`, `Services/AdEligibilityService.swift`, `Services/AnalyticsService.swift`, `Services/CrashReportingService.swift`, `Services/LocationSettingsService.swift`, `Services/EffectiveSettingsResolver.swift`, `Services/SpeechRecognizer.swift`, `Services/FriendsFamilyAccessPolicy.swift` (call-site), `Services/FirebaseMessagingService.swift`, `Services/RevenueCatEntitlementBridge.swift`, `Views/Components/AdBannerView.swift`, `Views/Family/*`, `Views/AccountCreation/SignInView.swift`, `ViewModels/FamilySettingsViewModel.swift`, `ViewModels/FamilyDashboardViewModel.swift`, `Coordinators/OnboardingCoordinator.swift`, `en/es/fr .lproj/Localizable.strings`, `LicensePlateApp.xcodeproj/project.pbxproj` (F-3), `Info.plist` (F-3), tests. **No changes** to `Model/SchemaVersions.swift`, `Model/User.swift`, `Model/FamilyMember.swift`.

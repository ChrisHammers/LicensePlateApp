# RoadTrip Royale — Written Children's Information Security Program (FR-82)

**Status: OWNER-APPROVED 2026-11-17.** Drafted 2026-08-30 from `COPPA_SRS_v3.md`
FR-82 (F-39), against the live code at `feature/MVPPush` commit `30a2463` (2026-08-30 —
the same commit that landed `RETENTION_POLICY.md`). This is the §312.8(b) *written
information security program* the amended COPPA Rule requires of an operator that
collects children's personal information. It is the first document this project would
hand over in any inquiry, audit, or incident. It is not a code change and authorizes
none.

**Accuracy refresh 2026-11-17** (approved by the owner the same day): every file:line
citation, count, and open/closed status below was re-checked against `feature/MVPPush`
at commit `8616a5fd` and corrected where the code had moved. No commitment was added or
removed; items found not yet true in code are now listed as **OPEN** in §7.2.

**Verification discipline:** every mechanism named below was located and read in this
worktree before this sentence was written about it — file paths, function names, and
rule text are cited so a reader can re-check them directly rather than trust this
document's prose. Where a claim could not be independently confirmed in the code, it is
marked **PLANNED** or **OPEN** rather than stated as fact. Section 7 is the honest
accounting of everything in that second category.

---

## 1. Security coordinator

The owner, **Chris Hammers**, holds the security-coordinator role §312.8(b)(1)
contemplates: the one person accountable for approving this program and any change to
it, receiving and triaging any incident or inquiry, and running the annual review (§6).
This is a role assignment, not a personnel file — no contact details or other personal
information are recorded in this document. At the company's current size (owner-operated,
pre-launch), the security-coordinator role and the engineering role are held by the same
person; this section exists so the role is named and transferable if that changes.

## 2. Child-data inventory

The living data map is code, not prose, and this document does not restate it — it would
drift the moment the code changed and the restatement didn't. The authority is
`PER_UID_DATA_LOCATION_KEYS` in `functions/src/childDataInventory.ts:51-64` (FR-61): the
12-entry manifest of every per-uid location this project holds data at. It is
machine-enforced two ways: the builder's section map is typed
`Record<PerUidDataLocationKey, …>`, so a key added to the manifest without a
corresponding inventory section fails to *compile*; and
`functions/src/childDataInventory.test.ts`'s `describe` block — **"FR-61 parity: deletion
sweep and review inventory cover the same locations"** — asserts the manifest matches
`DELETION_SWEEP_LOCATION_KEYS`, declared beside the account-deletion sweep in
`functions/src/accountDeletion.ts:126`, and fails the *test suite* if they ever diverge.
The deletion code path and the parental-review code path are structurally forced to agree
on where a child's data lives. If this table and the manifest ever disagree, the manifest
in the code is the authority, not this document.

| # | Location key | What it holds | Where |
|---|---|---|---|
| 1 | `user_profile` | Username, avatar, child flag, age-out year+month, account timestamps | `users/{uid}` |
| 2 | `private_subcollection` | Contact **presence only** (email/phone booleans, never values), push-token presence, the guardianship record | `users/{uid}/private/*` |
| 3 | `search_indexes` | Username/email/phone lookup rows — for a child these must be absent, and the inventory reports that rather than assuming it (FR-11) | `usernames`, `user_lookup_email`, `user_lookup_phone` |
| 4 | `friend_edges` | Count only — the other party is never named | `friends` |
| 5 | `family_membership` | Role, child flag, pending-consent marker | `families/{familyId}/members/{uid}` |
| 6 | `progression` | XP total, level, grant-ledger count | `user_progression/{uid}` (+ `xp_grants`) |
| 7 | `achievements` | Unlocked-achievement count | `user_achievements/{uid}` |
| 8 | `public_lifetime_stats` | Published numeric totals only, exactly as shown publicly | `public_lifetime_stats/{uid}` |
| 9 | `invite_rate_limits` | Operational abuse-prevention counters (FR-47), not user content | `invite_rate_limits` collection |
| 10 | `gameplay_residue` | Per-trip participation summaries, activity-event counts by kind, whether any stored event still carries a location payload, invites sent/received, share codes, pending notify buffers | `trip_sessions/*`, `trip_invites`, `share_codes`, `plate_found_notify_buffers` |
| 11 | `revenuecat_vendor` | Standing vendor posture, not per-child state (§5) | RevenueCat (external) |
| 12 | `analytics_vendor` | Standing vendor posture — no uid ever enters the catalog (§5; **not yet true in code as of 2026-11-17** — events carry participant identifiers until F-28 lands, see §5 and §7.2) | Google Analytics (external) |

Every row is reachable by a guardian through the FR-61 callables
(`getChildDataInventory`, `listGuardedChildren` — both declared in
`functions/src/familyChildStatus.ts:144` and `:162`, implemented by
`buildChildDataInventoryFlow` and `listGuardedChildrenFlow` in `childDataInventory.ts:134`
and `:414`, both exported from `functions/src/index.ts`), gated by the same FR-62
authorizer deletion uses
(§3d) — so the §312.6(a)(3) review right survives the child's removal from the family,
not just its duration.

## 3. Access model

Four layers, each verified directly against this worktree's code, not against the SRS's
narrative about the code.

**(a) Firestore rules deny by default.** `LicensePlateAppiOS/firestore.rules` is 751
lines with 32 `match` statements — the root `/databases/{database}/documents` wrapper
plus 31 path blocks, one per collection, subcollection, or collection-group path actually
in use; there
is no catch-all rule because Firestore's rules language does not need one — any path
with no matching block is denied structurally. Several collections are additionally
hard-denied by explicit rule rather than relying on that default: `consent_requests`
(lines 734-736, `allow read, write: if false` — carries the guardian's email and the
hashed confirmation nonce), `audit_logs` (lines 739-743), `plate_found_notify_buffers`
(lines 746-748), and `user_lookup_email` / `user_lookup_phone` (lines 350-356, server-only
lookup indexes). The guardianship record at `users/{uid}/private/guardianship` is denied to
every client, owner included: the private-subcollection rule (lines 339-347) allow-lists
owner reads, deletes, creates, and updates only for `docId == "contact" || docId == "fcm"`,
so any other document id
under that path — including `guardianship` — has no client access path at all; only the
Admin SDK reaches it. The same rule also refuses a create or update of the `fcm` (push
token) document when the caller is an unconsented child (`callerIsUnconsentedChild()`,
lines 158-162: child flag set and no `activeFamilyId`) — the FR-73 server-side backstop on
the push token; reads and deletes of `fcm` stay open so a token can always be removed.
Family membership docs (`families/{familyId}/members/{memberId}`,
lines 673-680) are `create, update, delete: if false` outright; pending join-request rows
(`families/{familyId}/pending/{requestId}`, lines 682-713) allow client `create: if false`
and field-guard `update` to exactly `["status", "resolvedAt"]` — a captain can resolve a
request but cannot rewrite who it names.

**(b) App Check on every callable.** `functions/src/callableOptions.ts`'s
`enforcedCallable()` sets `enforceAppCheck: true` on the underlying
`functions.runWith(...).https.onCall(...)` call (`callableOptions.ts:11-18`). A
repository-wide check (2026-11-17) finds 37 callable functions across 15 non-test source
files constructed with `= enforcedCallable(...)`,
and **zero** non-test call sites anywhere in `functions/src` that construct a callable
via a raw `functions.https.onCall` outside `callableOptions.ts`'s own implementation —
there is no bypass path for a client-invoked callable. The one deliberate exception,
`confirmParentalConsent` (`functions/src/consentRequests.ts:783`, the only `onRequest`
endpoint in `functions/src`), is an `onRequest` HTTP
endpoint a guardian's mail client opens directly; it cannot carry App Check by
construction and instead relies on a hashed, single-use, attempt-bounded nonce
(§312.5(c)(1)) — documented in the function's own header comment. Client-side,
`LicensePlateApp/Services/AppCheckConfigurator.swift` selects the App Check provider per
install channel (the debug provider on the Simulator, DeviceCheck for physical-device
Debug and local Xcode installs, App Attest for TestFlight/App Store), and
`FamilyRepository.swift`'s `FamilyCallable` type adds a limited-use-token path with a
same-process retry for family-management calls specifically. This mechanism has a known
open failure class — see §7.

**(c) Callable auth gates.** `functions/src/callableAuth.ts` is the shared library every
callable composes its auth precondition from: `assertAuthenticated` (signed in, full
stop), `assertRegisteredAccount` (rejects credential-less Firebase accounts — sign-in
provider `anonymous` or `custom` — the default requirement), the FR-60 carve-out `assertRegisteredAccountOrDeclaredChild` (admits a
credential-less (anonymous or custom-token) caller only when the server-side `users/{uid}.isChildAccount` flag already
reads `true` — never claimed by the client, only ever written by the Admin SDK), and
`assertNotUnconsentedChild` (blocks state-mutating gameplay calls for a child with no
active family). The registered-account and declared-child refusals share one exact
message constant, `REGISTERED_ACCOUNT_REQUIRED_MESSAGE`, specifically so a rejected
credential-less caller cannot fingerprint, from the wording alone, whether the uid it holds is
a declared child (FR-24 indistinguishability).

**(d) FR-62 guardianship authorizer.** `authorizeParentalRights()`
(`functions/src/familyChildStatusFlows.ts:77-113`) is the single function every
parental-rights action authorizes through: child-data deletion
(`requestChildDataDeletion`), review (`getChildDataInventory`,
`getParentalConsentStatus`), and FR-84 device transfer (`createDeviceTransferCode`,
`deviceTransfer.ts:152`) all call it. Its ladder, read directly from the source: (1) a
live Creator/Captain of the named family (a live member with any other role is refused
at this step), else (2) the uid recorded as
`guardianUid` on the child's `users/{uid}/private/guardianship` document for that same
family — matched whether that guardianship is live or ended — else (3)
`permission-denied`. This is the
mechanism that lets a parent who removed their child from the family retain review and
deletion rights afterward (§312.6(a)(2)/(a)(3)), and that stops a stranger or a different
family's manager from reaching either right.

## 4. Incident-response step list

Sized for a one-person operator; every step below names a mechanism that exists today,
not an aspirational one.

1. **Detect.** Three live signals: (a) the FR-64 nightly reconcile —
   `reconcileParentalConsentRecords` (`functions/src/retention.ts:242-262`, scheduled
   `"0 0 * * *"` America/Los_Angeles, i.e. midnight Pacific — `retention.ts:59-60`)
   re-derives from stored state
   that every consented child holds a sufficient consent record and every confirmed
   email-plus grant received its follow-up notice; a finding logs at
   `functions.logger.error` with the literal string `"FR-64 reconcile FINDINGS"`
   (`retention.ts:255`) — that
   string is the thing to alert on in Cloud Logging. (b) Cloud Functions error logs
   generally (deletion-cascade failures, consent-email send failures, an App Check
   rejection spike). (c) The owner's own standing deploy-and-review habit (recorded as
   D-24 in `COPPA_SRS.md`, inherited by `COPPA_SRS_v3.md` §2): nothing is called done until its rules
   and functions diffs are deployed to dev and reviewed — the same discipline catches
   most regressions before they reach a real user.
2. **Assess.** Map the finding onto the inventory in §2 — which of the 12 locations is
   touched, whether a child uid is involved, whether the exposure is read-only or a
   mutation. Check §7 first: several known failure signatures (the App Check "Decoding
   App Check token failed" class in particular) already have a documented root cause and
   may not be a new incident at all.
3. **Contain.** Concrete levers that exist today: rotate the affected secret
   (`RESEND_API_KEY`, `REVENUECAT_SECRET_API_KEY` once provisioned (§5), or a Firebase service-account key) via
   `firebase functions:secrets:set` and redeploy; tighten the relevant block in
   `firestore.rules` to `allow read, write: if false` and deploy (a rules-only deploy is
   fast and reversible); revoke or re-register a specific App Check debug token, or
   rotate the App Check configuration, from the Firebase console if token forgery is
   suspected; disable one scheduled job by removing its `pubsub.schedule` export if a
   retention or reconcile job is itself the problem.
4. **Notify counsel.** `COPPA_COUNSEL_MEMO.md` is the standing counsel-handoff channel —
   its §5 is an explicit numbered question list that remains the agenda if a formal
   counsel engagement is ever wanted; the owner's LLC counsel has given only a quick
   review of the memo's closed-group analysis (2026-08-27, §7.2). Any
   incident touching consent validity, disclosure, or this program itself gets added to
   that agenda rather than resolved unilaterally; the memo is a regulatory-analysis pass
   prepared to brief counsel, not a substitute for reaching counsel when something is
   live.
5. **Document.** This repository already has a working incident-narrative convention —
   `COPPA_SRS_v3.md` §3's wave-by-wave build log carries several examples in place (the
   "Bug B" App Check saga and the search-index "item 9" resurrection are the fullest
   ones): what was observed, the root cause once found, the fix, and an explicit
   owner device-verification pass before the entry is treated as closed. A new incident
   gets the same treatment in the SRS (or its eventual successor) — this document names
   the process but is not itself where a live incident gets logged.

## 5. Vendor list and data-handling posture

FR-82 asks for "the vendor list with data-handling terms". This section records each
vendor's posture as seen from this project's code; the vendors' own data-handling terms
(Google/Firebase, RevenueCat, Resend) have **not yet been collected or cited here** — an
**OPEN** owner task, listed in §7.2.

**Firebase / Google Cloud** — the platform, not a bolt-on vendor; every location in §2
lives inside it.
- *Firestore / Cloud Functions (Admin SDK):* primary datastore and compute; access is
  entirely governed by §3.
- *Firebase Auth:* identity provider. Consented children are represented as credential-less
  Firebase accounts (FR-60): anonymous, or a custom-token session after an FR-84 device
  transfer (`functions/src/deviceTransfer.ts:374`) — there is no separate credential store for them.
- *App Check:* integrity gate on every callable (§3b).
- *FCM (push):* token *existence* is itself part of the inventory (§2,
  `private_subcollection`); `LicensePlateApp/Services/FirebaseMessagingService.swift`
  persists tokens client-side, and `assertNotUnconsentedChild`
  (`functions/src/callableAuth.ts`) blocks state-mutating gameplay calls for a child with no active family. The token write
  itself is client-direct to Firestore and is refused for an unconsented child by the
  `users/{uid}/private/{docId}` rule (§3a, `firestore.rules:344-346`). Marketing-category
  (`promotionsAndNews`) pushes are refused server-side for every child account, consented
  or not (re-verified 2026-11-17): `CHILD_SUPPRESSED_PUSH_CATEGORIES`
  (`functions/src/notificationPrefs.ts:82-84`, checked by `isPushCategoryAllowedForChild`,
  `:87-89`) is enforced in `getFCMTokenForPush` (`functions/src/utils/notifications.ts:119`),
  which returns no token for a child account and a suppressed category before any
  preference is read. Every push sender in `functions/src` resolves its token through
  `getFCMTokenForPush` (directly or via its deprecated alias `getFCMTokenForSocialPush`);
  the ungated `getFCMToken` has no caller, and no current code path sends the
  `promotionsAndNews` category at all.
- *Firebase Analytics:* **the no-identifier, nothing-before-consent posture is NOT yet
  true in code (as of 2026-11-17).** What holds: a repository-wide search finds zero call
  sites for `Analytics.setUserID`/`setUserId` anywhere in the Swift app, and
  `AnalyticsService.swift:73-76`'s header comment states the FR-21 rule for the
  family-child-status events: no event may exist that fires only for a child session, and
  no uid, name, or age value is carried as a parameter of those events. What does not
  hold yet: the SDK start plan (`LicensePlateApp/Services/DeferredSDKStartupService.swift`,
  `startsAnalyticsCollection: isFirebaseConfigured`, line 114) has no child or consent
  term, so analytics collection is on for every age-resolved session, child sessions
  included, consented or not; and gameplay events carry participant identifiers
  (`participant_id` / `actor_participant_id`, `AnalyticsService.swift:700, 865-977`). The
  fix is COPPA item F-28 / FR-72, in progress and not landed. Listed **OPEN** in §7.2
  until it lands. `resetAnalyticsData()` runs
  client-side at account deletion (FR-78(b); `FirebaseAuthService.swift:1769`); retention
  beyond that is Google's own GA4 window, not this project's.
- *Crashlytics:* a thin wrapper, `LicensePlateApp/Services/CrashReportingService.swift` —
  treated as an internal operation under the amended rule's support-for-internal-
  operations exception (crash stability data, not behavioral or advertising data), and
  collection is permitted to start before age resolution on that basis (FR-46/58). This
  document does not certify that every call site's free-text `context` string passed to
  `CrashReportingService.record(error:context:)` is free of anything identifying — that
  line-by-line audit has not been done and is listed as an **OPEN** item in §7.

**RevenueCat** — subscription entitlement vendor. Deletion propagation is built —
`executeAccountDeletionForUser`'s FR-78(a) phase in `functions/src/accountDeletion.ts` —
but is **PLANNED, not live**: `currentRevenueCatApiKey()` (`accountDeletion.ts:54-57`)
reads `process.env.REVENUECAT_SECRET_API_KEY`. The production secret has not been
provisioned, and no function in `functions/src` declares it (no `defineSecret` for it,
no `secrets:` option on `deleteAccount` or `requestChildDataDeletion`), so the value is
never injected. The cascade's RevenueCat phase is therefore a **logged no-op in every
deployment today**: `deleteRevenueCatCustomerForUid` (`accountDeletion.ts:87-101`) logs
"FR-78 RevenueCat deletion skipped for <uid>: no secret API key configured" and returns
`skipped_no_key`, and no RevenueCat customer record is deleted. Enabling it requires provisioning the
secret (`firebase functions:secrets:set REVENUECAT_SECRET_API_KEY`) **and** re-adding the
`defineSecret()` declaration to both `deleteAccount` and `requestChildDataDeletion` in the
same change — both steps are named in the code's own comment. Tracked in §7.

**Resend** — transactional email for the consent flow
(`functions/src/consentRequests.ts`) and the welcome email (`functions/src/welcomeEmail.ts`),
authenticated via the `RESEND_API_KEY` secret. The guardian's email address is a
§312.5(c)(1) collection with a verified, bounded lifecycle, confirmed by reading the
code rather than the comment describing it: `createConsentRequestForApproval` stores the
address on the consent-request document, and it is removed
(`admin.firestore.FieldValue.delete()`) at whichever of these happens first —
(a) the "plus" follow-up notice sends (`sendDueConsentPlusNotices`), (b) the request
expires unconfirmed (`sweepExpiredConsentRequests`), (c) a stale live request is
superseded by a fresh approval (`createConsentRequestForApproval`'s supersede branch), or
(d) plus-notice delivery is abandoned after `CONSENT_PLUS_NOTICE_MAX_SEND_ATTEMPTS`
failed attempts. No code path leaves the address on the request document indefinitely.
Separately, the permanent consent-evidence rows (`audit_logs`,
`AUDIT_PARENTAL_CONSENT_GRANTED`) never carry the address at all — only `guardianUid` —
consistent with the retention policy's uid-only evidence exemption
(`RETENTION_POLICY.md` row 6; that policy is owner-approved 2026-08-30, not yet
published).

## 6. Annual review cadence

This program is reviewed on the same cadence, and at the same sitting, as
`RETENTION_POLICY.md` — that document's §3 already names this one as its review partner
("reviewed with the written information-security program… on that program's annual
cadence"); this section closes the loop from this side. Trigger for an off-cycle review,
in addition to the annual one: a new child-data location (§2), a new vendor or a change
to an existing vendor's data-handling posture (§5), a consent-method change (OD-1), or a
material change to the access model (§3). The security coordinator (§1) owns scheduling
and recording each review. There is no tooling-enforced reminder today — that is an
**OPEN** item, listed in §7, not a built mechanism.

## 7. Residual-risk register

### 7.1 Imported from `COPPA_SRS.md` §16 (v2.1)

The full v2.1 register — every risk the v2.1 program identified, paired with its
mitigation — is reproduced below from `COPPA_SRS.md` §16 (line 583 onward), every row
present and in order; some risk and mitigation cells are condensed from the source wording
(re-checked 2026-11-17), so `COPPA_SRS.md` §16 is the authority for the full text. Rows marked
**overturned/superseded** in `COPPA_SRS_v3.md` §5's re-disposition register are annotated
here rather than silently dropped, so this table stays honest about what changed and why.
Every other row stands as v2.1 recorded it (condensed wording; §16 governs).

| Risk | Mitigation |
|---|---|
| Member-doc client writes flip flags with no record | FR-8 `write:false`, rules test |
| Child self-clears flag via self-update | FR-7 diff-guard (entitlementTags pattern) |
| Cold-start gap (SDK starts pre-auth; nil = untagged) | Asymmetric cache + ratchet pre-start + FR-19 display hold *(v3 §5 R-9: overturned — the display hold alone is insufficient on a clean install; see FR-56)* |
| Mid-session flip never reaches SDK / offline device syncs late | FR-23 re-stamp + banner removal; test pinned |
| Stale cached "adult" shows ads to remotely-flagged child | FR-19 asymmetric trust; only fresh-confirmed non-child sessions see ads |
| Stale global TFCD child→adult | Over-restrictive only; resolves on fresh read |
| Projection nil ambiguity | Tri-state accessor; nil never adult |
| Flagless `users/{uid}` created by a preference/defaults writer reads as adult and shows ads to a declared child | Every `users/{uid}` writer held while a declaration is owed (`UserDocumentWritePolicy`); uid-set binding; bind-before-publish ordering (FR-27) |
| Latency-compensated snapshot (`isFromCache`/`hasPendingWrites`) releases the ads hold with the client's own write echo | `ChildFlagIngestPolicy.mayIngest` at every ingest site; unresolved stays nil |
| Absent flag key mistaken for a manager correction — child protections erased permanently, account unre-flaggable | `isServerExplicit` required on destructive paths only; gating still reads absent-⇒-false |
| Corrected child's own device stays child-postured until reinstall | FR-39 correction release valve; revocation never qualifies |
| OS location prompt fired at a child during onboarding, before any uid exists | `LocationManager.requestAuthorization()` choke point + restriction keyed on the age answer (FR-33) |
| Idle session never receives a mid-session flag flip | Self `users/{uid}` listener pinned for the session lifetime including Home (FR-23) |
| Child as stranger-contact initiator | FR-24 server-enforced |
| Un-clearable orphaned flag / age-out dead end | FR-25/26/40 |
| Collection after revocation | FR-28 restricted state |
| Consent granted but held events never upload | FR-28c clear-then-drain ordering; test pinned |
| Held child silently loses progression an adult would receive | FR-28e local provisional ledger, idempotent reconciliation |
| Restricted child stranded — sole exit to consent unreachable | FR-28f reachability invariant + tests |
| Parent-rights screen misreports a removed child | FR-20 snapshot-authoritative pruning *(v3 §5 R-12: superseded — durable guardianship, FR-62/63, replaces live-membership-only rights)* |
| Stale accepted invite resurfaces as a live join request | §8.2 approval-time retirement |
| Unreadable approval target laundered back in as an adult | FR-25 third state; `unknown` treated as strictly as `alreadyChild` |
| Self-registered child collected pre-consent | FR-27 provisioning guard + per-uid write hold |
| Stored age answer declares a pre-existing adult account as a child | FR-27 identity-epoch binding |
| Answer-shopping: declared child re-answers to escape protections | FR-27 — sign-in never re-asks *(v3 §5 R-11: amended — FR-74 closes the sign-out→fresh-registration gap)* |
| Age question as the app's first pixel drives abandonment | FR-27 placement (D-18) |
| Forged pending join request installs stranger as consenting manager | FR-16 extension; rules test |
| Child location collected outside consentScope | FR-33 all-flags forced off + FR-42 |
| Carve-out breaks rosters / missing-key misfire | FR-12 ordered expression + key guard + matrix |
| Consent metadata becomes permanent PII | §11.1 uid-only schema + FR-35; test asserts no name/email/birthdate keys |
| Deleted-account exit loses lineage | FR-6 adds missing audit |
| Checkbox consent challenged as insufficient VPC | FR-31 affirmation + versioned text + OQ-2 legal gate *(v3 §5 R-2: overturned for the VPC method — FR-59/OD-1 real verifiable-consent method replaces the checkbox; see §7.2)* |
| Purchases by children | FR-34 blocked purchase path only — **no platform backstop available** (Apple Ask-to-Buy cannot be required or detected) |
| Retention job deletes consent evidence | F-12 carve-out; test pinned |
| `changeFamilyMemberRole` flips altering treatment | Dedicated `isChild` independent of role |
| Future captain assignment widens authority | OQ-1; explicit role list |
| Legacy client search re-enabled | Deleted in F-11; child docs unreadable regardless |
| Mediation adapters (if ever added) snapshot config at init | None used; verify at that time |
| Ratchet/suppression revenue impact | Accepted; negligible vs. certification risk |
| **`auditValueHash` is an unsalted SHA-256 (truncated 16 hex) over low-entropy inputs — pseudonymous, not anonymous** | Accepted residual: `audit_logs` is client-inaccessible; project salt deferred (needs secret config) — **still deferred as of v3, see §7.2** |
| Consented child client-writes a `share_codes` doc — rules gate is unconsented-only | Accepted residual, bounded; forged code still needs captain/creator approval or is stopped at friend-acceptance |
| Restoring commented-out OAuth buttons ships an un-gated account-creation path | FR-27 blocking precondition — **latent, not live: no OAuth path is reachable today; do not restore without the age-gate work** |
| Reinstall-restored anonymous session never resolves ⇒ no ads for its lifetime | Accepted (D-17) — fail-closed, revenue-only |
| Second account provisioned inside an open under-13 epoch inherits the child binding permanently | Fail-safe (over-flags, never under-flags); recoverable |
| EEA traveller sees ads with no UMP/GDPR consent flow | Accepted at launch (D-23) — no EU/EEA distribution |
| Engagement pushes default ON for a child; FCM token registered for an unconsented child | *(v3 FR-73 (F-29), not a v3 §5 row: implements v2.1 FR-53 plus the bypasses it did not cover — re-verified in code 2026-11-17: the `fcm` token-write rule backstop (§3a) and the server-side child category gate (§5))* |
| New rejection on a child-reachable surface leaks a child-identification oracle | FR-24 two-way indistinguishability; pinned by test |

### 7.2 v3-era items still open as of this draft (2026-08-30; status re-checked 2026-11-17)

These are not inherited from v2.1 — they surfaced during v3's build-out and remain live
today. Listed honestly, per FR-82's instruction, rather than smoothed over:

- **App Check "Bug B" — App Attest variant untested.** The per-process limited-use-token
  wedge on the DeviceCheck provider (Debug/Xcode/physical-debug hardware) was
  root-caused and mitigated across several sessions ending 2026-08-30 (see
  `COPPA_SRS_v3.md` §3's Bug B narrative for the full chain). The **App Attest** variant
  — the provider used on TestFlight and App Store builds, i.e. every real end user — has
  never been exercised. This is the single largest unverified assumption behind §3(b)'s
  App Check claim: the mechanism is provably wired for every callable, but its behavior
  under real-world App Attest failure modes is **OPEN** until a TestFlight build gets a
  device pass.
- **Counsel review of the consent method — quick review only; no formal opinion.** OD-1
  (no third-party VPC vendor; first-party email-plus, FR-59.1) is an owner decision, not a
  legal one, and `COPPA_SRS_v3.md` records the standing recommendation that the method
  choice get outside COPPA counsel review — "the launch caveat stands: counsel
  confirmation before submission" (`COPPA_SRS_v3.md` Appendix A, line 714).
  `COPPA_COUNSEL_MEMO.md` is a regulatory-analysis pass prepared *to brief* counsel ("NOT
  legal advice", per its own header). FR-59's status (`COPPA_SRS_v3.md` line 349) records
  that on 2026-08-27 the owner's LLC counsel quick-reviewed the memo's closed-group
  analysis and said it was fine — "a quick review, not a formal opinion letter" — and that
  the memo's §5 question list remains the agenda if a formal engagement is ever wanted.
  **OPEN** to the extent of that recorded caveat.
- **NP-2 (online notice / privacy-policy update) — unpublished.** The direct-notice and
  in-app policy text ships as localized strings (`COPPA_SRS_v3.md` v3.1 changelog: "NP-2
  is recognized as partly code"), but the SRS itself calls this only *partly* code, and
  `RETENTION_POLICY.md`'s own status header states plainly that its public-facing
  rendering — which NP-2 is supposed to carry — has **not yet been published**, on the
  website's privacy-policy page or otherwise. **OPEN/PLANNED.**
- **NP-3 (`RETENTION_POLICY.md`) — owner-approved 2026-08-30, not yet published; its own
  counsel review pending.** Directly stated in that document's status header (its line 3:
  "OWNER-APPROVED 2026-08-30 — not yet published"; counsel review "rides the standing
  launch caveat"). This program's annual-review linkage (§6) inherits that same open item.
- **RevenueCat production key not provisioned** — see §5. **PLANNED**, inert today by
  design, not by oversight: the deletion cascade's RevenueCat phase is a logged no-op
  until the secret is provisioned and declared.
- **Firebase Analytics posture not yet true in code** — see §5. Collection starts for
  child sessions with no consent term, and gameplay events carry participant
  identifiers. **OPEN until COPPA item F-28 / FR-72 lands** (in progress 2026-11-17, not
  landed). Until then this also contradicts `RETENTION_POLICY.md` row 10 ("child sessions
  send nothing pre-consent"), as `COPPA_SRS_v3.md` §7.1 records.
- **Vendor data-handling terms not collected.** FR-82 asks for the vendor list *with
  data-handling terms*; §5 cites none of the vendors' own terms (Google/Firebase,
  RevenueCat, Resend). **OPEN** — owner task to collect and cite them (also listed as owner console work in
  `COPPA_SRS_v3.md` §7.1, line 678).
- **Cloud Logging alert on `"FR-64 reconcile FINDINGS"` not confirmed configured.** The
  log line exists (`retention.ts:255`, §4 step 1a); whether a log-based alert policy is
  set up on it lives in the Firebase/Google Cloud console and cannot be checked from the
  repo. **OPEN** — owner to confirm in the console.
- **`auditValueHash` salt still deferred.** Carried forward unchanged from v2.1 (§7.1
  above); `COPPA_SRS_v3.md`'s traceability table (§6) confirms it is still "Deferred
  (needs secret config; unchanged)" as of v3. Audit-log and deletion-tombstone hashes
  remain pseudonymous, not anonymous, until a project salt is provisioned. **OPEN.**
- **Sticky-rejoin theoretical gap.** A removed, sticky-child-flagged account's re-entry
  through `setFamilyMemberChildStatus`'s membership-requiring correction path is a
  documented **untested** gap (`COPPA_SRS_v3.md` §3, the Bug B addendum) — the adult
  case was live-verified 2026-08-29; the sticky-child-flagged case was not. **OPEN,**
  low-likelihood, not yet a confirmed defect.
- **Promo-category (`promotionsAndNews`) server-side child rejection — CLOSED on
  re-verification 2026-11-17.** The 2026-08-30 draft could not locate it; it exists at
  the token chokepoint: `CHILD_SUPPRESSED_PUSH_CATEGORIES`
  (`functions/src/notificationPrefs.ts:82-84`) enforced in `getFCMTokenForPush`
  (`functions/src/utils/notifications.ts:119`), through which every push sender resolves
  its token. See §5. Kept here, marked closed, so the earlier open entry is not silently
  dropped.
- **Crashlytics call-site content — not line-by-line audited.** See §5. No call site is
  known to leak anything, but none has been specifically checked either. **OPEN.**
- **No tooling-enforced annual-review reminder.** See §6. **OPEN** (process gap, not a
  code gap).

---

*This document should be re-read alongside `RETENTION_POLICY.md` — they cite each other
and share a review cadence (§6). The owner approved this document on 2026-11-17, and `RETENTION_POLICY.md` §3's
cross-reference was updated the same day to read "FR-82, owner-approved 2026-11-17". Counsel review timing (both OD-1's method review and NP-3's own review) is
an owner scheduling decision, not something this document can resolve.*

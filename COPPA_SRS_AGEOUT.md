# RoadTrip Royale — Age-Out SRS (Phase 2)

**Version:** 1.5 — 2026-08-15 (**OD-20 decided — collect birth month + year**, on the §312.7 reasonably-necessary test: month is required for correct classification, so collecting it is better minimization, not worse. The v3 FR-55 change request is therefore live and has been accepted by the v3 session as v3.7. Adds **§3.1**: F-70 folds *into* v3's F-14b rather than following it — same file, and `ageOutYearMonth` cannot be computed without the month F-14b introduces — plus a worked boundary-symmetry check showing the gate rule and the detection rule meet exactly at the birthday month. Prior header follows.)
**Version:** 1.4 — 2026-08-15 (**OD-16 decided — build it.** Adds **FR-117 / F-74**: at the FR-59 consent moment, the verified parent confirms or corrects the child's declared birth month/year, recovered by reverse lookup from `ageOutYearMonth` with no new stored field. Corrections are handled asymmetrically — protective applies immediately, permissive routes through v2.1 FR-39's existing correction valve so no second flag-clearing door opens. Recorded as **OD-21**. Also corrects FR-110(a)'s minimization claim: the marker is losslessly reversible to birth year-month, so it is equivalent to it, not a reduction — only the day is minimized away.)
**Version:** 1.3 — 2026-08-15 (**owner ruling on the age boundary.** COPPA's line is under-13, so protection now runs 12→13 rather than 13→14. §2 rewritten: the cutoff cannot simply move from `< 14` to `< 13`, because year-only math cannot express 13 — the `D = 13` cohort is half 12-year-olds. Implemented instead by making the answer exact (birth month + year, both discarded after classification), recorded as **OD-20**, with an explicit fallback if the owner declines the extra field. FR-110 becomes `ageOutYearMonth`; detection compares year-months. **OD-16 expanded** at owner request. A matching change request for v3 FR-55 / §5 R-1 is relayed separately — v3 is not this session's file.)
**Version:** 1.2 — 2026-08-15 (**second ID move, no content changed.** v4 vacated FR-84…FR-91 / F-40…F-46 back to v3 and relocated to FR-100…FR-107 / F-60…F-66, so this document moved ahead of it to **FR-110…FR-116 / F-70…F-73**. Full mapping in `COPPA_SRS_v4.md` §0.1.)
**Version:** 1.1 — 2026-08-15 (v1.1 renumbered out of v3's block per the v3.5 ID-SPACE NOTICE: this document originally claimed FR-92…FR-98 / F-47…F-50, which v3.5 allocated to device transfer and consented-child parity. No content changed in the renumber.)
**Version:** 1.0 — 2026-08-15. Authored against local HEAD `0fc73bc` on `feature/MVPPush`.
**Scope:** the transition of a child account out of the COPPA-protected posture when the user reaches the app's adult boundary — detection, gating, notification, credential collection, and the closure of parental rights.
**Classification (answering the v3 session's question):** this document is **part of the v4 program**, not a separate program and not scratch. It is a companion to `COPPA_SRS_v4.md`, numbered from the v4 block, owned by the v4 session, and governed by v4's execution model. Treat "v4" and "AGEOUT" as one program in two files.
**Precedence:** `COPPA_SRS.md` v2.1 (frozen base) → `COPPA_SRS_v3.md` v3.5 (active program) → `COPPA_SRS_v4.md` (consent UX & egress boundary) → this document. Where they conflict, later wins.
**ID space (v4.3):** the v4 program allocates **FR-100…FR-119**, **F-60…F-79**, **OD-10…OD-29**. This document defines **FR-110…FR-117**, features **F-70…F-74**, owner decisions **OD-16…OD-21**; `COPPA_SRS_v4.md` defines FR-100…FR-107 / F-60…F-66 / OD-10…OD-15. v3 holds FR-1…FR-99, F-1…F-56, OD-1…OD-9 — including FR-84…FR-91 / F-40…F-46, which the v4 program has **released**. Neither program allocates into the other's block.
**Phase:** 2 — deliberately **not** launch-blocking, with **one exception** (§1, FR-110) that is launch-blocking because the feature is unbuildable later without it.
**Legal frame:** COPPA applies to children under 13. When it stops applying, the operator's COPPA obligations end — but the account's restrictions, the parent's expectations, and the app's own contract posture do not update themselves. This document is mostly about *not* changing things silently.

---

## §1 The one launch-blocking dependency

**Age-out requires retaining something derived from the birth year, and the current design discards it.**

Today the age gate asks for a birth year, derives a category, and **throws the birth year away** — v3 FR-55's own words are "still discarded." Nothing anywhere records *when* a given child stops being a child. v2.1 §11.1 has an optional year-granular `expectedAgeOutYear` in consent metadata, but it is optional, year-only, and has no local counterpart; and under v3 FR-60's local-first model a never-consented child has **no server record at all**, so for that entire population there is nothing to compute from.

**The consequence is one-way.** A child who declares under-13 in 2026 turns 13 in, say, 2029. In 2029 the app has no birth year, no age-out marker, and no lawful way to ask again — D-17 forbids mid-session re-prompts and FR-74's cooldown deliberately makes re-answering sticky. That account stays in the child posture permanently. Shipping the capture later fixes only accounts created *after* it lands; **every account from launch until then is stranded**.

**FR-110 is therefore launch-blocking** even though the feature it serves is Phase 2. It is one integer, written in two places, roughly five lines of code. The rest of this document can wait years.

---

## §2 The boundary is 13 — and year-only math cannot express it

**Owner ruling 2026-08-15:** the boundary moves to the true COPPA line. COPPA covers children **under 13**; a 13-year-old is outside it. Protection therefore runs 12→13, not 13→14. The owner is right about the statute, and v3 FR-55's `< 14` cutoff changes accordingly.

**But the cutoff cannot simply be edited from `< 14` to `< 13`, because that does not implement "13."** With a year-only answer, `D = currentYear - birthYear` is ambiguous by construction:

| `D` | Actual age | Certainty |
|---|---|---|
| ≤ 12 | 11 or 12 | certainly under 13 |
| **13** | **12 or 13** | **ambiguous — birthday passed this year, or not** |
| ≥ 14 | 14+ | certainly 13+ |

The `D = 13` cohort is a coin flip whose bias is the time of year. So the two year-only cutoffs are not "wrong" and "right" — they are two ways of guessing:

- **`D < 14` (v3 today):** every actual 12-year-old is protected. Actual 13-year-olds are over-protected for up to a year. The cost is product, not legal.
- **`D < 13` (a literal reading of the ruling):** every actual 13-year-old is classified correctly — **and roughly half of that cohort, who are still 12, are classified as adults.** Averaged over a year that is ~50% of `D = 13`. Those are actual under-13s routed to ads, analytics, location and unconsented collection. That is not a product cost; it is the violation COPPA exists to punish, self-inflicted at the one screen designed to prevent it.

**Therefore: implement the ruling by making the answer exact, not by moving the guess.** Collect **birth month + year** at the age gate, classify on both, discard both immediately as today. Then `D = 13` resolves precisely — birthday passed ⇒ 13+, not yet ⇒ 12 — and the boundary genuinely sits at 13, with nobody over-protected and nobody under-protected. The residual is a ≤1-month window for users whose birthday falls in the current month, resolved toward under-13 (fail-closed; affects ~1/12 of the boundary cohort, for at most a few weeks).

**On collecting one more field:** a month picker is not a meaningful privacy cost. It is used solely for classification, discarded in the same breath as the year, never stored, never transmitted. The FTC's own age-screen guidance contemplates asking for a date of birth for exactly this purpose, and the change *reduces* misclassification in both directions — more accurate screening is a privacy improvement, not a regression. OD-20 records the choice.

**If the owner declines the extra field**, the honest fallback is to keep `D < 14`, not to adopt `D < 13`. Year-only forces a choice about which way to be wrong, and being wrong toward "not a child" is the direction that carries legal exposure. This is the one place in either program where I would push back on a literal implementation of the ruling rather than simply executing it.

**Consequence for this document:** with an exact boundary, an aged-out user has just turned 13. They are still a minor and still cannot form a binding contract in most states — §6 addresses what that means for the ToS gate.

---

## §3 Feature roadmap

| ID | Feature | Covers | Risk | Model / effort | Depends | Gate |
|---|---|---|---|---|---|---|
| **F-70** | Age-out data capture (`ageOutYearMonth`, local + server) | FR-110 | High | Sonnet | **fold into v3 F-14b** — see §3.1 | **L (launch)** |
| **F-71** | Age-out detection + held transition state | FR-111, FR-112 | High | Opus / high | F-70 | Phase 2 |
| **F-72** | Transition gate: ToS/PP/safe-driving re-acceptance + email collection | FR-113, FR-114 | High | Opus / high + verify | F-71 | Phase 2 |
| **F-73** | Parent notification + guardianship closure | FR-115, FR-116 | High | Sonnet | F-71, v3 F-20 | Phase 2 |
| **F-74** | Parent confirms/corrects the child's date at consent | FR-117 | Medium | Opus / high | F-70, v3 F-17 | Phase 2 |

### §3.1 Sequencing: F-70 folds into v3's F-14b, it does not follow it

The v3 session is planning **F-14b** — reworking `AgeGateStore.category` to exact month+year classification, since F-14 shipped and deployed under `< 14`. F-70 must land **in that same change**, not after it:

- Both edit `AgeGateStore.swift`, its keys, and its boundary tests. v3 §3.2's own hard-won note is that concurrent agents in one file produced today's phantom failures — this is that situation exactly.
- **F-70 is not merely adjacent, it is downstream:** `ageOutYearMonth` cannot be computed without the birth month that F-14b introduces. Building F-70 first would mean writing a year-granular marker and immediately rewriting it.
- The classifier's signature changes once, and both the boundary tests and the age-out capture tests are authored against the final shape.

**Consequence:** F-70's launch-blocking status is discharged when F-14b lands with the capture included. If F-14b ships without it, F-70 becomes a second edit to the same file for no reason, and every account created in between is stranded per §1.

**Boundary symmetry check (both ends agree).** The gate classifies the birth month itself as `.under13` (fail-closed on the unknown day). FR-111's detection mirrors it with a strict comparison, `ageOutYearMonth < currentYearMonth`, so a child stays protected *through* their birthday month and ages out at the start of the following one. Worked example — born 2014-03 ⇒ `ageOutYearMonth = 202703`: Feb 2027 child, **March 2027 (birthday month) still child**, April 2027 ages out. The two rules were written independently and meet exactly; if either is later "simplified," they must be re-checked together.

---

## §4 Requirements

### FR-110 (F-70, LAUNCH-BLOCKING) — Capture the age-out marker at the moment the answer is given

> **STATUS 2026-08-27: (a) LOCAL — LANDED** with v3 F-14b (`AgeGateStore.ageOutYearMonth`, persisted at the under-13 answer, survives `clearAnswer()`/correction, marker-less re-asserts preserve it; boundary symmetry with the (strict) detection rule pinned in `AgeGateStoreTests`). **(b) server-required consent/declaration fields and (c) provisional-row carriage ride the v3 §3.1.2 email_plus wave**, per the sequencing rule that the consent-record schema must not be built without this field.

- **(a) Local.** `AgeGateStore` persists `ageGate.ageOutYearMonth` alongside the existing epoch answer, at the moment the under-13 answer is recorded. Value is a single comparable integer `(birthYear + 13) * 100 + birthMonth` (e.g. born 2014-03 ⇒ `202703`) under OD-20's month+year gate, or `(birthYear + 13) * 100` if the owner stays year-only. **The raw month and year are discarded exactly as today.** *Honest framing:* this integer is losslessly reversible to the birth year-month (`birthYearMonth = ageOutYearMonth - 1300`), so it is **equivalent to** storing birth year+month, not a reduction of it. What is actually minimized is the *day*, which is never asked for and never stored. The reversibility is deliberate and load-bearing — FR-117 needs it to show a parent the date being confirmed — and it is not an identifier at year-month granularity. It follows the epoch's lifecycle **with one exception**: like the ratchet and the declared-uid history, it survives `clearAnswer()` (sign-out, deletion), because it is device-scoped protection state, not session state. v2.1 §4's precedence rules for cache/ratchet/declared-history gain this key so the interaction surface stays one document.
  *Naming note:* the key is `ageOutYearMonth`, not `expectedAgeOutYear` — the v2.1 §11.1 consent-metadata field of that older name is year-granular and is superseded, not reused, so the two cannot be silently conflated at a call site.
- **(b) Server.** `ageOutYearMonth` becomes **required, not optional**, in the consent record written by v3 FR-59's grant transaction, and in the `declareChildRegistration` audit row, superseding v2.1 §11.1's optional year-granular `expectedAgeOutYear`. Uid-only shape unchanged — a year-month integer is not PII, and it is coarser than the birth date already implied by the declaration.
- **(c) Provisional accounts.** For the v3 FR-60 redemption window (uid exists, consent pending), the value rides the declaration row, so a later-approved child carries it without re-asking.
- **(d) No inference elsewhere.** No other code path may re-derive an age or a birth year. Standing rule, grep-pinned, same discipline as v3 FR-55's accept clause.

*Accept:* under-13 answer writes the local key with the correct year-month; `clearAnswer()` preserves it; declaration and consent rows carry it; a fixture consent record without the field is rejected server-side; a boundary fixture pair (birthday-this-month vs next-month) classifies fail-closed; no second age-derivation site exists (grep).

### FR-111 (F-71) — Detection is server-authoritative where an account exists, local where it does not

- **(a) Consented / provisioned children:** a scheduled job (reusing v3 FR-77's paged `retentionCore` bounds and the D-20 midnight-Pacific schedule) evaluates `ageOutYearMonth < currentYearMonth` daily (strict `<`, so the birthday month itself stays protected — the fail-closed residual of §2) and marks the account `ageOutPending`. Server-authoritative because the restrictions being lifted are server-enforced.
- **(b) Never-consented local children** (v3 FR-60's zero-footprint population) have no account to evaluate. The local check runs at launch against the FR-110(a) key and lifts the device posture through the same held transition (FR-112) — there is no server involvement because there is no server record.
- **(c) The device ratchet and declared-child history are *not* cleared by age-out** on a device that may still be shared. Only the current identity transitions. v2.1 FR-39's `ChildDeviceCorrectionPolicy` governs device-marker lifting and is untouched by this program — age-out is not a correction, and must not route through the correction valve (a correction asserts the flag was *wrong*; an age-out asserts it was right and has expired).
- **(d) `isChildAccount` clears only through this path or FR-39's correction valve.** The stickiness rule of v2.1 §4 otherwise stands.

*Accept:* job fixtures either side of the boundary; a local-only child ages out with zero network calls; ratchet survives; a revoked (sticky) child does not age out into an unrestricted state without the transition gate; adversarial verify (early lift / permanent hold).

### FR-112 (F-71) — Nothing lifts silently: the held transition state

Between detection and completion of the FR-113 gate, the account sits in **`ageOutPending`**, in which **every child protection remains in force**. Ads stay off, analytics stays scoped, location stays force-off, purchases stay suppressed, search exclusion holds, family-only trip constraints hold.

This is the load-bearing requirement of the document. An account that becomes searchable, ad-eligible, and location-capable overnight — with no interaction from the user and no word to the parent — is the worst version of this feature. The parent consented to a bounded set of practices; the birthday does not communicate the change to them.

`ageOutPending` reuses v2.1 FR-28's restricted-state machinery rather than introducing a fourth posture: the child postures already model "playable, collection-limited," which is exactly the state required here. `ChildSessionPosture` gains no case; the coordinator resolves `ageOutPending` to the existing child-directed posture until the gate completes.

*Accept:* posture matrix showing all protections held during `ageOutPending`; no ad request, no location capture, no analytics widening, no purchase path while pending; the state is durable across relaunch.

### FR-113 (F-72) — The transition gate

Presented on next launch after detection. One flow, dismissible only by completion or by "not now" (which returns the user to play in the held state — never a lockout).

- **(a) A plain-language "what changes" screen** — first, before any acceptance control. What was restricted, what is about to be available, and that a parent was told. Written for a 13-year-old, ×3 locales.
- **(b) ToS, Privacy Policy, and safe-driving acknowledgment re-accepted in the user's own name**, version-stamped under the OQ-2 discipline, recorded against the uid. The safe-driving acknowledgment is not a COPPA artifact — it is a product/liability one — and this is a natural moment to re-present it.
- **(c) Per-capability opt-in, not a blanket unlock.** The capabilities that were force-off (location, searchability, personalized-ads eligibility) present as **individually off by default**, each with the v4 FR-103 card pattern and per-scope policy anchors. The user opts into each. A gate that flips everything on at once is the silent-lift problem with an extra tap.
- **(d) Completion clears `ageOutPending`** and resolves the posture normally on the next FR-23 seam evaluation.
- **(e) "Not now" is durable and non-punitive** — the held state persists, the gate re-presents at a later launch (OD-18 cadence), and play is unaffected throughout.
- **(f) Accessibility:** VoiceOver labels/values/hints on every card, Dynamic Type without clipping, state never by color alone, Reduce Motion respected.

*Accept:* gate presents once per launch until completed or deferred; deferral leaves protections in force; each capability opts in independently; version stamps recorded; localization ×3; a11y audit; adversarial verify (capability enabled without its opt-in / user permanently unable to complete).

### FR-114 (F-72) — Email collection at age-out

Under v3 FR-60 a child account has no email and no password. Age-out is the first lawful and natural moment to offer credentials, and the first moment the account can be recovered by its actual owner.

**Relationship to v3 FR-92 (parent-initiated device transfer).** The two solve the same underlying problem — a credential-less anonymous account is strandable — at different points in the account's life, and they are complementary, not alternatives. FR-92 is the *pre*-age-out answer: the captain issues a `device_transfer` code, no credentials ever reach the child, and it stays the recovery path for a consented child on a new device. FR-114 is the *post*-age-out answer: the user is no longer a child, so they may hold their own credentials. Neither supersedes the other, and FR-114 must not be treated as a reason to defer FR-92 (a child stranded at 12 cannot wait two years for a birthday). One constraint: once FR-114 credentials exist on an account, FR-92's transfer path for that account is retired — a parent-issued transfer code must not be able to rebind an account whose owner now holds their own login.

- **(a) Offered, not required.** Play continues without it. A user who declines keeps an anonymous-uid account exactly as before.
- **(b) Unique messaging**, distinct from the standard sign-up copy: this is an existing account gaining credentials, not a new registration. Copy states that the account, trips, XP and progression carry over unchanged — the migration anxiety is the actual barrier here, not the form. ×3 locales.
- **(c) The welcome-email suppression of v2.1 FR-35(c) lifts for this account** once `isChildAccount` is false — but the mail sent is the **age-out variant** (OD-17), not the generic welcome. A "welcome to RoadTrip Royale!" to someone who has played for two years is a defect.
- **(d) Contact containment unchanged.** The address lands in `private/contact` per v2.1 FR-43, never on the peer-readable `users/{uid}` doc. No display name is captured (D-15: no real names, app-wide, at any age).
- **(e) Not a verification step.** This is account recovery, not identity proof; it carries no consent semantics and must not be recorded in any consent structure.

*Accept:* credential attach preserves uid, trips, XP, entitlements and progression (integration test); declining leaves the account fully playable; age-out mail variant sent, generic welcome suppressed; address lands only in `private/contact`; rules deny peer reads.

### FR-115 (F-73) — The parent is told, by push and by email

The guardian consented to a bounded set of practices; those bounds are about to change. Telling them is not a COPPA obligation once the child is 13+ — it is the difference between a product a parent trusts and one they discover changed behind their back.

- **(a) At detection** (not at completion): the guardian resolved via v3 FR-62's guardianship record receives a push notification in an existing family category **and** an email. Email is required because a push token may be absent or revoked, and this is the message that must not be missed (v4 OD-15's reasoning).
- **(b) Content:** the child's account has reached the age boundary; COPPA-based parental review and deletion rights end at completion of the transition; here is what the user will be able to enable; here is the deletion path **while it is still available**.
- **(c) An in-app badge** on the family surface, using v2.1 FR-25's sticky-surfacing pattern and v4 FR-104's badge mechanism — no third badge system.
- **(d) A deletion window before rights lapse (OD-19, proposed 30 days).** During `ageOutPending` the guardian's v3 FR-62/FR-63 review and deletion rights remain fully live. This is deliberate: a parent who wants the data gone should not lose the ability on a birthday they did not know about.
- **(e) No notification to a guardian who never consented** — under v3 FR-60 that guardian does not exist, and a never-consented child has no guardian record to resolve.

*Accept:* push + email + badge on detection; content localized ×3; guardian rights verified live throughout `ageOutPending`; deletion during the window succeeds through the existing v3 FR-63 flow; no message to non-guardians.

### FR-116 (F-73) — Guardianship closes, evidence survives

- **(a) On completion**, the v3 FR-62 guardianship record is **ended, never deleted**: `endedAt` set, `endedReason: "age_out"`. It is consent evidence and retains under v3 FR-77's audit-row exemption.
- **(b) COPPA-based parental review and deletion rights end** with the guardianship. The parent retains whatever rights the product grants a family manager over a member (roster management), which are not COPPA rights and are unchanged.
- **(c) The consent record is not deleted and not marked revoked** — a revocation is a withdrawal of consent, an age-out is its expiry. The distinction matters if the record is ever produced as evidence (v2.1 D-1's withdrawal ≠ correction principle, extended: expiry ≠ withdrawal ≠ correction).
- **(d) The account's own consent scopes (v3 FR-65) retire.** Scopes are a child-consent construct; post-age-out the user's own per-capability choices from FR-113(c) govern, and v4 FR-104's re-affirmation machinery no longer targets this account.
- **(e) Analytics:** one typed event at completion from the service layer (never a View), carrying no age, no year, and no guardian reference — an opaque transition marker only. Nothing may fire that is unique to formerly-child accounts in a way that re-identifies the cohort (v2.1 §12).

*Accept:* guardianship ended not deleted; consent row intact and distinguishable from a revocation; scope retirement verified; post-completion guardian read of the inventory denied; event catalog audit shows no age-derived parameter.

### FR-117 (F-74, Phase 2) — The parent confirms or corrects the child's date at consent

*(Owner request 2026-08-15: "should the parent CORRECT this date when they sign consent? We reverse look up and ask the parent that date?" — yes, and the reverse lookup works.)*

The age answer is self-declared by a child, at a screen designed to be neutral rather than accurate. The FR-59 consent moment is the one point in the account's life where a **verified adult** is present and attentive, which makes it the best available opportunity to correct it.

- **(a) Reverse lookup.** `ageOutYearMonth − 1300` yields the declared birth year-month, so the consent flow can display what the child entered without any additional stored field. This is the property noted in FR-110(a).
- **(b) Presentation.** During the FR-103 scope cards, one row shows the declared birth month/year with a confirm control and an edit control. Neutral copy — it must not read as an accusation, and it must not imply the consent is contingent on changing it. Confirming is one tap and is the default path.
- **(c) Asymmetric handling of a correction — the load-bearing part.** Direction decides the machinery:
  - **Protective direction** (parent says the child is *younger* than declared ⇒ later age-out): applied immediately and unconditionally. It only extends protection, so no additional evidence is required.
  - **Permissive direction** (parent says *older* ⇒ earlier age-out, or old enough that they are not a child at all): routed through v2.1 FR-39's `ChildDeviceCorrectionPolicy` with the FR-59 verification evidence attached. It **must not** open a second path to clearing child status. The VPC artifact is stronger evidence than anything FR-39 accepts today, but the valve stays the single door — a new door is exactly the laundering surface v3 FR-66(b) spent a feature closing.
- **(d) What it does not fix, stated plainly.** This only reaches children who *entered the child flow*. A 12-year-old who claimed to be 15 never triggers a consent screen, so no parent is ever asked. FR-117 improves age-out accuracy for consented children; it is **not** an age-verification mechanism and must not be described as one.
- **(e) Minimization.** The corrected value is converted to `ageOutYearMonth` and the raw entry discarded, exactly as at the gate. No date of birth is stored at any point.
- **(f) Audit.** A correction writes an audit row (uid-only, existing `writeAuditLog` shape) recording direction and that it was parent-supplied under a verified consent — never the date itself.

*Accept:* reverse lookup renders the declared month/year; confirm is one tap and the default; protective corrections apply with no extra gate; permissive corrections provably route through FR-39 and cannot clear child status outside it; corrected value round-trips to a new `ageOutYearMonth`; no DOB persisted anywhere (grep + fixture); localization ×3; VoiceOver on the confirm/edit row.

---

## §5 Non-goals

- **A teen (13–15) band.** v2.1 OQ-3 and v3 L-10 both leave it out of scope; this document does not re-open it. Google's TFUA tagging remains unimplemented and unneeded while D-23's no-EEA-distribution ruling stands. If EEA distribution is ever enabled, the teen band and TFUA are revisited together with D-23, not here.
- **Re-verifying age at the boundary.** The age-out derives from the original declaration. A user who lied at the gate ages out on their lie; that is equivalent to lying at the neutral screen and is accepted on the same basis as v3 OD-9(v).
- **Migrating child data into a different account.** The uid is stable across age-out. There is no migration and none should be built.
- **Lifting device-scoped protections.** FR-111(c): the ratchet and declared history are device state and outlive any one identity's age-out.

---

## §6 Honest limitations

**A 13-year-old still cannot form a binding contract.** FR-113(b)'s re-acceptance is meaningful as notice and as a record of what the user was shown; it is not a substitute for the enforceability that a parent's agreement provided. The parent's original acceptance is what carries contractual weight, and it is not withdrawn by the age-out. Do not let FR-113(b) be described internally as "the user has now agreed to the ToS" in a sense that implies enforceability against a minor.

**COPPA ending is not privacy ending.** Once the user is 13+, the amended Rule stops governing them — but the app's own retention schedule (v3 FR-77), egress boundary (v4 FR-102), and published policy still apply. Nothing in this document should read as "protections may now be relaxed"; it reads as "the *legally mandated* subset no longer applies, and the user chooses the rest."

**The self-declared year is the whole foundation.** Every requirement here derives from an integer the user typed at a neutral screen years earlier. That is the accepted design (v3 OD-9(v)), but it means age-out accuracy is exactly as good as the original answer, and no downstream mechanism improves it.

---

## §7 Owner decisions

- **OD-16 — DECIDED 2026-08-15 (owner): build it.** The question was only "confirm this ships at launch" — answered yes. Rationale retained below.
- **OD-16 (rationale): store one integer at the age gate.** *(Expanded 2026-08-15 — the owner had not seen this item before; §1 is the full argument, this is the short version.)*
  **What it is:** when a user answers the age question, also write `ageOutYearMonth` — the year-month they turn 13 — to device storage and, for consented children, to the consent record. Raw birth month/year stay discarded exactly as today.
  **Why it blocks launch even though age-out is Phase 2:** the gate currently discards the birth year, so nothing records when a child stops being one. A kid who declares under-13 at launch and turns 13 two years later cannot be detected — there is no stored value to check, and re-asking is closed off by D-17 and FR-74. Adding the field in 2028 helps only accounts created in 2028. **Every child account from launch until then is permanently stuck in the child posture** — no ads, no analytics, no location, no purchases, forever, with no lawful recovery path.
  **Cost:** about five lines. One `UserDefaults` key, one field on two existing server writes. No UI, no migration (pre-release), no schema change.
  **Recommendation: yes.** This is the cheapest item in either program and the only one whose omission is unrecoverable rather than merely deferred.
- **OD-21 (blocks F-74; Phase 2, not urgent): parent date confirmation at consent.** Recommended: build it per FR-117 — the consent screen is the only moment a verified adult is present, and the reverse lookup makes it free of new storage. Two things to be deliberate about: the permissive direction must route through FR-39's existing correction valve rather than opening a second door, and the feature must not be described internally as age verification, since it never reaches a child who overstated their age at the gate.
- **OD-20 — DECIDED 2026-08-15 (owner): collect birth month + year.** Owner's test — "would it be considered data we should reasonably save?" — is the right one, and it resolves in favour of collecting. §312.7 asks whether collection is *reasonably necessary for the purpose*, not whether it is small. The purpose is classifying a child correctly, and month is **required** to do that: without it the boundary cohort is a coin flip and misclassification is the exact harm this program exists to prevent. More accurate screening is better minimization, not worse. Retention side: the raw entry is discarded at classification; what persists is `ageOutYearMonth`, necessary for FR-110/FR-111 and deleted with the account under v3 FR-77. The day is **not** collected — see the residual below. Analysis retained below.
- **OD-20 (analysis): month + year at the age gate, or stay year-only?** *(New 2026-08-15, raised by the owner's ruling to move the boundary to 13 — see §2 for the full analysis.)*
  **Recommended: collect birth month + year, discard both after classification.** This is what makes the ruling implementable: it puts the boundary exactly at 13, with nobody over-protected and nobody under-protected. Cost is one extra picker wheel on a screen that already exists.
  **The alternative is not "keep it simple" — it is "choose which way to be wrong."** Year-only leaves the `D = 13` cohort genuinely ambiguous (12 or 13, depending on whether the birthday has passed). `D < 14` errs toward protecting them, which costs product. `D < 13` errs toward treating them as adults, which means collecting from actual 12-year-olds without parental consent — the precise thing the age screen exists to prevent.
  **If declined:** keep `D < 14` as-is and do not adopt `D < 13`. The v3 FR-55 change request is withdrawn in that case, and the boundary stays where it is.
- **OD-17 (blocks F-72): age-out email variant.** Recommended: a distinct template, not the generic welcome. Copy owner-approved under the OQ-2 discipline before F-72 ships.
- **OD-18 (tuning, default acceptable): gate re-present cadence after "not now" = every 7 days**, unlimited deferrals, never a lockout.
- **OD-19 (blocks F-73): guardian deletion window during `ageOutPending`.** Recommended: **30 days** minimum, and the window does not begin until the notification of FR-115(a) is actually sent.

---

## §8 Test plan

Add to the v2.1 §14 suites: FR-110 capture and `clearAnswer()` survival; FR-111 boundary fixtures (the month before, the month of, and the month after the 13th birthday) plus the local-only path with zero network calls; **FR-112's held-state matrix — the single most important suite here**, asserting every protection stays on through `ageOutPending` across relaunch; FR-113 per-capability opt-in independence and durable deferral; FR-114 credential-attach preservation of uid/trips/XP/entitlements; FR-115 notification delivery on both channels and guardian rights live throughout the window; FR-116 guardianship-ended-not-deleted and post-completion denial. §2.4 adversarial verification (both directions) applies to F-71 and F-72: a child escaping protections before completing the gate, and a legitimate aged-out user permanently unable to complete it.

---

*File-touch forecast:* iOS — `Services/AgeGateStore.swift` (FR-110 key + precedence docs), `Services/ChildSessionPostureCoordinator.swift` (`ageOutPending` resolution), `Services/AnalyticsService.swift` (one event), new age-out gate views + view model, `Views/AccountCreation/SignInView.swift` (credential attach entry), `Localizable.strings` ×3, tests. functions — `childAccountCore.ts` (required `expectedAgeOutYear`), `childConsent.ts`, `guardianship.ts`, new `ageOut.ts` (scheduled job + transition callable), `welcomeEmail.ts` (age-out variant), `utils/notifications.ts`, `firestore.rules`. **No `@Model` or `VersionedSchema` changes.**

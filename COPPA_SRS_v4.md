# RoadTrip Royale — COPPA Compliance SRS v4 (Program 3: Consent UX, Egress Boundary & Share Surface)

**Version:** 4.5 — 2026-08-15 (**owner follow-ups on OD-10; OD-14/OD-15 decided.** OD-10 refined to **two** outcomes — adults (including guest adults, who resolve normally under v3 OD-9) keep usernames; children *and* unresolved participants share one neutral positional label. The owner's own suggestion is adopted: `"child-user"` is dropped from the export because captioning a shareable image that way publishes the fact that a minor is present, and one token for both cases removes any state where an adult is captioned as a child. "(You)" decoration retained on the sharer's own row. OD-14 decided (Option A), OD-15 decided (all three channels). Prior header follows.)
**Version:** 4.4 — 2026-08-15 (**owner decisions.** OD-10 **decided** — adults keep their names on the share card, children render `"child-user"` consented or not, unresolved participants get a neutral rank label; FR-100(a) rewritten and FR-102(d) gains an explicit `.inApp`/`.export` strictness parameter rather than a second implementation. OD-11 **closed, no decision needed** — the owner correctly identified that SDK deferral is already built and landed; the question only ever concerned a UI default, which the landed enforcement already settles as off. OD-14 and OD-15 **expanded** with the scenarios, options and failure modes the owner asked for. Requirement text elsewhere unchanged.)
**Version:** 4.3 — 2026-08-15 (**ID move, no requirement text changed.** v4 vacates FR-84…FR-91 / F-40…F-46 entirely and relocates to **FR-100…FR-107 / F-60…F-66**; `COPPA_SRS_AGEOUT.md` moves ahead of it to **FR-110…FR-116 / F-70…F-73**. Rationale: v3's FR-93 work is *already implemented* with `F-42`/`FR-85` in code comments, while v4 existed only on paper — the cheaper move is the one with no code behind it. This dissolves the two-way tag collision rather than managing it, and **releases FR-84…FR-91 / F-40…F-46 back to v3**, which may reclaim them so the in-flight comments need no retag at all. Mapping table in §0.1.)
**Version:** 4.2 — 2026-08-15 (v4.2 folds the v3 session's review of the egress-boundary requirement: **(1)** the render policy is restated as **subject-keyed, never viewer-keyed** — v4.0's "anything *involving* a child subject" was ambiguous on the viewer axis and would have mirrored the FR-93 degradation onto a child's own roster; **(2)** the requirement now mandates reusing v3's `callerIsConsentedChildFamilyPeerOf` rather than defining a second membership predicate.)
**Version:** 4.1 — 2026-08-15 (v4.1 rebases from v3.3 onto **v3.5**: folds §3.1's live implementation status into the Depends column, records the ID-space split, notes the interaction with v3's new FR-92/FR-93, and adopts the v3 session's point that amendments to unbuilt features fold into those features rather than shipping as separate passes. No requirement text changed.)
**Version:** 4.0 — 2026-08-15 (authored against local HEAD `0fc73bc` on `feature/MVPPush`, against `COPPA_SRS_v3.md` v3.3).
**Basis:** owner design session of 2026-08-15 (share-surface PI reduction, egress-boundary framework, visual per-scope consent, re-consent notification, family path sharing), plus the amended-Rule analysis carried forward from v3 §1.
**Precedence:** `COPPA_SRS.md` v2.1 is the frozen base; `COPPA_SRS_v3.md` v3.5 is the active remediation program. Both stay in force **except where this document explicitly amends them** (§5 register). Where three documents conflict, v4 wins over v3 wins over v2.1.
**Program scope:** this document plus `COPPA_SRS_AGEOUT.md` are **one program in two files** — same owner, same execution model, same ID block. AGEOUT is Phase 2 except for its FR-110, which is launch-blocking for a data-capture reason explained there.
**ID space (v4.3 — supersedes the v3.5 ID-SPACE NOTICE's allocation to v4).** The v4 program allocates **FR-100…FR-119**, **F-60…F-79**, and **OD-10…OD-29**. This document defines FR-100…FR-107, F-60…F-66, OD-10…OD-15; AGEOUT defines FR-110…FR-117, F-70…F-74, OD-16…OD-21. **v4 claims nothing below FR-100 / F-60 / OD-10 and has released FR-84…FR-91 and F-40…F-46** — v3 may reclaim that range freely. v3 continues to hold FR-1…FR-99, F-1…F-56, OD-1…OD-9. Neither program allocates into the other's block.
**File ownership.** The v4 session owns `COPPA_SRS_v4.md` and `COPPA_SRS_AGEOUT.md`; the v3 session owns `COPPA_SRS_v3.md`; `COPPA_SRS.md` (v2.1) is frozen. Read freely across all four, write only your own.
**Relationship to v3:** v4 does **not** re-open any v3 wave, and does not re-litigate v3 §5's fifteen re-dispositions or §7's OD-1…OD-9 — all treated as settled owner decisions. Three v4 rows amend v3 requirements (FR-79(d), FR-65, FR-77); since none of their host features are built yet, they **fold into those features when implemented** rather than shipping as separate passes (§5).
**App status:** pre-release, no real users. The CLAUDE.md pre-release rule holds — delete, don't migrate; no compatibility shims; dev testers reinstall.

---

## §0 Why this program exists

Three findings from the 2026-08-15 session, none of which v3 fully covers:

1. **The share surface is a publication path, and it currently carries usernames.** `TripSummaryShareCardView` renders participant display names (`:176-212`, `displayName(for:)` at `:252-259`) and a winner line naming users (`:214-224`). v3's FR-79(d) makes the *child's own* card names-free but leaves the **adult's** card free to publish a child family member's username. COPPA reaches the operator that *enables* publication of a child's PI (§312.2, second collection prong) — and it does not care whose finger tapped share.

2. **There is no single egress boundary.** Redaction decisions are made at each SDK call site (`AnalyticsService`, `AdMobService`, `FirebaseMessagingService`, `RevenueCatEntitlementBridge`, crash reporting) and at each render site. v3 fixes several individually (FR-72, FR-73, FR-78). Nothing structurally prevents the *next* SDK or the *next* render path from shipping unredacted. The owner's stated model — "I am passing them into MY service layer, not theirs; the interface is on OUR side" — is correct and is specified here as a first-class framework (FR-102).

3. **Consent is captured once, as a wall of text, and never re-affirmed.** v3's FR-65 splits consent into scopes but specifies only that the manage-child surface "renders scope state read/write." There is no visual per-scope selection, no per-scope policy link, and no mechanism to re-obtain consent when the practices change — which the amended Rule requires for any material change (§312.5).

**One new collection is introduced deliberately** (FR-101(d), family path sharing). It is the only place in v4 where data that is local today becomes data that leaves the device, and it is gated accordingly.

---

## §0.1 ID mapping (v4.3 move — for anyone holding earlier text)

Requirement content is unchanged throughout; only identifiers moved. If you are reading a v4.0–v4.2 quote, a v3.4/v3.5 cross-reference, or an earlier chat transcript, translate with this table.

| Requirement | v4.0–v4.2 | **v4.3 (current)** | Feature | v4.0–v4.2 | **v4.3** |
|---|---|---|---|---|---|
| Share surface PI reduction | FR-84 | **FR-100** | Share surface | F-40 | **F-60** |
| Route render hardening | FR-85 | **FR-101** | Route hardening | F-41 | **F-61** |
| Egress boundary + identity render | FR-86 | **FR-102** | Egress boundary | F-42 | **F-62** |
| Visual per-scope consent | FR-87 | **FR-103** | Consent UI | F-43 | **F-63** |
| Consent re-affirmation | FR-88 | **FR-104** | Re-affirmation | F-44 | **F-64** |
| Local route retention | FR-89 | **FR-105** | Route retention | F-45 | **F-65** |
| Family path sharing (FROZEN) | FR-90 | **FR-106** | Path sharing | F-46 | **F-66** |
| Standing rule: declare new egress | FR-91 | **FR-107** | — | — | — |

`COPPA_SRS_AGEOUT.md` moved twice and its current IDs are **FR-110…FR-116 / F-70…F-73**: age-out data capture was FR-92 then FR-100, now **FR-110** (feature F-47 → F-60 → **F-70**); the remaining six requirements follow in order. Owner decisions did not move — OD-10…OD-15 here, OD-16…OD-21 in AGEOUT, throughout.

**Why the move.** v3's FR-93 was already being implemented with `F-42`/`FR-85` in its code comments while v4 existed only as specification. Moving the paper is free; retagging deployed code is not. The range is released rather than merely conceded — see the ID-space line above.

---

## §1 Analysis hooks (what in the Rule drives each row)

| Rule hook | v4 requirement |
|---|---|
| §312.2 "collection" prong (b) — *enabling a child to make PI publicly available* | FR-100 (share surface carries no PI, at any age) |
| §312.2 PI — geolocation sufficient to identify street name and city | FR-101 (route render: no basemap on export; endpoint trimming; local retention) |
| §312.5(c)(7) internal-operations exception + its **new disclosure obligation** | FR-102 (declared egress classes per channel), v3 FR-72(e)/NP-2 (the disclosure text itself) |
| §312.5(a) — consent must be obtained **before** collection, and separately for non-integral disclosure | FR-103 (per-scope visual consent), amends v3 FR-65 |
| §312.5 — **material change** in practices requires new consent | FR-104 (scope version vectors + re-affirmation) |
| §312.4(d) — direct notice content and per-purpose clarity | FR-103(c) per-scope policy deep links |
| §312.10 — no indefinite retention, written and published schedule | FR-105 (local-route retention; amends v3 FR-77) |
| §312.6(a)(3) — parental review must reflect data actually held | FR-102(e) (inventory derives from the channel registry, so it cannot drift) |

---

## §2 Execution model

Inherits v3 §2 unchanged: isolated worktrees, serialized landing, deploy-to-dev + diff disclosure before "testable" (D-24), coordinator-run rules suite on a JRE shell (no CI — v2.1 §15.3), owner commits, §2.4 adversarial verification for Critical rows.

**Model policy.** `Opus / high` for FR-102 (framework design) and FR-104 (state machine). `Sonnet` for FR-100, FR-101(a)-(c), FR-103 rendering, FR-105 — all pattern-following against existing surfaces. `Fable / xhigh` for FR-101(d) only if the owner un-freezes it (it widens child-data surface; the v3 §0 freeze rule applies). Doc rows may run on `Haiku`.

**Standing constraints carried forward:** D-16 comply-don't-reposition; D-23 EEA gate; FR-24 two-way rejection indistinguishability for any new child-reachable rejection; `ChildFlagIngestPolicy` server-explicit rules for every new ingest; no `@Model` / `VersionedSchema` changes (all v4 state is Firestore + UserDefaults, except FR-105's local pruning which deletes existing `TripRoutePointEntity` rows without schema change).

---

## §3 Feature roadmap

Gate: **L** = launch-blocking, **FF** = fast-follow, **FROZEN** = specified but must not ship without explicit owner un-freeze.

Depends reflects **v3 §3.1's live status as of 2026-08-14** — confirm against §3.1 before planning, since that table moves.

| ID | Feature | Covers | Risk | Model / effort | Depends (v3 status) | Gate |
|---|---|---|---|---|---|---|
| **F-60** | Share surface PI reduction (all ages) | §0(1) → FR-100 | High | Sonnet + verify | none — **startable now**; folds into v3 F-35 if that lands first | **L** |
| **F-61** | Route render hardening: export prohibition, endpoint trimming, structural gate | §0(1) → FR-101(a)(b)(c) | High | Sonnet | v3 F-31 **✓ landed + deployed** — **startable now** | **L** |
| **F-62** | Egress boundary framework + identity render policy | §0(2) → FR-102 | Critical | **Opus / high** + verify | v3 F-28, F-29 — **not started** | **L** |
| **F-63** | Visual per-scope consent UI + per-scope policy links | §0(3) → FR-103 | High | Sonnet (design settled by FR-103) | v3 F-17, F-21 — **not started**; folds into F-21 | **L** |
| **F-64** | Consent re-affirmation on material change (push + badge + email) | §0(3) → FR-104 | High | **Opus / high** | v3 F-17, F-21, F-29 — **not started** | **L** |
| **F-65** | Local route retention + policy parity | §312.10 → FR-105 | Medium | Sonnet | v3 F-33 — **not started**; folds into F-33 | **L** |
| **F-66** | Family path sharing (adult ↔ adult; child gated) | new feature → FR-101(d), FR-106 | Critical | Fable / xhigh + verify | OD-13 + v3 F-17 — **not started** | **FROZEN** |

**Launch gate =** F-60…F-65. F-66 is specified but frozen under the v3 §0 rule (no feature that widens child-data surface ships on the current consent mechanism).

**Startable immediately:** F-60 and F-61 only. Everything else waits on v3's Wave 2 consent core (F-17/F-21) or Wave 4 SDK postures (F-28/F-29). F-62 is the largest v4 row and its dependency is the reason — building the egress boundary before F-28/F-29 land would mean refactoring their call sites twice.

**Do not re-specify built work.** v3 §3.1 lists thirteen features landed and deployed to `roadtrip-royale-dev-d2652`. In particular v3 F-31/FR-75 (location enforcement) and F-32/FR-76 (server payload allowlist + child location strip) are **live** — v4 builds on them and must not restate them. All of it is uncommitted working-tree state; v3 §3.2's environment notes (Java on `PATH` for rules tests, Swift Testing selecting by type name, pinned simulator OS) apply to v4 work equally.

---

## §4 Requirements (FR-100…FR-107)

### FR-100 (F-60) — The exported share image carries no personal information, at any age

**Amends v3 FR-79(d)** (§5 A-1), which scoped the names-free variant to child sessions only.

- **(a) Adult names stay; everyone else is a neutral player label (OD-10 decided, refined 2026-08-15).** `TripSummaryShareCardView`'s participant rows (`:189-210`) and winner line (`:214-224`) keep rendering names, but through the FR-102(d) `IdentityRenderPolicy` at `.export` strictness rather than through `displayName(for:)` directly. **Two outcomes per participant, decided by subject:**
  - **Server-explicit non-child** ⇒ **username**, exactly as today. Adults — including guest/anonymous adults, who resolve normally under v3 OD-9's account-provenance rule — keep their names, and the winner line keeps naming the winner. That is the point of sharing (owner ruling).
  - **Everything else** — child by any evidence (flag `true`, cached true, ratchet, declared history, consented or not), **and** unresolved / `nil`-held / offline-with-cold-cache ⇒ the same **neutral rank label**, `"Player 2"`.
  **Why children get the neutral label rather than `"child-user"` (owner question, 2026-08-15 — recommendation adopted).** Printing `"child-user"` on an image built for public sharing *publishes the fact that a minor is in this family*. That is not enumerated PI, but it is strictly more information about a child than the neutral alternative, and it makes the artifact more sensitive rather than less. `"Player 2"` publishes less, and collapsing to two outcomes removes the mislabeling failure mode entirely — there is no longer any state in which an adult is captioned as a child. The owner's earlier `"child-user"` ruling is superseded on this surface only; it remains available as a one-string change if the owner prefers the explicit form.
  **The asymmetry is the whole mechanism** and mirrors v2.1 FR-19's asymmetric trust: only a *server-explicit false* earns a username; a missing, cached-only, or held signal never does. A child cannot be published under any resolution failure, and an adult's worst case is a neutral label on one card.
  **On unresolved being rare.** Under v3 OD-9, `.unresolved` is transient-only for accounts with cloud identity, so in practice this branch fires on genuine failure — offline with a cold cache, or a peer doc that never loaded. It is a degraded render, not a normal one, and it is safe by construction rather than by luck.
  **Numbering and the viewer's own row.** Labels are positional within a single card (`"Player 2"` = second-ranked row), never a pseudonym stable across trips — a stable one would itself become an identifier. The sharer's own row keeps the existing `ParticipantDisplayName.decorated` "(You)" treatment layered on whatever token resolves, so a sharer always finds themselves: an adult sees `"Chris (You)"`, a child sees `"Player 1 (You)"`.
  **Consequence for FR-102(d):** the export path is no longer moot. It is the strictest consumer of the render policy, and the policy gains an explicit strictness parameter rather than a second implementation (see FR-102(d)).
  **Open, small:** whether a *child session* may invoke share at all is v3 F-35/M-1's question, not this one. FR-100 defines what the card contains for any sharer; if child sharing is later disallowed, nothing here changes.
- **(b) No route, map, polyline, or coordinate may ever be composed into an exported image.** Standing prohibition, not a toggle. The card has no map today; this pins it so a future "add the route to the card!" change is a spec violation rather than a judgment call. Enforced by a test asserting `TripSummaryShareCardView` transitively references no `MapKit` symbol and no `locationMetadata` key.
- **(c) No location metadata on the exported asset.** `TripSummaryShareImageRenderer.render` produces a `UIImage` with no GPS EXIF today (`ImageRenderer` output carries none). Pin it: a test asserts the rendered image's metadata dictionary contains no `kCGImagePropertyGPSDictionary`, and `TripSummaryShareActivityItemSource` never sets a `LPLinkMetadata` location or passes a `CLLocation`.
- **(d) Sharer's own data only.** The card summarizes the trip the sharer participated in; it must not include another participant's per-discovery detail beyond the aggregate rank/score row from (a). `uniquePlatesSection` is already viewer-scoped (`TripSummaryShareContentBuilder.uniquePlatesFoundByViewer`) — unchanged, pinned by test.
- **(e) Trip name is retained** but the child-flow username guidance of v3 FR-80 extends to trip naming for child sessions: a localized hint that trip names are shareable. No server-side validation (heuristic hardening only; recorded as such).
- **(f) The v3 FR-79(d) child-variant branch is deleted, not extended** — there is **one card**, whose participant rows resolve per-subject through (a). v4.0 achieved single-card by removing all names; OD-10 achieves it by making the *row* posture-aware instead of the *card*. The distinction matters at implementation: there is still exactly one `TripSummaryShareCardView`, one export path, and no `if isChildSession` branch around the whole view — the resolution happens once per participant inside the row builder.

*Accept:* snapshot fixtures covering both (a) outcomes — adult (username) and non-adult (neutral rank label) — across solo / competitive / tied cards, with a child fixture and an unresolved fixture proving they render **identically**; the two existing `#Preview`s updated to include a child participant; a fixture in which **every** participant is unresolved still renders a usable card; winner line names an adult winner and shows the neutral label for a child winner; a child renders a *different* positional label across two trips (no stable pseudonym); the sharer's own row carries the "(You)" decoration in both outcomes; MapKit-reference test; EXIF test; localization ×3 for the player label and the rank/score row; VoiceOver conveys rank, score and the token without implying a name; **adversarial verify** in both directions (a child's handle reachable through any export path under any resolution state; an adult with a healthy server-explicit flag stripped of their name).

### FR-101 (F-61) — The route stays local, stays coarse at the edges, and is gated structurally

- **(a) Structural gate, not a data-presence check.** `TripSummaryView`'s route section currently renders on `summary.locationMetadata != nil && !isEmpty` (`:50-51`) — a data-presence test that renders whatever local rows exist, including rows recorded before an under-13 answer or on a device whose posture later flipped. It gains the v3 FR-75 resolver term: the section renders only when `EffectiveSettingsResolver` resolves route display **on** for the current session. Child-restricted ⇒ no section, regardless of stored rows.
- **(b) Endpoint trimming (all ages, not a COPPA requirement — a safety one).** `TripRouteSummaryBuilder` gains a trim step: drop route points within an **OD-12 radius (proposed 1.5 km)** of the first and last recorded point before simplification, and start/end the drawn polyline at the trimmed boundary. Rationale recorded in the code: a road-trip trail otherwise begins in the family's driveway. Applies to the on-screen render and to any future export equally. Degenerate case (whole trip inside the radius) ⇒ no route section rather than a stub.
- **(c) Local-only invariant, pinned.** `TripRoutePointEntity`'s header already states "local-only, never synced to Firestore, not part of the gameplay event log." A test pins it: no `TripRoutePointEntity` field name appears in any Firestore serialization path, and `TripRoutePointRepository` has no writer outside the local repository layer. This is the invariant the entire "route is not collection" analysis rests on; it deserves a lock rather than a comment.
- **(d) Family path sharing — FROZEN, specified in FR-106.** See below.

*Accept:* resolver-driven render matrix (child signal × stored rows × authorized location); trim test including the degenerate case; local-only grep test; existing route-recap analytics (`recapSectionAnalyticsLoggedSessionId`) carries no coordinate-derived value.

### FR-102 (F-62) — One declared egress boundary for every SDK and outbound interface

The framework the owner specified: redaction happens at *our* interface, before any third-party or network call, and adding a channel without declaring it fails the build's test suite.

- **(a) `PIClass`** — a closed enum naming what may cross a boundary: `.persistentIdentifier`, `.onlineContact`, `.preciseLocation`, `.coarseLocation`, `.userHandle`, `.gameplayContent`, `.purchaseHistory`, `.deviceId`, `.audio`, `.imageOrVideo`, `.freeText`. Derived from the amended §312.2 list so the mapping to the Rule is legible.
- **(b) `EgressChannel` protocol** — every outbound integration conforms:
  ```
  protocol EgressChannel {
      static var channelId: String { get }              // "firebase_analytics", "admob", …
      static var declaredClasses: Set<PIClass> { get }  // the allowlist for this channel
      static func plan(for posture: ChildSessionPosture,
                       scopes: ConsentScopeSet) -> EgressPlan  // .blocked | .redacted(…) | .permitted
  }
  ```
  Registered channels at landing: Firebase Analytics, Crashlytics, Google Mobile Ads, RevenueCat, Firebase Messaging, Firestore gameplay writes, Cloud Function callables, the share-sheet export (FR-100), and Remote Config.
- **(c) `EgressGate`** — the single call point. A channel does not read `ChildSessionPostureCoordinator` itself; it asks the gate, which composes posture (v3 FR-75's structural rule), consent scopes (v3 FR-65), and the channel's declared classes, and returns a plan or a refusal. A refusal is a no-op, never a crash, and never an analytics event (v2.1 §12: nothing may fire only for child sessions).
- **(d) `IdentityRenderPolicy`** — the owner's "don't publish a child's username" rule as one policy instead of N call sites. Resolves a uid to a `DisplayToken`. Every render path that today calls `ParticipantDisplayName.decorated` routes through it — in-app surfaces (rosters, participant rows, recap, push copy) **and** FR-100's export path, at different strictness.
  **Subject-keyed, never viewer-keyed (load-bearing).** The substitution decision is a function of **whose name is being rendered**, never of **who is looking**. Signature is `token(for subject: UserId, viewedBy viewer: UserId)`, and `viewer` participates in exactly one test — whether subject and viewer share a family — never as a property that triggers substitution on its own. Concretely: a child subject rendered to a non-family viewer ⇒ role label (`"Scout"`, `"Player 2"`); a child subject rendered inside their own family ⇒ username (v3 FR-93); **an adult subject rendered to a child viewer ⇒ username, always.** Writing the policy symmetrically — "a child is involved, so substitute" — mirrors the degradation onto the child's own roster, where every adult would render as a role label. That is the same bug FR-93 fixes, pointed the other way. [Reviewer-flagged 2026-08-15 by the v3 session; v4.0's phrasing ("anything *involving* an unresolved or child subject") was genuinely ambiguous on this axis and is replaced, not clarified.]
  **Strictness levels (added v4.4 for OD-10).** The policy takes a `strictness` parameter; there is one implementation, not two.
  - **`.inApp` (default)** — used by rosters, participant rows, recap, push copy. A cached or held signal may still resolve a username inside the family, because FR-93 requires the child's own roster to hydrate and these surfaces never leave the device.
  - **`.export`** — used by FR-100's share card and any future outbound artifact. **Only a server-explicit non-child earns a username; everything else — child evidence of any kind, and any unresolved signal — yields the same neutral positional label.** One token for both cases, deliberately: the export must not disclose *which* reason applied, since "this one is a child" is itself information about a child. This is the FR-19 asymmetric-trust rule applied to publication.
  A caller must pass strictness explicitly — there is no inferred default at the call site — so that adding an export surface is a visible decision rather than an accidental inheritance of in-app leniency. FR-107's standing rule covers the same ground for egress channels.
  **Practical invariant:** because children are never searchable (v2.1 FR-9/11/12) and play family-only trips (D-4), a child viewer's surfaces are entirely in-family — so for a child viewer the policy is a **no-op** in every reachable state. Any test in which a child viewer sees a role label is a failing test, not an edge case.
  **Interaction with v3 FR-93 (consented-child parity) — read before implementing.** The two policies point in opposite directions and must not be conflated. FR-93 is about what a consented child may **read**: they are a full family member, so their roster hydrates with real names and avatars rather than raw uids. `IdentityRenderPolicy` is about how a child is **rendered to others**. Inside the family both resolve to usernames and nothing changes; the policy only substitutes a role label outside the family context. An implementation that applies the role label inside the family would re-create the exact degradation FR-93 exists to fix, so the family-context branch is a pinned test case, not an incidental behavior.
- **(e) Registry-derived, not hand-maintained.** Two derivations, both pinned by test so they cannot drift:
  - v3 FR-61's parental data inventory enumerates the **registry**, so a newly registered channel appears in the parental review automatically.
  - v3 FR-72(e)'s internal-operations position paper is generated from the registry's declared classes and stated purposes — which is exactly what the amended Rule's disclosure obligation asks for.
- **(f) No-unregistered-SDK test.** A test scans the target's imports and SPM product list against the registry and fails on any third-party networking SDK with no registered channel. Grep-shaped and imperfect; recorded as a tripwire, not a proof.
- **(g) Server-side sibling.** Callable responses shape through one `projectForViewer(subject:viewer:)` step before serialization, so a child's handle cannot ride a response body that some future client renders. Applies to roster, search, invite, and recap payloads. Subject-keyed per (d) — the same asymmetry rule governs both sides of the boundary.
- **(h) One definition of "consented family member."** v3 F-48/FR-93 lands the rules helper **`callerIsConsentedChildFamilyPeerOf`**. F-62 **reuses it** for the family-context test in (d) and (g); it MUST NOT define a second membership predicate. Two definitions of the same relationship is how enforcement drifts — one widens, the other does not, and the gap is invisible until it is a finding. If the helper's shape does not fit the render path, extend it in place rather than forking it. [Constraint supplied by the v3 session, 2026-08-15.]
  **Naming hazard — resolved by the v4.3 move, noted for anyone reading older text.** FR-93's in-flight implementation carries pre-renumber code comments reading `F-42` and `FR-85`. Those were ambiguous while v4 also owned `F-42`/`FR-85`; **v4.3 vacated that range**, so those tags are now unambiguous v3 identifiers and need no retag on v4's account. Nothing in the v4 program uses `F-40`…`F-46` or `FR-84`…`FR-91`. If you find one of those tags in code, it belongs to v3 — do not "correct" it toward v4.

*Accept:* posture × scope × channel matrix test; every existing SDK call site refactored to the gate with no behavior change for adults (regression pins from v3 F-28/F-29 stay green); inventory-derives-from-registry parity test; unregistered-SDK tripwire fails on a deliberately added dummy import; **the four-cell identity matrix pinned in both directions** — child subject / non-family viewer ⇒ role label, child subject / family viewer ⇒ username, adult subject / child viewer ⇒ username, adult subject / adult viewer ⇒ username — with the third cell called out as the mirrored-degradation regression lock (shared test case with v3 F-48); `callerIsConsentedChildFamilyPeerOf` is the only membership predicate on the render path (grep); **adversarial verify** both directions (PI crossing a channel that did not declare it; an adult path or a child's own roster degraded by an over-eager gate).

### FR-103 (F-63) — Consent is selected visually, per scope, with the policy text attached to each

**Amends v3 FR-65** (§5 A-2), which specified scope separation server-side but left the surface as "renders scope state read/write."

- **(a) One card per scope**, rendered in the FR-59 consent flow and again in the manage-child surface. Each card carries: scope name in plain language, a one-sentence "what this means" line, what is collected, who sees it, and a **toggle** — not a paragraph with an embedded checkbox.
- **(b) Core vs declinable, honestly labelled.** `core` (`gameplay_sync` + `family_visibility`) renders as **required to join a family**, visibly non-toggleable, with the reason stated — not a pre-checked box that looks optional. `analytics_internal` renders declinable and defaults **off** (see OD-11). Declining is non-punitive and the copy says so.
- **(c) Per-scope policy deep link.** Each card carries a link to the *section* of the Privacy Policy / ToS governing that scope, using the existing tappable-policy-link pattern from v2.1 FR-31 (which survives as the acknowledgment layer under v3 FR-59). Deep-link targets are anchors within the localized policy strings; a test pins that every scope has a resolvable anchor in all three locales.
- **(d) Frozen scopes are visible and disabled**, with a reason line ("not available yet") — `ads_child_directed`, `location_family_shared`, `cross_family_visibility`. Visible-but-disabled is deliberate: it tells a parent what the product may ask for later, and it makes FR-104's re-affirmation legible when one is un-frozen.
- **(e) Grant is per-scope and atomic with the consent row** (v3 FR-64's transaction, extended to carry the scope vector).
- **(f) Accessibility and localization**: each card is one VoiceOver element with label = scope name, value = granted/declined, hint = what changes; Dynamic Type to accessibility sizes without clipping; state never by color alone (icon + text); ×3 locales; consent-text version bumped per OQ-2 discipline.

*Accept:* scope-matrix snapshot tests; per-scope anchor resolution test ×3 locales; declining `analytics_internal` verifiably stops v3 FR-72 collection for that child; core cannot be declined while joining; a11y audit on the flow; the frozen scopes cannot be granted through any client or server path.

### FR-104 (F-64) — Material changes re-open consent, and consented parents are told

- **(a) Version vector per scope.** `CONSENT_SCOPE_VERSIONS: {scopeId: version}` in `childAccountCore.ts`, stamped into the consent row at grant. A scope whose current version exceeds the granted version is **`STALE`**.
- **(b) Effect of stale, fail-closed but not punitive.** A stale **declinable** scope (`analytics_internal`, and any un-frozen scope) suspends its collection until re-affirmed — the child keeps playing, the data flow stops. A stale **core** scope suspends *new* cloud collection while leaving local play and existing data intact (the v2.1 FR-28 restricted-state machinery already models exactly this; reuse it, do not build a second hold). **OD-14** confirms the core-stale behavior.
- **(c) Notification, only to guardians who already consented.** On a version bump, for each child with a GRANTED record whose guardian resolves via v3 FR-62's guardianship doc: a push notification in an existing family category (v3 FR-73 governs token eligibility — the guardian is an adult, so no child-token question arises), an **email** via the `welcomeEmail.ts` send infrastructure, and an in-app badge. Parents with no consent record receive **nothing** — there is nothing for them to re-affirm, and messaging them would be unsolicited contact.
- **(d) The red bubble.** A badge count surfaces on the Family tab and on the affected child's row in the manage-child surface, cleared only by completing the re-affirmation — not by viewing the screen. Uses the existing `FamilyPendingApprovals` sticky-surfacing pattern (v2.1 FR-25's "sticky surfacing" is the precedent; do not invent a second badge mechanism).
- **(e) Re-affirmation reuses FR-103's cards**, showing only the stale scopes, with a diff line ("what changed"). It does **not** re-run FR-59 verification — the guardian is already verified; this is a scope re-acknowledgment, and the consent row records `reaffirmedAt` + the new version vector while preserving the original `verifiedAt` evidence.
- **(f) Version discipline.** The OQ-2 rule (a version string is a date+commit pin or date+slug, bumped in the same commit as the wording change) extends to scope versions. v3 FR-83(e)'s hash-lock test extends: a scope's policy text changing without its version bumping fails tests.

*Accept:* bump-a-scope integration test — consented guardians get push + email + badge, unconsented get nothing, collection for that scope halts until re-affirmed; badge clears only on completion; core-stale leaves local play working; re-affirmation writes the new vector without touching `verifiedAt`; hash-lock test catches an unbumped copy change; localization ×3.

### FR-105 (F-65) — Local route data has a retention bound too

**Amends v3 FR-77** (§5 A-3) by adding a class it does not cover.

Local `TripRoutePointEntity` rows are not collection and carry no COPPA retention duty. They are bounded anyway, because an unbounded on-device location history is a device-loss risk and a stated-practice mismatch waiting to happen:

- Route points for a trip are pruned **OD-12 (proposed 90 days)** after that trip ends, by a local maintenance pass on app launch (reuse the existing repository delete path; `TripRoutePointRepository.deleteAll(tripSessionId:)` exists).
- The trip's derived `locationMetadata` summary is regenerated from points at open time (`TravelLogViewModel:275-276`), so pruning simply retires the route section for old trips — no stale render, no schema change.
- Account deletion and sign-out already clear local stores; pinned by test here rather than assumed.
- The published retention policy (NP-3) states the local window alongside the server windows. Stating a practice you don't implement is the deception exposure; this makes the sentence true.

*Accept:* pruning test with fixtures either side of the window; regeneration test (an old trip opens with no route section and no error); NP-3 ↔ constant parity pinned by the v3 FR-77 test pattern.

### FR-106 (F-66, FROZEN) — Family path sharing

Specified now so the design is not improvised later. **MUST NOT ship** without OD-13 plus the v3 §0 un-freeze (FR-59 landed + counsel review).

- **(a) This is the program's only new collection.** Route points leave the device for the first time. For adults that is ordinary (notice + policy + manifest). For children it is precise-geolocation collection requiring the `location_family_shared` scope under real VPC.
- **(b) Adult ↔ adult, opt-in both ways.** A trip participant's path is visible to other participants only when the sharer has enabled sharing for that trip. Default off. Reuses `participant_prefs` + `EffectiveSettingsResolver`, never a challenge/tournament override (v2.1 FR-45(c) deleted that mechanism deliberately; the standing owner intent is an explicit join-time consent gate, never a silent override).
- **(c) Children: default off, parent-held enable, child may disable.** The child may always turn their own sharing **off** (protective direction, mirroring the self-declaration principle); only the guardian may turn it **on**, via FR-103's scope card. A consented child with the scope off still *sees* other participants' shared paths — receive-only is the cheapest compliant posture and preserves the family-map experience without the child transmitting anything.
- **(d) Uploaded paths are coarse.** FR-101(b) endpoint trimming applies **before** upload; coordinates round to 3 decimals server-side (v3 FR-76's adult rounding path); altitude and accuracy keys rejected. A child actor's coordinates remain stripped server-side per v3 FR-76 unless the scope is granted — the server never trusts the client's posture.
- **(e) Retention:** shared paths age out on v3 FR-77's location-payload schedule (12 months proposed), independent of trip-history retention.
- **(f) Declarations:** `PrivacyInfo.xcprivacy` location classification is re-derived (v3 FR-81 likely coarsens it; this feature may re-earn precise) and NP-2/NP-3 updated. Shipping this without the manifest pass is a false declaration.
- **(g) Never on the share card.** FR-100(b) is unconditional and this feature does not create an exception.

*Accept (when un-frozen):* scope-gated upload matrix; child-off-by-default and child-can-disable pinned; receive-only child verified to transmit nothing; endpoint trim applied pre-upload; server strip for unscoped children; manifest and policy updated in the same change; **adversarial verify** both directions.

### FR-107 (F-62) — Standing rule: new egress requires a declaration

Any change that adds an SDK, a network client, a callable response field, or an export surface **must** register or extend an `EgressChannel` (FR-102(b)) in the same change, and the PR description states the declared classes and why. A change that adds egress without a declaration is a spec violation regardless of whether it happens to be harmless. This is the maintenance rule that keeps FR-102 from decaying into the situation §0(2) describes.

---

## §5 Amendment register (v3 / v2.1 items this document changes)

| # | Existing item | v4 action | Why |
|---|---|---|---|
| A-1 | v3 FR-79(d): child share card is names-free; adult card unchanged | **Extended** → FR-100(a) | The adult card publishes the child's handle. Prong (b) of §312.2 attaches to the operator that built the mechanism, not to the tapper. Unconditional removal also avoids resolving every participant's child flag at render time, which fails open when the signal is `nil`-held. |
| A-2 | v3 FR-65: "the parent manage-child surface renders scope state read/write" | **Extended** → FR-103 | Scope separation without a per-scope surface and per-scope policy text is server-side bookkeeping the parent never sees; §312.4(d) is about what the parent is actually shown. |
| A-3 | v3 FR-77: retention classes cover server data only | **Extended** → FR-105 | Local route history is unbounded today. No COPPA duty, but NP-3 will state a practice, and the statement should be true. |
| A-4 | v2.1 FR-45(b) / v3 FR-76: coordinate rounding is a server concern | **Extended** → FR-101(b) | Rounding reduces precision uniformly; it does not address that the *endpoints* are the sensitive part. Trimming is orthogonal to rounding and applies locally. |
| A-5 | v3 FR-61: inventory is hand-assembled from known locations | **Amended** → FR-102(e) | An inventory maintained in parallel with the code drifts. Deriving it from the channel registry makes new egress appear in parental review automatically. |
| A-6 | v3 §0 freeze list (`location_family_shared` frozen) | **Stands, now specified** → FR-106 | The freeze is unchanged. v4 writes the design so an un-freeze is a decision, not a redesign under time pressure. |

**Folding rule (v4.1, adopted from the v3 session).** A-1, A-2 and A-3 amend v3 features that are **not yet built** (F-35, F-21, F-33 per v3 §3.1). They therefore fold into those features when implemented rather than shipping as separate passes — one change to `TripSummaryShareCardView`, not two. The v4 requirement text governs what gets built; the v3 feature row is where it lands. This does not apply to F-61/F-62/F-64, which are new surfaces with no v3 host.

**v3.5 additions — reviewed, no conflict with v4.** v3 FR-92 (parent-initiated device transfer) and FR-93 (consented-child capability parity) were added after v4.0 was authored. Neither collides: FR-92 is a post-consent share-code flow that v4 does not touch (its interaction with AGEOUT's FR-114 credential collection is recorded there), and FR-93 is a read-side capability restoration whose interaction with FR-102(d) is recorded at that requirement.

Everything in v3 and v2.1 not named here **stands and must not regress** — in particular v3 FR-59/60 (consent core and local-first child), FR-62/63 (guardianship and deletion), FR-72/73 (analytics and push postures), FR-75/76 (location enforcement and server strip), and v2.1's flag architecture, FR-24 oracle closure, D-16, D-17, D-23.

---

## §6 Owner decisions

- **OD-10 — DECIDED 2026-08-15 (owner), refined same day: adults keep their names; every non-adult renders a neutral positional label.** Owner's framing: "showing who won is an important part of sharing" — honoured, adults and the winner line are unchanged from today. The v4.0 blanket-removal recommendation is withdrawn.
  Three sub-questions the owner raised, answered: **(i) guest adults** resolve normally and keep their usernames — under v3 OD-9 a guest has cloud identity, so `"Player 2"` is a genuine-failure branch, not the guest branch. **(ii) `"child-user"` vs `"Player x"` for children** — owner's instinct adopted: the neutral label is better, because captioning a shareable image `"child-user"` publishes the fact that a minor is present, which is more information about a child than the alternative, and collapsing to two outcomes removes any state where an adult is captioned as a child. **(iii) "(You)" on one's own row** — yes, the existing `ParticipantDisplayName.decorated` treatment is layered on whichever token resolves.
  Reversible: `"child-user"` remains a one-string change if the owner later prefers the explicit form. Consent state is deliberately not a factor either way — consent governs collection; publication is a separate act.
- **OD-11 — NO DECISION NEEDED (closed 2026-08-15).** The owner is right that this is already settled elsewhere and the question as written was misleading. Three distinct things were being conflated:
  1. **SDK deferral** — already built and landed (v3 F-16/FR-58, per v3 §3.1). Analytics collection does not start before posture resolution. Not in question, and the owner's recollection that it was built and tested that way is correct.
  2. **Child collection gate** — already specified (v3 FR-72(a)): a child's analytics starts only when consented **and** `analytics_internal` is granted. Not in question.
  3. **What OD-11 actually asked** — whether the consent screen's toggle renders pre-checked or unchecked. That is a UI default, not a collection default.
  Since (2) already requires an affirmative grant before any collection, an unchecked toggle is the only state consistent with the code. A pre-checked box would show "on" while the enforcement holds it off — misleading *and* the pattern the FTC reads worst. **Resolved as unchecked/off**, matching landed behavior; no owner action required.
- **OD-12 (tuning, defaults acceptable): FR-101(b) endpoint trim radius = 1.5 km; FR-105 local route retention = 90 days.**
- **OD-13 (blocks F-66, and F-66 is frozen regardless): family path sharing.** Requires: FR-59 landed, counsel review per v3 OD-1, and an explicit un-freeze. Do not treat FR-106's existence as approval.
- **OD-14 — DECIDED 2026-08-15 (owner): Option A.** Play continues, cloud collection pauses, backlog drains on re-affirmation. Analysis retained below.
- **OD-14 (analysis): what happens to a consented child while a *core* scope is stale.**
  **The scenario.** You change what `gameplay_sync` or `family_visibility` covers — say a new field starts syncing. That is a material change, so §312.5 requires fresh consent, so `CONSENT_SCOPE_VERSIONS` bumps and **every currently-consented child's core scope goes stale at once**. The parent has not done anything wrong; they simply have not re-affirmed yet, and they may not for days. The question is what the child's app does in the meantime.
  **Option A — pause cloud collection, keep playing (recommended).** The child plays normally; finds, XP and progression accrue **locally**; nothing new uploads. A gentle localized notice says a parent needs to approve an update. On re-affirmation the queue drains through v2.1 FR-28c's `resumeGameplaySyncAfterConsent` and the backlog uploads via FR-28h late replay. **This is not new machinery** — it is exactly the pre-consent hold that already exists and already has tests; the trigger is the only new part.
  **Option B — full lockout.** Child cannot play until the parent acts. Compliant, and punishes a child for an adult's inbox habits. Also the version bump is *your* action, not theirs.
  **Option C — banner only, keep collecting.** Not available: that is collection under consent you have declared insufficient.
  **Recommendation: A.** COPPA requires you stop collecting under stale consent; nothing requires you to stop the game. Note the asymmetry with declinable scopes — a stale `analytics_internal` just stops analytics silently, no notice needed, because nothing user-visible degrades.
- **OD-15 — DECIDED 2026-08-15 (owner): all three channels.** Push + in-app badge + email, on the bounded cadence below (fire at bump, one reminder at day 7, then stop). The cheaper badge+push variant is declined. Analysis retained below.
- **OD-15 (analysis): how the parent finds out a re-affirmation is waiting.**
  **Why it matters more than it sounds:** under OD-14(A) the child's uploads are paused while the scope is stale. A parent who never learns has a child whose progress silently stops syncing. The notification is not a courtesy — it is what bounds the degradation.
  **The three channels, and what each fails at.** *Push* — instant, but needs an APNs token the parent may have denied or revoked, and it is the channel most easily dismissed. *In-app badge* (Family tab + the affected child's row, FR-104(d)) — reliable when they open the app, useless if they do not, and the parent may be the least frequent user in the family. *Email* — durable, addressable from `private/contact` for any registered adult, survives a reinstall, and is the only channel that still works when the parent has not opened the app in a month.
  **Recommendation: all three, with a bounded cadence** — fire once at the bump, one reminder at day 7 if unactioned, then stop. No third reminder: past that point it is nagging, and the in-app badge persists anyway until cleared by completion.
  **The cheaper alternative** is badge + push only, dropping email. Acceptable if the owner would rather not send transactional mail on a version bump, but it means a lapsed parent's child can sit un-synced indefinitely with no signal outside the app.

---

## §7 Notice-side dependencies

- **NP-4 — Per-scope policy anchors.** The localized Privacy Policy / ToS strings gain addressable sections per consent scope (FR-103(c)). Ships as a strings change ×3 under the OQ-2 version-stamp discipline, same as v3 NP-2.
- **NP-5 — Retention text gains the local window** (FR-105), stated alongside the server schedule in NP-3.
- **NP-6 — Change-notification practice** stated in the policy: what constitutes a material change, how guardians are told, and what happens to collection while consent is stale (FR-104).

---

## §8 Test-plan deltas

Add to the v2.1 §14 / v3 §10 suites: the FR-100 card snapshots across both identity outcomes, including the child-and-unresolved-render-identically pin, plus the MapKit-reference and EXIF pins; FR-101's resolver matrix and trim tests including the degenerate case; the **FR-102 boundary matrix** (posture × scope × channel) and the unregistered-SDK tripwire, which together replace per-SDK trust with one harness; FR-103's per-scope anchor resolution ×3 locales; FR-104's bump-notify-halt-reaffirm integration test; FR-105's prune-and-regenerate fixtures. §2.4 adversarial verification (both directions) applies to F-60, F-62, and F-66.

---

*v4 file-touch forecast (for worktree planning):* iOS — `Views/Trips/TripSummaryShareCardView.swift`, `TripSummaryShareContentBuilder.swift`, `TripSummaryShareActivityItemSource.swift`, `TripSummaryView.swift`, `Services/TripRouteSummaryBuilder.swift`, `Repositories/TripRoutePointRepository.swift`, `Services/EffectiveSettingsResolver.swift`, `Services/ChildSessionPostureCoordinator.swift`, new `Services/Egress/*` (`PIClass`, `EgressChannel`, `EgressGate`, `IdentityRenderPolicy`, per-channel conformances), `Services/AnalyticsService.swift`, `AdMobService.swift`, `FirebaseMessagingService.swift`, `CrashReportingService.swift`, `RevenueCatEntitlementBridge.swift`, `Core/ParticipantDisplayName.swift`, `Views/Family/FamilyChildPrivacyView.swift`, `Views/Family/FamilyPendingApprovals.swift` + view models, new consent-scope card views, `Localizable.strings` ×3, tests. functions — `childAccountCore.ts` (scope versions), `childConsent.ts`, `guardianship.ts` (v3), `welcomeEmail.ts` (re-affirmation send), `retentionCore.ts`, response-projection helper, `firestore.rules`. **No `@Model` or `VersionedSchema` changes.**

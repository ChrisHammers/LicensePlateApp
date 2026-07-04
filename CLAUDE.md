# RoadTrip Royale

iOS SwiftUI app + Firebase backend. Not yet shipped.
Stack: SwiftUI · SwiftData · Firebase (Auth / Firestore / Cloud Functions) · RevenueCat · Firebase Analytics · AdMob.

This file is the standing contract. It is always true. Step-specific work runs through `/rtr-step`.

## Gameplay architecture (canonical)

The gameplay model is `TripSession` → `GameInstance` → `TripActivityEvent`.

- The legacy `Trip` model was removed. Do not reintroduce it.
- Solo is the one-participant case of multiplayer — not a separate path.
- Gameplay mutations produce append-only `TripActivityEvent`s. Sync operates on events, not mutable trip blobs.
- Views render projections. They do not make rule decisions.
- There is one source of truth for trips, discoveries, progression, entitlements, and users. Never create a parallel one.

## Layering

- **Repositories** — the only layer that touches SwiftData or Firestore; own `ModelContext` usage.
- **Services** — domain logic and rule engines; orchestrate repositories.
- **ViewModels** — UI state only; call repositories and services; never touch SwiftData or Firebase directly.
- **Views** — render only; no business logic, no persistence, no heavy computation in the body.

Prefer extending this architecture over introducing anything parallel.

## Reference paths (read the real code, don't guess)

- Trip recap: `TripSummaryBuilder` + TripSession/GameInstance/TripActivityEvent repos. Reference path: `@TravelLogViewModel.openSummary`.
- Trip lifecycle end hook: `@TripSessionLifecycleService.endTrip()` (canonical).
- Entitlements: `@EntitlementService` + `@RevenueCatEntitlementBridge`. Do not invent parallel tier logic.
- Celebrations: `RewardPresenter` / `UnlockPopup` in `Views/Rank Progression/` already exist.
- Return streak: `@ReturnStreakService` already records — surface it, don't rewrite unless broken.

## SwiftData & schema

- Don't change property wrappers (`@State`, `@StateObject`, `@ObservedObject`, `@EnvironmentObject`, `@Bindable`) unless the step requires it.
- Don't alter relationships, inverses, delete rules, or persistence annotations unless instructed. Never replace a relationship with an ID.
- Preserve `NavigationStack` identity and sheet/`item:` presentation models.
- Do not edit frozen `VersionedSchema` types. Any `@Model` change lands in a new schema version, advancing the versioned-schema tree (swiftdata-versioned-schema rule).

## Cloud writes

- `clientMetadata` is never nested inside gameplay payloads. Cloud writes carry `ClientMetadata.current.firestoreValue` as a sibling field (client-metadata-cloud-calls rule).
- Don't weaken auth, Firestore rules, App Check, entitlement checks, duplicate rules, or competitive integrity.
- Keep offline-first behavior deterministic and idempotent.

## Quality bar for any change

- New UI ships with SwiftUI previews.
- Accessibility: meaningful VoiceOver labels/values/hints, Dynamic Type without clipping, Reduce Motion respected, state never conveyed by color alone, sufficient contrast, minimum touch targets. Preserve light/dark and iPhone/iPad.
- Localization: every user-facing string goes through the localization system in English, Spanish (Latin America, es-419), and French (Canadian, fr-CA). No untranslated production text.
- Analytics: typed events through the existing `AnalyticsService` taxonomy, emitted from ViewModels or services, never from Views. Don't log sensitive values.
- Tests: unit tests for business rules and persistence; focused UI tests for critical flows where practical.
- Haptics/audio where they help — don't overdo it.

## Do not

- Add friends / invite / leaderboard / competitive features beyond what already exists.
- Change monetization (paywall tiers, AdMob eligibility, RevenueCat mapping) unless the step explicitly requires it.
- Redefine gameplay semantics (who sees "found", duplicate rules, multiplayer attribution). Visible meaning must match prior behavior (ui-refactor-parity).
- Refactor working code, or unrelated systems, needlessly. Smallest correct diff wins.
- Create git commits, PRs, or markdown docs unless I ask.

When the repo conflicts with a step, explain the conflict and choose the smallest change that preserves these rules. When uncertain, ask rather than guess.

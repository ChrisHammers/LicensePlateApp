# Deep link vs home sheet presentation

## Problem

Tapping a Friend Invite, Family Invite, Trip Invite (and similar) notification sets `DeepLinkHandler.destination` immediately, but the invite UI is a **RootView**-level `.sheet(item:)`. Settings / Friends / Travel Log / create-trip live as **ContentView**-level sheets.

SwiftUI will not present a parent sheet while a child sheet is already up. The destination stays set, so the invite sheet only appears after the user dismisses the competing sheet — which felt like “deep link doesn’t work until I’m back on home.”

## What we shipped (Option A)

**Dismiss competing home sheets, then present the invite sheet.**

Implemented in `ContentView`:

- On `deepLinkHandler.destination` change, dismiss Settings, Travel Log, create-trip, deferred setup hub, streak explanation, and trip-limit paywall when any of those are up.
- For sheet-based destinations, clear and re-publish `destination` after a short delay so RootView’s `.sheet(item:)` retries after child teardown.
- Trip-session deep links also dismiss those sheets, then navigate via `MainCoordinator` (not a RootView sheet).

Key files:

- `LicensePlateApp/App Shell/ContentView.swift` — dismiss + republish
- `LicensePlateApp/App Shell/RootView.swift` — invite / family / pending sheets
- `LicensePlateApp/Services/DeepLinkHandler.swift` — parse + `@Published destination`

Tradeoff accepted: user loses Settings/Friends context when an invite push is tapped.

---

## Options to revisit

### Option B — Present invite on top of the active sheet

Keep Settings (or whatever modal) open and attach deep-link presentation to the **already-presented** sheet (or a shared host inside it), e.g. nest `.sheet(item: deepLink…)` on `DefaultSettingsView`, or use `fullScreenCover` from the active modal.

**Pros**

- User stays in Settings/Friends while handling the invite.
- No flash of home between sheets.

**Cons**

- Multiple attachment points (Settings, Travel Log, create-trip, deferred hub, paywall, …) — easy to miss one.
- Nested sheet UX and dismiss order get fiddly.
- Trip invite → `PendingTripsView` may not belong inside Settings.

**When to prefer:** invite must appear *over* Settings without dismissing it.

---

### Option C — Overlay window (like rewards / XP toasts)

Host invite UI in a dedicated `UIWindow` above all SwiftUI sheets, same idea as `RewardPopupWindowHost` / `XpGainToastWindowHost`.

**Pros**

- Always on top of any sheet stack.
- Pattern already proven in this app for celebrations.

**Cons**

- Second presentation stack (env objects, auth, dismiss, accessibility focus).
- Heavier than a sheet-handoff fix.
- Risk of diverging from normal navigation chrome.

**When to prefer:** need guaranteed visibility regardless of modal state, and willing to invest in window-host plumbing.

---

### Option D — Route into the Settings navigation stack

When Settings is already open, push Friends/Family invite onto `MainSettingsCoordinator` instead of presenting a new RootView sheet. If Settings is closed, open Settings then push (or keep Option A for that case).

**Pros**

- Aligns with where users already manage invites (Friends hub / Family).
- No competing RootView sheet when already in Settings.

**Cons**

- `MainSettingsCoordinator` is local `@StateObject` on `DefaultSettingsView`, not app-scoped — needs shared presentation state.
- Trip invite → `PendingTripsView` doesn’t fit Settings well; still need a non-Settings path.
- Product meaning of “open invite” shifts from modal detail to in-stack navigation.

**When to prefer:** invite handling should feel like inbox navigation inside Settings, not a global modal.

---

### Option E — Single app-level presentation coordinator

One owner for “active modal”: home sheets + deep-link destinations. Queue or replace presentations so contention is impossible by design.

**Pros**

- Fixes sheet contention systematically (also helps ContentView’s many sibling `.sheet`s).
- Clear place for future deep links / paywalls / hubs.

**Cons**

- Larger refactor than this bug alone.
- Easy to over-engineer; touch many call sites.

**When to prefer:** presentation bugs keep recurring, or you’re already redesigning home/settings modal flow.

---

## Related gotchas (not the sheet bug)

1. **Local** notifications from `NotificationRoutingService` may omit deep-link `userInfo` — tap won’t navigate even on a clear home screen.
2. Trip invite deep link opens **`PendingTripsView`**, not a single-invite detail.
3. `DeepLinkDestination.tripSession` is handled in ContentView via `MainCoordinator`, not RootView’s sheet (binding returns `nil` for that case).
4. RootView’s sheet binding also gates on `rootView == .main` and signed-in user; cold start relies on holding `destination` until ready.

## Suggested revisit order

1. Stay on **A** unless product wants invite *over* Settings.
2. Prefer **B** for “don’t dismiss Settings.”
3. Prefer **C** if overlays are already the team’s go-to for “above everything.”
4. Prefer **D** only with a product decision to treat invites as Settings-stack destinations.
5. Prefer **E** when paying down modal architecture debt intentionally.

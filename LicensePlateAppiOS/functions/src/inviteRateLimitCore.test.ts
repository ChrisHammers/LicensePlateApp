/**
 * FR-47 (COPPA F-10) — the rate-limit window rule, in isolation.
 *
 * The callable wiring is pinned in `inviteHardening.test.ts`; this file covers the decision
 * function itself, including the malformed/skewed inputs that must fail OPEN (start a fresh
 * window) rather than locking a user out of inviting.
 */

import { describe, it, expect } from "vitest";
import {
  FRIEND_INVITE_MAX_PER_WINDOW,
  INVITE_RATE_LIMIT_WINDOW_MS,
  TRIP_INVITE_MAX_PER_WINDOW,
  evaluateInviteRateLimit,
  inviteRateLimitDocId,
  inviteRateLimitDocIdsForUser,
  readInviteRateLimitWindow,
} from "./inviteRateLimitCore";

const NOW = 1_700_000_000_000;
const LIMIT = 3;

describe("evaluateInviteRateLimit: opening a window", () => {
  it("starts a fresh window when there is no counter yet", () => {
    expect(evaluateInviteRateLimit(null, NOW, LIMIT)).toEqual({
      allowed: true,
      next: { windowStartAtMs: NOW, count: 1 },
      retryAfterMs: 0,
    });
  });

  it("increments within a live window without moving its start", () => {
    const decision = evaluateInviteRateLimit(
      { windowStartAtMs: NOW, count: 1 },
      NOW + 60_000,
      LIMIT
    );
    expect(decision).toEqual({
      allowed: true,
      next: { windowStartAtMs: NOW, count: 2 },
      retryAfterMs: 0,
    });
  });

  it("allows exactly `limit` sends before refusing", () => {
    let window = { windowStartAtMs: NOW, count: 0 };
    for (let i = 0; i < LIMIT; i += 1) {
      const decision = evaluateInviteRateLimit(window, NOW, LIMIT);
      expect(decision.allowed).toBe(true);
      window = decision.next;
    }
    expect(window.count).toBe(LIMIT);
    expect(evaluateInviteRateLimit(window, NOW, LIMIT).allowed).toBe(false);
  });
});

describe("evaluateInviteRateLimit: refusing and recovering", () => {
  it("refuses at the limit and reports the time left in the window", () => {
    const decision = evaluateInviteRateLimit(
      { windowStartAtMs: NOW, count: LIMIT },
      NOW + 10_000,
      LIMIT
    );
    expect(decision.allowed).toBe(false);
    expect(decision.retryAfterMs).toBe(INVITE_RATE_LIMIT_WINDOW_MS - 10_000);
  });

  it("leaves the stored window untouched when refusing (a refusal costs nothing)", () => {
    const current = { windowStartAtMs: NOW, count: LIMIT };
    expect(evaluateInviteRateLimit(current, NOW + 1, LIMIT).next).toEqual(current);
  });

  it("restarts once the window has fully elapsed", () => {
    const decision = evaluateInviteRateLimit(
      { windowStartAtMs: NOW, count: LIMIT },
      NOW + INVITE_RATE_LIMIT_WINDOW_MS,
      LIMIT
    );
    expect(decision).toEqual({
      allowed: true,
      next: { windowStartAtMs: NOW + INVITE_RATE_LIMIT_WINDOW_MS, count: 1 },
      retryAfterMs: 0,
    });
  });

  it("is still refusing one millisecond before the window lapses", () => {
    expect(
      evaluateInviteRateLimit(
        { windowStartAtMs: NOW, count: LIMIT },
        NOW + INVITE_RATE_LIMIT_WINDOW_MS - 1,
        LIMIT
      ).allowed
    ).toBe(false);
  });
});

describe("evaluateInviteRateLimit: hostile and degenerate input", () => {
  it("restarts rather than blocking when the stored start is in the future (clock skew)", () => {
    const decision = evaluateInviteRateLimit(
      { windowStartAtMs: NOW + 5_000_000, count: 99 },
      NOW,
      LIMIT
    );
    expect(decision.allowed).toBe(true);
    expect(decision.next).toEqual({ windowStartAtMs: NOW, count: 1 });
  });

  it("treats a non-positive limit as closed", () => {
    expect(evaluateInviteRateLimit(null, NOW, 0).allowed).toBe(false);
  });
});

describe("readInviteRateLimitWindow: a corrupt counter must not lock anyone out", () => {
  it("reads a well-formed doc", () => {
    expect(readInviteRateLimitWindow({ windowStartAtMs: NOW, count: 4 })).toEqual({
      windowStartAtMs: NOW,
      count: 4,
    });
  });

  it("returns null for missing, mistyped, non-finite or negative values", () => {
    const bad: (Record<string, unknown> | undefined)[] = [
      undefined,
      {},
      { windowStartAtMs: "nope", count: 1 },
      { windowStartAtMs: NOW, count: "nope" },
      { windowStartAtMs: Number.NaN, count: 1 },
      { windowStartAtMs: NOW, count: Number.POSITIVE_INFINITY },
      { windowStartAtMs: NOW, count: -1 },
    ];
    for (const data of bad) {
      expect(readInviteRateLimitWindow(data)).toBeNull();
    }
  });

  it("a null read means the next call opens a fresh window, not a refusal", () => {
    expect(evaluateInviteRateLimit(readInviteRateLimitWindow({}), NOW, LIMIT).allowed).toBe(
      true
    );
  });
});

describe("counter doc ids", () => {
  it("separates the two scopes for the same user", () => {
    expect(inviteRateLimitDocId("trip_invite", "u1")).not.toBe(
      inviteRateLimitDocId("friend_invite", "u1")
    );
  });

  it("enumerates every id a user can own, for deletion residue cleanup (FR-50)", () => {
    const ids = inviteRateLimitDocIdsForUser("u1");
    expect(ids).toHaveLength(2);
    expect(ids).toContain(inviteRateLimitDocId("trip_invite", "u1"));
    expect(ids).toContain(inviteRateLimitDocId("friend_invite", "u1"));
  });
});

describe("configured limits", () => {
  it("are positive and finite (a zero would close invites entirely)", () => {
    for (const limit of [TRIP_INVITE_MAX_PER_WINDOW, FRIEND_INVITE_MAX_PER_WINDOW]) {
      expect(Number.isInteger(limit)).toBe(true);
      expect(limit).toBeGreaterThan(0);
    }
  });
});

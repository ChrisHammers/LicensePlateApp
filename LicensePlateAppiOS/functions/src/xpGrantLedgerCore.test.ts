import { describe, it, expect } from "vitest";
import {
  activityEventGrantReason,
  activityEventXpGrantId,
  buildXpGrantDocument,
  legacyUnledgeredGrantId,
  XP_GRANT_REASON,
} from "./xpGrantLedgerCore";
import { KIND_GAME_ENDED } from "./progressionCore";
import { KIND_REGION_FOUND } from "./gameplayEventResolver";

describe("xpGrantLedgerCore", () => {
  it("builds stable activity grant ids", () => {
    expect(activityEventXpGrantId("u1", "evt-1")).toBe("activity|evt-1|u1");
  });

  it("maps activity kinds to grant reasons", () => {
    expect(activityEventGrantReason(KIND_REGION_FOUND)).toBe(
      XP_GRANT_REASON.REGION_FOUND
    );
    expect(activityEventGrantReason(KIND_GAME_ENDED)).toBe(
      XP_GRANT_REASON.COMPETITIVE_WIN
    );
  });

  it("builds grant documents with required fields", () => {
    const doc = buildXpGrantDocument({
      grantId: "activity|evt-1|u1",
      amount: 10,
      reason: XP_GRANT_REASON.REGION_FOUND,
      sourceType: "activity_event",
      sourceId: "evt-1",
      idempotencyKey: "evt-1",
      sessionId: "trip-1",
    });
    expect(doc.grantId).toBe("activity|evt-1|u1");
    expect(doc.amount).toBe(10);
    expect(doc.reason).toBe(XP_GRANT_REASON.REGION_FOUND);
    expect(doc.sessionId).toBe("trip-1");
  });

  it("uses a stable legacy grant id", () => {
    expect(legacyUnledgeredGrantId()).toBe("legacy_unledgered_balance|v1");
  });

  it("includes return streak daily grant reason", () => {
    const doc = buildXpGrantDocument({
      grantId: "return_streak_daily|v1|u1|2026-07-11",
      amount: 5,
      reason: XP_GRANT_REASON.RETURN_STREAK_DAILY,
      sourceType: "return_streak",
      sourceId: "2026-07-11",
      idempotencyKey: "return_streak_daily|v1|u1|2026-07-11",
    });
    expect(doc.reason).toBe("return_streak_daily");
    expect(doc.sourceType).toBe("return_streak");
  });
});


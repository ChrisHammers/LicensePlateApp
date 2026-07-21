import { describe, it, expect } from "vitest";
import {
  buildPlateFoundNotificationCopy,
  classifyPlateFoundRelationship,
  coalesceFlushCountForRecipients,
  mergePlateFoundBuffer,
  pushCategoryForRelationship,
} from "./plateFoundNotifyCore";

describe("classifyPlateFoundRelationship", () => {
  it("marks collaborative peers as co-pilots", () => {
    expect(
      classifyPlateFoundRelationship({
        gameMode: "collaborative",
        actorId: "a",
        recipientId: "b",
        teams: [],
      })
    ).toBe("co_pilot");
  });

  it("marks same-team competitive peers as co-pilots", () => {
    expect(
      classifyPlateFoundRelationship({
        gameMode: "competitive",
        actorId: "a",
        recipientId: "b",
        teams: [{ id: "t1", participantUserIds: ["a", "b"] }],
      })
    ).toBe("co_pilot");
  });

  it("marks other-team or unteamed competitive peers as opponents", () => {
    expect(
      classifyPlateFoundRelationship({
        gameMode: "competitive",
        actorId: "a",
        recipientId: "b",
        teams: [
          { id: "t1", participantUserIds: ["a"] },
          { id: "t2", participantUserIds: ["b"] },
        ],
      })
    ).toBe("opponent");

    expect(
      classifyPlateFoundRelationship({
        gameMode: "competitive",
        actorId: "a",
        recipientId: "b",
        teams: [],
      })
    ).toBe("opponent");
  });
});

describe("pushCategoryForRelationship", () => {
  it("maps relationship to prefs category", () => {
    expect(pushCategoryForRelationship("opponent")).toBe("plateFoundByOpponent");
    expect(pushCategoryForRelationship("co_pilot")).toBe("plateFoundByCoPilots");
  });
});

describe("buildPlateFoundNotificationCopy", () => {
  it("uses single-find copy", () => {
    expect(
      buildPlateFoundNotificationCopy({
        tripName: "Beach Run",
        pending: [{ regionId: "CA", actorId: "a", actorDisplayName: "Alex", atMs: 1 }],
      })
    ).toEqual({ title: "Plate found", body: "Alex found CA" });
  });

  it("uses multi-find coalesce copy", () => {
    expect(
      buildPlateFoundNotificationCopy({
        tripName: "Beach Run",
        pending: [
          { regionId: "CA", actorId: "a", atMs: 1 },
          { regionId: "NV", actorId: "b", atMs: 2 },
        ],
      })
    ).toEqual({ title: "Plates found", body: "2 plates found on Beach Run" });
  });
});

describe("mergePlateFoundBuffer", () => {
  it("schedules flush only on first item in window", () => {
    const first = mergePlateFoundBuffer({
      existingPending: [],
      existingFlushAtMs: null,
      nowMs: 1_000,
      item: { regionId: "CA", actorId: "a", atMs: 1_000 },
      coalesceMs: 90_000,
    });
    expect(first.shouldScheduleFlush).toBe(true);
    expect(first.flushAtMs).toBe(91_000);
    expect(first.pending).toHaveLength(1);

    const second = mergePlateFoundBuffer({
      existingPending: first.pending,
      existingFlushAtMs: first.flushAtMs,
      nowMs: 5_000,
      item: { regionId: "NV", actorId: "b", atMs: 5_000 },
      coalesceMs: 90_000,
    });
    expect(second.shouldScheduleFlush).toBe(false);
    expect(second.flushAtMs).toBe(91_000);
    expect(second.pending).toHaveLength(2);
  });
});

describe("coalesceFlushCountForRecipients", () => {
  it("5 others seeing 10 plates each is 5 notifications not 50", () => {
    const recipients = ["r1", "r2", "r3", "r4", "r5"];
    const actors = ["a1", "a2", "a3", "a4", "a5"];
    expect(
      coalesceFlushCountForRecipients({
        recipientIds: recipients,
        actorIds: actors,
        findsPerActor: 10,
      })
    ).toBe(5);
  });
});

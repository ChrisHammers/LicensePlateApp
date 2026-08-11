/**
 * FR-38 (+ FR-13 / FR-24 trip cases) — family-only trips for children.
 *
 * The matrix below is the full both-directions set §14 asks for: child as target, child as
 * sender, non-family user pulled into a child-containing trip, cross-family mixing,
 * unconsented children, and the accept-path re-verification against a roster that changed
 * after the invite was sent.
 */

import { describe, it, expect, beforeEach } from "vitest";
import type * as admin from "firebase-admin";
import { FakeFirestore } from "./testSupport/fakeFirestore";
import { evaluateTripChildParticipation } from "./tripChildParticipation";

function asFirestore(db: FakeFirestore): admin.firestore.Firestore {
  return db as unknown as admin.firestore.Firestore;
}

let db: FakeFirestore;

/**
 * fam1 = parent + kid + sibling. fam2 = otherparent + otherkid. `stranger` is unattached.
 * `s1` is a trip owned by `parent`.
 */
beforeEach(() => {
  db = new FakeFirestore();

  db.seed("users/parent", { userName: "Parent", activeFamilyId: "fam1" });
  db.seed("users/sibling", { userName: "Sib", activeFamilyId: "fam1" });
  db.seed("users/kid", {
    userName: "Kid",
    isChildAccount: true,
    activeFamilyId: "fam1",
  });
  db.seed("families/fam1/members/parent", { role: "creator" });
  db.seed("families/fam1/members/sibling", { role: "scout" });
  db.seed("families/fam1/members/kid", { role: "scout", isChild: true });

  db.seed("users/otherparent", { userName: "OP", activeFamilyId: "fam2" });
  db.seed("users/otherkid", {
    userName: "OK",
    isChildAccount: true,
    activeFamilyId: "fam2",
  });
  db.seed("families/fam2/members/otherparent", { role: "creator" });
  db.seed("families/fam2/members/otherkid", { role: "scout", isChild: true });

  db.seed("users/stranger", { userName: "Stranger" });
  db.seed("users/lonekid", { userName: "Lone", isChildAccount: true }); // no family

  db.seed("trip_sessions/s1", { name: "Trip", createdBy: "parent" });
  db.seed("trip_sessions/s1/members/parent", { role: "owner" });
});

function send(joiningUserId: string, senderId: string) {
  return evaluateTripChildParticipation(asFirestore(db), {
    tripSessionId: "s1",
    joiningUserId,
    additionalParticipantIds: [senderId],
  });
}

function accept(joiningUserId: string) {
  return evaluateTripChildParticipation(asFirestore(db), {
    tripSessionId: "s1",
    joiningUserId,
  });
}

describe("FR-38: child as invite target", () => {
  it("allows a family member inviting the child", async () => {
    await expect(send("kid", "parent")).resolves.toBeNull();
  });

  it("rejects a stranger inviting the child, as a non-disclosing child_joiner", async () => {
    db.seed("trip_sessions/s1/members/stranger", { role: "member" });
    await expect(send("kid", "stranger")).resolves.toEqual({
      kind: "child_joiner",
      childUserId: "kid",
    });
  });

  it("rejects even a family sender when a NON-family participant is already aboard", async () => {
    db.seed("trip_sessions/s1/members/stranger", { role: "member" });
    await expect(send("kid", "parent")).resolves.toEqual({
      kind: "child_joiner",
      childUserId: "kid",
    });
  });

  it("rejects a child from another family's trip roster (cross-family mixing)", async () => {
    db.seed("trip_sessions/s1/members/otherparent", { role: "member" });
    await expect(send("kid", "parent")).resolves.toEqual({
      kind: "child_joiner",
      childUserId: "kid",
    });
  });

  it("rejects an UNCONSENTED child target — no family means no shared trip", async () => {
    await expect(send("lonekid", "parent")).resolves.toEqual({
      kind: "child_joiner",
      childUserId: "lonekid",
    });
  });
});

describe("FR-38: the other direction — inviting into a child-containing trip", () => {
  beforeEach(() => {
    db.seed("trip_sessions/s1/members/kid", { role: "member" });
  });

  it("allows another member of the child's family", async () => {
    await expect(send("sibling", "parent")).resolves.toBeNull();
  });

  it("rejects a non-family user, naming the existing child participant", async () => {
    await expect(send("stranger", "parent")).resolves.toEqual({
      kind: "child_participant",
      childUserId: "kid",
    });
  });

  it("rejects a child of a DIFFERENT family (each child's rule fails)", async () => {
    const rejection = await send("otherkid", "parent");
    // The joiner is evaluated first so the caller can pick the non-disclosing message.
    expect(rejection).toEqual({ kind: "child_joiner", childUserId: "otherkid" });
  });
});

describe("FR-24: child as the sender", () => {
  beforeEach(() => {
    db.seed("trip_sessions/s1/members/kid", { role: "member" });
  });

  it("allows a child inviting their own family member", async () => {
    await expect(send("sibling", "kid")).resolves.toBeNull();
  });

  it("rejects a child inviting anyone outside their family", async () => {
    await expect(send("stranger", "kid")).resolves.toEqual({
      kind: "child_participant",
      childUserId: "kid",
    });
  });

  it("rejects an unconsented child sender outright", async () => {
    db.seed("trip_sessions/s2", { name: "Solo", createdBy: "lonekid" });
    const rejection = await evaluateTripChildParticipation(asFirestore(db), {
      tripSessionId: "s2",
      joiningUserId: "sibling",
      additionalParticipantIds: ["lonekid"],
    });
    expect(rejection).toEqual({ kind: "child_participant", childUserId: "lonekid" });
  });
});

describe("FR-38: accept-path re-verification", () => {
  it("passes when the roster is still all-family", async () => {
    db.seed("trip_sessions/s1/members/kid", { role: "member" });
    await expect(accept("sibling")).resolves.toBeNull();
  });

  it("rejects when a child joined the trip AFTER the invite was sent", async () => {
    // stranger was legitimately invited to an adults-only trip; a child then joined.
    db.seed("trip_sessions/s1/members/kid", { role: "member" });
    await expect(accept("stranger")).resolves.toEqual({
      kind: "child_participant",
      childUserId: "kid",
    });
  });

  it("rejects when the child's family membership ended between send and accept", async () => {
    db.seed("trip_sessions/s1/members/sibling", { role: "member" });
    db.store.delete("families/fam1/members/sibling");
    await expect(accept("kid")).resolves.toEqual({
      kind: "child_joiner",
      childUserId: "kid",
    });
  });

  it("rejects when the joiner was flagged as a child between send and accept", async () => {
    db.seed("users/stranger", { userName: "Stranger", isChildAccount: true });
    await expect(accept("stranger")).resolves.toEqual({
      kind: "child_joiner",
      childUserId: "stranger",
    });
  });
});

describe("FR-38: adults-only trips are unaffected", () => {
  it("returns null with no family lookups needed", async () => {
    db.seed("trip_sessions/s1/members/stranger", { role: "member" });
    await expect(send("otherparent", "parent")).resolves.toBeNull();
  });

  it("treats a missing user doc as an adult", async () => {
    await expect(send("ghost", "parent")).resolves.toBeNull();
  });

  it("permits a solo child session (nobody to be exposed to)", async () => {
    db.seed("trip_sessions/s3", { name: "Solo", createdBy: "lonekid" });
    await expect(
      evaluateTripChildParticipation(asFirestore(db), {
        tripSessionId: "s3",
        joiningUserId: "lonekid",
      })
    ).resolves.toBeNull();
  });
});

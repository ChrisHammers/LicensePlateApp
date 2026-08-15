/**
 * FR-68 — `publishTripCanonicalState` / `ensureOwnerMemberIfCreatorPayload` ownership hardening.
 *
 * THE DEFECT: `ensureOwnerMemberIfCreatorPayload` trusted the CLIENT-SUPPLIED
 * `session.createdBy` field. If it equalled the caller's uid and no `members/{uid}` doc
 * existed yet, it installed the caller as `owner` — without ever checking whether the trip
 * session document already existed under a DIFFERENT creator. Combined with `assertTripOwner`
 * (which only checks the member doc this function just wrote) and the later rewrite of the
 * stored `createdBy` from the same untrusted payload, anyone who merely learned an existing
 * `tripSessionId` — a past participant, a removed/kicked participant (`members/{uid}` is
 * deleted on kick — see `runOwnerRemoveParticipantTransaction`), or a trip-invite recipient
 * (`trip_invites` is party-readable and carries `tripSessionId`) — could self-install as
 * owner of someone else's trip and then cement the takeover by rewriting `createdBy`.
 *
 * THE FIX mirrors the sibling `ensureOwnerMemberIfTripDocCreatedByMatches` (used by
 * `appendTripActivityEvent`), which already reads `createdBy` from the STORED document. A
 * caller may self-install as owner only when there is no stored session yet (genuine first
 * publish) or the stored `createdBy` already matches them (idempotent republish / the
 * documented creator-before-invite race). Otherwise the callable refuses with the same
 * `permission-denied` "Not a member of this trip session" a genuine outsider gets elsewhere
 * in this file, so the refusal does not itself disclose "this trip already has an owner".
 */

import { describe, it, expect, beforeEach, vi } from "vitest";

const holder = vi.hoisted(() => ({ db: undefined as any }));

vi.mock("firebase-admin", async () => {
  const { FakeFirestore } = await import("./testSupport/fakeFirestore");
  holder.db = new FakeFirestore();
  const firestore: any = () => holder.db;
  firestore.FieldValue = {
    serverTimestamp: () => "__serverTimestamp__",
    delete: () => "__delete__",
    increment: (n: number) => n,
  };
  firestore.Timestamp = {
    fromMillis: (ms: number) => ({ toMillis: () => ms }),
    fromDate: (date: Date) => ({ toMillis: () => date.getTime() }),
  };
  return { default: { firestore }, firestore };
});

import type { FakeFirestore } from "./testSupport/fakeFirestore";
import { publishTripCanonicalState } from "./tripSessionCanonical";

function db(): FakeFirestore {
  return holder.db as FakeFirestore;
}

type Runnable = { run: (data: unknown, context: unknown) => Promise<unknown> };

function context(uid: string): unknown {
  return { auth: { uid, token: { firebase: { sign_in_provider: "password" } } } };
}

const CREATED_AT = 1_700_000_000;

/** Minimal valid `publishTripCanonicalState` payload; `games` defaults to empty. */
function publish(
  tripSessionId: string,
  sessionOverrides: Record<string, unknown>,
  uid: string,
  games: unknown[] = []
) {
  return (publishTripCanonicalState as unknown as Runnable).run(
    {
      tripSessionId,
      session: { id: tripSessionId, createdAt: CREATED_AT, ...sessionOverrides },
      games,
    },
    context(uid)
  );
}

const NOT_A_MEMBER = {
  code: "permission-denied",
  message: "Not a member of this trip session",
};

beforeEach(() => {
  db().store.clear();
  db().writeCount = 0;
});

// ---------------------------------------------------------------------------
// The attack: a known tripSessionId is not enough to seize an existing trip
// ---------------------------------------------------------------------------

describe("FR-68: publishTripCanonicalState cannot be used to seize an existing trip", () => {
  function seedVictimTrip() {
    db().seed("trip_sessions/victim-trip", { name: "Family Trip", createdBy: "victim" });
    db().seed("trip_sessions/victim-trip/members/victim", { role: "owner" });
  }

  it("(1) an attacker with a known sessionId cannot become owner of someone else's session", async () => {
    seedVictimTrip();

    await expect(
      publish("victim-trip", { createdBy: "attacker", name: "Family Trip", status: "active" }, "attacker")
    ).rejects.toMatchObject(NOT_A_MEMBER);

    // No member row was installed for the attacker...
    expect(db().store.get("trip_sessions/victim-trip/members/attacker")).toBeUndefined();
    // ...and the real owner's membership is untouched.
    expect(db().store.get("trip_sessions/victim-trip/members/victim")).toMatchObject({
      role: "owner",
    });
  });

  it("(2) a rejected takeover attempt does not rewrite the stored createdBy", async () => {
    seedVictimTrip();

    await publish("victim-trip", { createdBy: "attacker" }, "attacker").catch(() => {});

    expect(db().store.get("trip_sessions/victim-trip")).toMatchObject({
      createdBy: "victim",
    });
  });

  it("a former participant (member doc deleted on kick, per gameplayEventResolver.ts) cannot claim ownership either", async () => {
    // Same reachable state as a kicked/removed participant: no members/{uid} doc, but the
    // tripSessionId is still known to them.
    seedVictimTrip();

    await expect(
      publish("victim-trip", { createdBy: "ex-participant" }, "ex-participant")
    ).rejects.toMatchObject(NOT_A_MEMBER);
    expect(db().store.get("trip_sessions/victim-trip/members/ex-participant")).toBeUndefined();
  });

  it("a trip-invite recipient who never joined cannot claim ownership from the invite's tripSessionId alone", async () => {
    seedVictimTrip();
    // The recipient has a party-readable trip_invites row naming this tripSessionId, but was
    // never added to members/.
    db().seed("trip_invites/inv1", {
      tripSessionId: "victim-trip",
      fromUserId: "victim",
      toUserId: "invite-recipient",
      status: "pending",
    });

    await expect(
      publish("victim-trip", { createdBy: "invite-recipient" }, "invite-recipient")
    ).rejects.toMatchObject(NOT_A_MEMBER);
    expect(db().store.get("trip_sessions/victim-trip/members/invite-recipient")).toBeUndefined();
  });

  it("the refusal is byte-identical to the ordinary non-member rejection (no owner-seizure oracle)", async () => {
    seedVictimTrip();
    const err = await publish("victim-trip", { createdBy: "attacker" }, "attacker").catch((e) => e);
    expect(err.code).toBe(NOT_A_MEMBER.code);
    expect(err.message).toBe(NOT_A_MEMBER.message);
  });

  it("a legitimate non-owner member cannot use a forged createdBy to escalate to owner", async () => {
    // Already covered by the pre-existing member-doc-exists guard; pinned here so the new
    // stored-createdBy check cannot regress it. A real member calling publish with a lying
    // payload must get the ordinary "Only the Driver" rejection, not silently become owner.
    seedVictimTrip();
    db().seed("trip_sessions/victim-trip/members/plusone", { role: "member" });

    await expect(
      publish("victim-trip", { createdBy: "plusone" }, "plusone")
    ).rejects.toMatchObject({
      code: "permission-denied",
      message: "Only the Driver can publish canonical state",
    });
    expect(db().store.get("trip_sessions/victim-trip/members/plusone")).toMatchObject({
      role: "member",
    });
  });
});

// ---------------------------------------------------------------------------
// The happy path must survive: genuine creators still get to publish
// ---------------------------------------------------------------------------

describe("FR-68: legitimate creator flows still work", () => {
  it("(3) a genuine first publish (no stored session yet) installs the creator as owner", async () => {
    const result = (await publish(
      "fresh-trip",
      { createdBy: "creator", name: "Fresh Trip", status: "active" },
      "creator"
    )) as { success: true; syncVersion: number };

    expect(result.success).toBe(true);
    expect(db().store.get("trip_sessions/fresh-trip/members/creator")).toMatchObject({
      role: "owner",
    });
    expect(db().store.get("trip_sessions/fresh-trip")).toMatchObject({
      createdBy: "creator",
    });
  });

  it("(4) an idempotent republish by the same creator still succeeds", async () => {
    const session = { createdBy: "creator", name: "Fresh Trip", status: "active" };
    await expect(publish("fresh-trip", session, "creator")).resolves.toMatchObject({
      success: true,
    });

    // Offline-first client retry / second sync (e.g. adding games) by the true owner.
    await expect(
      publish("fresh-trip", { ...session, name: "Fresh Trip (renamed)" }, "creator")
    ).resolves.toMatchObject({ success: true });

    expect(db().store.get("trip_sessions/fresh-trip/members/creator")).toMatchObject({
      role: "owner",
    });
    expect(db().store.get("trip_sessions/fresh-trip")).toMatchObject({
      createdBy: "creator",
      name: "Fresh Trip (renamed)",
    });
  });

  it("tolerates the documented creator-before-invite race: publish runs before sendTripInvite seeds members/{owner}", async () => {
    // First publish for a brand-new id: no stored session exists yet, so this is the
    // genuine-first-publish case, not a takeover.
    await publish("raced-trip", { createdBy: "creator" }, "creator");
    expect(db().store.get("trip_sessions/raced-trip/members/creator")).toMatchObject({
      role: "owner",
    });

    // A later republish by the SAME creator (now stored createdBy === caller, AND the member
    // doc already exists) must still succeed.
    await expect(
      publish("raced-trip", { createdBy: "creator" }, "creator")
    ).resolves.toMatchObject({ success: true });
  });

  it("repairs a missing owner member row when the stored createdBy already matches the caller", async () => {
    // Mirrors what the sibling `ensureOwnerMemberIfTripDocCreatedByMatches` repairs on the
    // appendTripActivityEvent path: the session doc exists with createdBy correctly set (e.g.
    // written by sendTripInvite), but members/{owner} was not seeded yet.
    db().seed("trip_sessions/half-seeded", { name: "Half Seeded", createdBy: "creator" });

    await expect(
      publish("half-seeded", { createdBy: "creator" }, "creator")
    ).resolves.toMatchObject({ success: true });

    expect(db().store.get("trip_sessions/half-seeded/members/creator")).toMatchObject({
      role: "owner",
    });
  });
});

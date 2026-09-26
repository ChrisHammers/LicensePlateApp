/**
 * §3.1.1 item 19 — `memberUserId` on `trip_sessions/{id}/members/{uid}`.
 *
 * The field exists for one reason: `members/{uid}` is the membership authority, and Firestore
 * cannot query by document id across a collection group, so a trip could never follow an
 * account to its owner's second device. Writing the doc's own id into the doc makes
 * `collectionGroup("members").where("memberUserId","==",uid)` possible.
 *
 * What this file pins:
 *  1. the shared helper's shape — one place composes a member doc, so the writers cannot drift;
 *  2. all FOUR create sites stamp it (publish-by-creator, the append-race repair, the invite
 *     sender's owner seed, and the invite accept), including that a republish keeps it;
 *  3. the de-identification TOMBSTONE row does NOT carry it. That row's id is an unsalted
 *     sha256 prefix of a DELETED user's uid; putting it in a collection-group-indexed field
 *     would make a deterministic function of an erased uid queryable database-wide, and an
 *     absent field is already correct for a "must equal my uid" query. This assertion is the
 *     one that must fail if someone "simplifies" the tombstone to reuse the helper;
 *  4. deletion / FR-61 inventory discovery reaches a session known ONLY through the member
 *     field — so what the user can now SEE can never exceed what deletion can reach;
 *  5. departure still deletes the whole member row, so discovery self-heals with no extra
 *     machinery;
 *  6. no FIFTH create site can appear silently — a source scan, because 2. names its sites by
 *     hand and therefore cannot fail for code nobody has written yet.
 */

import { describe, it, expect, beforeEach, vi } from "vitest";
import { readFileSync, readdirSync } from "node:fs";
import { resolve } from "node:path";

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
    fromMillis: (ms: number) => ({
      toMillis: () => ms,
      seconds: Math.floor(ms / 1000),
      nanoseconds: 0,
    }),
    fromDate: (date: Date) => ({
      toMillis: () => date.getTime(),
      seconds: Math.floor(date.getTime() / 1000),
      nanoseconds: 0,
    }),
    now: () => ({ toMillis: () => 1_800_000_000_000, seconds: 1_800_000_000, nanoseconds: 0 }),
  };
  firestore.FieldPath = { documentId: () => "__documentId__" };
  return { default: { firestore }, firestore };
});

import type { FakeFirestore } from "./testSupport/fakeFirestore";
import {
  TRIP_MEMBER_USER_ID_FIELD,
  removeParticipantFromLiveTripRoster,
  tripMemberDocFields,
} from "./tripRosterWrites";
import { appendTripActivityEvent, publishTripCanonicalState } from "./tripSessionCanonical";
import { respondToTripInvite, sendTripInvite } from "./tripInvites";
import {
  deidentifyUserResidue,
  discoverAffectedSessionIds,
} from "./accountDeletionDeidentify";
import { deletedUserTombstoneIdFor } from "./accountDeletionDeidentifyCore";
import { friendshipEdgeId } from "./inviteRelationshipGate";

function db(): FakeFirestore {
  return holder.db as FakeFirestore;
}

type Runnable = { run: (data: unknown, context: unknown) => Promise<unknown> };

function context(uid: string): unknown {
  return { auth: { uid, token: { firebase: { sign_in_provider: "password" } } } };
}

const CREATED_AT = 1_700_000_000;

function publish(tripSessionId: string, session: Record<string, unknown>, uid: string) {
  return (publishTripCanonicalState as unknown as Runnable).run(
    {
      tripSessionId,
      session: { id: tripSessionId, createdAt: CREATED_AT, status: "active", ...session },
      games: [],
    },
    context(uid)
  );
}

function memberDoc(sessionId: string, uid: string): Record<string, unknown> | undefined {
  return db().store.get(`trip_sessions/${sessionId}/members/${uid}`);
}

beforeEach(() => {
  db().store.clear();
  db().writeCount = 0;
});

// ---------------------------------------------------------------------------
// 1. The shared helper
// ---------------------------------------------------------------------------

describe("tripMemberDocFields: one place composes a member doc", () => {
  it("stamps the member's own uid for an owner row", () => {
    expect(tripMemberDocFields({ userId: "u1", role: "owner" })).toEqual({
      role: "owner",
      joinedAt: "__serverTimestamp__",
      memberUserId: "u1",
    });
  });

  it("stamps the member's own uid for a member row", () => {
    expect(tripMemberDocFields({ userId: "u2", role: "member" })).toEqual({
      role: "member",
      joinedAt: "__serverTimestamp__",
      memberUserId: "u2",
    });
  });

  it("adds exactly one field to the pre-item-19 shape", () => {
    expect(Object.keys(tripMemberDocFields({ userId: "u1", role: "owner" })).sort()).toEqual([
      "joinedAt",
      "memberUserId",
      "role",
    ]);
    expect(TRIP_MEMBER_USER_ID_FIELD).toBe("memberUserId");
  });
});

// ---------------------------------------------------------------------------
// 2. All four create sites
// ---------------------------------------------------------------------------

describe("every path that creates a member doc stamps memberUserId", () => {
  it("site 1/4 — publishTripCanonicalState by the creator (first publish)", async () => {
    await publish("s-pub", { createdBy: "creator", name: "Trip" }, "creator");

    expect(memberDoc("s-pub", "creator")).toMatchObject({
      role: "owner",
      memberUserId: "creator",
    });
  });

  it("site 1/4 — a republish is idempotent and never drops the field", async () => {
    await publish("s-pub", { createdBy: "creator", name: "Trip" }, "creator");
    await publish("s-pub", { createdBy: "creator", name: "Trip v2" }, "creator");

    expect(memberDoc("s-pub", "creator")).toMatchObject({ memberUserId: "creator" });
  });

  it("site 2/4 — the append-race repair (session doc exists, member row missing)", async () => {
    // What `ensureOwnerMemberIfTripDocCreatedByMatches` repairs: sendTripInvite (or a partial
    // sync) wrote the parent doc with `createdBy`, but members/{owner} was never seeded.
    db().seed("trip_sessions/s-race", {
      name: "Raced",
      createdBy: "creator",
      canonicalStatus: "active",
    });

    await (appendTripActivityEvent as unknown as Runnable).run(
      {
        tripSessionId: "s-race",
        event: {
          id: "ev-1",
          sessionId: "s-race",
          kind: "trip_started",
          timestamp: CREATED_AT,
          actorId: "creator",
        },
      },
      context("creator")
    );

    expect(memberDoc("s-race", "creator")).toMatchObject({
      role: "owner",
      memberUserId: "creator",
    });
  });

  it("site 3/4 — the invite sender's owner seed when the first invite creates the trip", async () => {
    db().seed("users/sender", { userName: "Sender" });
    db().seed("users/target", { userName: "Target" });
    db().seed(`friends/${friendshipEdgeId("sender", "target")}`, {
      userA: "sender",
      userB: "target",
      status: "accepted",
    });

    await (sendTripInvite as unknown as Runnable).run(
      { tripSessionId: "s-invite", tripName: "Fresh", toUserId: "target" },
      context("sender")
    );

    expect(memberDoc("s-invite", "sender")).toMatchObject({
      role: "owner",
      memberUserId: "sender",
    });
  });

  it("site 4/4 — respondToTripInvite accept (a plain set, no merge, so the field must be in the payload)", async () => {
    db().seed("users/owner", { userName: "Owner" });
    db().seed("users/joiner", { userName: "Joiner" });
    db().seed("trip_sessions/s-join", { name: "Trip", createdBy: "owner" });
    db().seed("trip_sessions/s-join/members/owner", {
      role: "owner",
      memberUserId: "owner",
    });
    db().seed("trip_invites/inv-1", {
      tripSessionId: "s-join",
      tripName: "Trip",
      fromUserId: "owner",
      toUserId: "joiner",
      status: "pending",
    });

    await (respondToTripInvite as unknown as Runnable).run(
      { inviteId: "inv-1", response: "accept" },
      context("joiner")
    );

    expect(memberDoc("s-join", "joiner")).toMatchObject({
      role: "member",
      memberUserId: "joiner",
    });
    // And the trip is now reachable by the joiner's own account-scoped query.
    expect(
      db().docPathsMatching(
        (path, data) => path.endsWith("/members/joiner") && data.memberUserId === "joiner"
      )
    ).toEqual(["trip_sessions/s-join/members/joiner"]);
  });
});

// ---------------------------------------------------------------------------
// 3. The tombstone must stay unstamped (privacy pin)
// ---------------------------------------------------------------------------

describe("de-identification tombstone rows carry NO memberUserId", () => {
  const DELETED = "uid_deleted_0000000000000000";
  const OTHER = "uid_other_00000000000000000";
  const TOMBSTONE = deletedUserTombstoneIdFor(DELETED);

  beforeEach(() => {
    db().seed("trip_sessions/s1", {
      name: "Shared trip",
      createdBy: OTHER,
      canonicalStatus: "ended",
      canonicalParticipants: [
        { userId: OTHER, role: "owner" },
        { userId: DELETED, role: "member" },
      ],
    });
    db().seed(`trip_sessions/s1/members/${OTHER}`, { role: "owner", memberUserId: OTHER });
    db().seed(`trip_sessions/s1/members/${DELETED}`, {
      role: "member",
      memberUserId: DELETED,
    });
  });

  it("deletes the real member row and writes a tombstone without the field", async () => {
    await deidentifyUserResidue(db() as never, DELETED);

    expect(db().store.get(`trip_sessions/s1/members/${DELETED}`)).toBeUndefined();

    const tombstone = db().store.get(`trip_sessions/s1/members/${TOMBSTONE}`);
    expect(tombstone).toMatchObject({ role: "member", tombstone: true });
    expect(tombstone).not.toHaveProperty(TRIP_MEMBER_USER_ID_FIELD);
  });

  it("leaves no document anywhere carrying the deleted uid in the indexed field", async () => {
    await deidentifyUserResidue(db() as never, DELETED);

    expect(
      db().docPathsMatching((_path, data) => data[TRIP_MEMBER_USER_ID_FIELD] === DELETED)
    ).toEqual([]);
    // And the tombstone id is not queryable either — it is a document id and nothing more.
    expect(
      db().docPathsMatching((_path, data) => data[TRIP_MEMBER_USER_ID_FIELD] === TOMBSTONE)
    ).toEqual([]);
  });
});

// ---------------------------------------------------------------------------
// 4. Deletion / FR-61 inventory coverage cannot lag what the user can see
// ---------------------------------------------------------------------------

describe("discoverAffectedSessionIds reaches a session known only through membership", () => {
  const USER = "uid_member_only";

  it("finds a trip whose ONLY signal is the member doc's memberUserId", async () => {
    // No activity_events, no participant_prefs, no createdBy/canonicalEndedBy, no invite:
    // before item 19 this session was invisible to deletion and to FR-61 review, while the
    // user could now see it in their travel log.
    db().seed("trip_sessions/hidden", { name: "Hidden", createdBy: "someone_else" });
    db().seed(`trip_sessions/hidden/members/${USER}`, {
      role: "member",
      memberUserId: USER,
    });

    expect(await discoverAffectedSessionIds(db() as never, USER)).toEqual(["hidden"]);
  });

  it("never mistakes a family member doc for a trip session, even if one carries the field", async () => {
    // Defence in depth: the field name makes this collision impossible by convention, the
    // query filter makes it impossible in practice, and the path guard makes it impossible
    // structurally. If a familyId ever reached this list it would be swept as a trip.
    db().seed(`families/fam1/members/${USER}`, { role: "scout", memberUserId: USER });

    expect(await discoverAffectedSessionIds(db() as never, USER)).toEqual([]);
  });
});

// ---------------------------------------------------------------------------
// 5. Departure self-heals: the whole row goes, so discovery drops the trip
// ---------------------------------------------------------------------------

describe("leaving a roster removes the row discovery keys off", () => {
  it("removeParticipantFromLiveTripRoster deletes the member doc outright", async () => {
    db().seed("trip_sessions/s-live", {
      name: "Live",
      createdBy: "owner",
      canonicalStatus: "active",
      canonicalParticipants: [
        { userId: "owner", role: "owner" },
        { userId: "leaver", role: "member" },
      ],
    });
    db().seed("trip_sessions/s-live/members/owner", { role: "owner", memberUserId: "owner" });
    db().seed("trip_sessions/s-live/members/leaver", {
      role: "member",
      memberUserId: "leaver",
    });

    const removed = await removeParticipantFromLiveTripRoster(db() as never, {
      tripSessionId: "s-live",
      userId: "leaver",
      leaveReason: "kicked",
      eventId: "left-1",
    });

    expect(removed).toBe(true);
    expect(memberDoc("s-live", "leaver")).toBeUndefined();
    expect(
      db().docPathsMatching((_path, data) => data[TRIP_MEMBER_USER_ID_FIELD] === "leaver")
    ).toEqual([]);
  });
});

// ---------------------------------------------------------------------------
// 6. A FIFTH create site cannot appear silently (source scan)
// ---------------------------------------------------------------------------

/**
 * Section 2 names its four sites by hand, so it can only fail for a site that already exists.
 * Nothing repairs an existing unstamped row — the self-scoped backfill callable that used to
 * was deleted on the owner's word (2026-09-21: the app is not released, old trips do not
 * matter, the dev rows were stamped by a one-off) — so a fifth writer that composes the member
 * doc inline would be a permanent, silent data defect: `batch.set(memberRef, { role, joinedAt })`
 * compiles, type-checks (the payload is `Record<string, unknown>`) and passes every other test.
 *
 * This scan is the part that fails for code nobody has written yet: in non-test source, every
 * `set` / `create` / `update` aimed at a `trip_sessions/{id}/members/{uid}` document must hand
 * its payload to `tripMemberDocFields`. It understands the two write forms the codebase uses —
 * `ref.set(…)` and `batch.set(ref, …)` / `tx.set(ref, …)` — and ignores reads and deletes, which
 * carry no fields. `families/{id}/members/{uid}` is a different collection and is skipped.
 *
 * The de-identification TOMBSTONE is the one deliberate unstamped member row (section 3 pins
 * it). It is written through a `PendingWrite` object rather than either form above, so it does
 * not reach this scan today; if it is ever rewritten as a direct `set`, it needs an exception
 * here AND the reason recorded, not a quiet deletion of this test.
 *
 * A site that invents a third indirection has to teach the scan about it. That is the point,
 * and the second assertion is what keeps it honest: it pins the writes the scan finds today,
 * so a regex that quietly stops matching fails here instead of passing for ever.
 */
interface MemberDocWrite {
  file: string;
  ref: string;
  verb: string;
  stamped: boolean;
}

/** `families/{id}/members/{uid}` — a different collection, a different meaning. */
function isFamilyReceiver(expression: string): boolean {
  return /famil/i.test(expression.slice(-40));
}

/** The write's own statement — bounded at the next `;` so a neighbour cannot vouch for it. */
function statementAt(source: string, index: number): string {
  const end = source.indexOf(";", index);
  return source.slice(index, end === -1 ? source.length : end);
}

function scanMemberDocWrites(file: string, source: string): MemberDocWrite[] {
  const writes: MemberDocWrite[] = [];

  // `x.collection("members").doc(y).set(…)` — a write with no ref variable in between.
  const inlineWrite =
    /([^=;]*?)\.collection\(\s*"members"\s*\)\s*\.doc\([^()]*\)\s*\.(set|create|update)\(/g;
  for (let m = inlineWrite.exec(source); m; m = inlineWrite.exec(source)) {
    if (isFamilyReceiver(m[1])) continue;
    writes.push({
      file,
      ref: "(inline)",
      verb: m[2],
      stamped: statementAt(source, m.index).includes("tripMemberDocFields"),
    });
  }

  // `const memberRef = <trip session ref>.collection("members").doc(uid)` — then find the
  // writes aimed at that name anywhere in the file.
  const refDeclaration =
    /(?:const|let)\s+(\w+)\s*=\s*(?:await\s+)?([^=;]*?)\.collection\(\s*"members"\s*\)\s*\.doc\(/g;
  const names = new Set<string>();
  for (let m = refDeclaration.exec(source); m; m = refDeclaration.exec(source)) {
    if (!isFamilyReceiver(m[2])) names.add(m[1]);
  }

  for (const name of names) {
    const patterns = [
      new RegExp(`\\b${name}\\.(set|create|update)\\(`, "g"),
      new RegExp(`\\b(?:batch|tx|transaction)\\.(set|create|update)\\(\\s*${name}\\s*,`, "g"),
    ];
    for (const pattern of patterns) {
      for (let w = pattern.exec(source); w; w = pattern.exec(source)) {
        writes.push({
          file,
          ref: name,
          verb: w[1],
          stamped: statementAt(source, w.index).includes("tripMemberDocFields"),
        });
      }
    }
  }

  return writes;
}

function allMemberDocWrites(): MemberDocWrite[] {
  return readdirSync(__dirname)
    .filter((name) => name.endsWith(".ts") && !name.endsWith(".test.ts"))
    .sort()
    .flatMap((name) => scanMemberDocWrites(name, readFileSync(resolve(__dirname, name), "utf8")));
}

describe("no fifth create site can write a member doc without the stamp", () => {
  it("every trip member-doc write in non-test source goes through tripMemberDocFields", () => {
    const unstamped = allMemberDocWrites()
      .filter((write) => !write.stamped)
      .map((write) => `${write.file}: ${write.ref}.${write.verb}(…) does not use tripMemberDocFields`);

    expect(unstamped).toEqual([]);
  });

  it("the scan still sees the writes it exists to watch, so it cannot pass vacuously", () => {
    expect(
      allMemberDocWrites()
        .map((write) => `${write.file}:${write.ref}.${write.verb}`)
        .sort()
    ).toEqual([
      "tripInvites.ts:memberRef.set",
      "tripInvites.ts:ownerMemberRef.set",
      "tripSessionCanonical.ts:memberRef.set",
      "tripSessionCanonical.ts:memberRef.set",
    ]);
  });
});

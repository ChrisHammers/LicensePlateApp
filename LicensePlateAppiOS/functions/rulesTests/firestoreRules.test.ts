/**
 * Firestore security-rules matrix — COPPA F-5a (§14 rules section, F-5a subset).
 *
 * Covers the rules changes this feature lands:
 *  - FR-7  user-doc diff-guard: no client write may change `isChildAccount` or
 *          `entitlementTags` (update diff-guard + create key-guard);
 *  - FR-8  family member docs are client write:false (the `isChild` projection can
 *          never be flipped without an audit trail);
 *  - FR-16(b)/G-6  a `pending` join-request create must name its own author
 *          (`userId == request.auth.uid`) — forgery denial;
 *  - FR-28 unconsented-child gates on the client-writable social surfaces
 *          (friends, share_codes) + pin that every gameplay collection remains
 *          client write:false for everyone;
 *  - audit_logs stay fully client-inaccessible, even to the row's subject.
 *
 * RUNNING: needs the Firestore emulator (Java). From `functions/`:
 *     npm run test:rules
 * which wraps `firebase emulators:exec --only firestore --project demo-rtr-rules`.
 * With an emulator already running, set FIRESTORE_EMULATOR_HOST and run
 *     npx vitest run --config vitest.rules.config.ts
 */

import { beforeAll, afterAll, beforeEach, describe, it } from "vitest";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  type RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  setDoc,
  updateDoc,
  type Firestore,
} from "firebase/firestore";

const PROJECT_ID = "demo-rtr-rules";
const RULES_PATH = resolve(__dirname, "..", "..", "firestore.rules");

function emulatorHostPort(): { host: string; port: number } {
  const raw = process.env.FIRESTORE_EMULATOR_HOST ?? "127.0.0.1:8080";
  const [host, port] = raw.split(":");
  return { host, port: Number(port) };
}

let testEnv: RulesTestEnvironment;

// `@firebase/rules-unit-testing` bundles its own `@firebase/firestore` typings, which are
// structurally identical to (but nominally distinct from) the top-level `firebase` package
// types. Cast once at this boundary so every test reads naturally.
/** Registered (non-anonymous) caller. */
function registered(uid: string): Firestore {
  return testEnv
    .authenticatedContext(uid, {
      firebase: { sign_in_provider: "password" },
    })
    .firestore() as unknown as Firestore;
}

/** Anonymous Firebase caller. */
function anonymous(uid: string): Firestore {
  return testEnv
    .authenticatedContext(uid, {
      firebase: { sign_in_provider: "anonymous" },
    })
    .firestore() as unknown as Firestore;
}

async function seed(fixtures: Record<string, Record<string, unknown>>): Promise<void> {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore() as unknown as Firestore;
    for (const [path, data] of Object.entries(fixtures)) {
      await setDoc(doc(db, path), data);
    }
  });
}

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: readFileSync(RULES_PATH, "utf8"),
      ...emulatorHostPort(),
    },
  });
});

afterAll(async () => {
  await testEnv?.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
});

// ---------------------------------------------------------------------------
// FR-7 — users/{uid} server-controlled field guard
// ---------------------------------------------------------------------------

describe("FR-7: users diff-guard protects isChildAccount and entitlementTags", () => {
  beforeEach(async () => {
    await seed({
      "users/kid": { userName: "Kid", isChildAccount: true, activeFamilyId: "fam1" },
      "users/adult": { userName: "Grown", entitlementTags: ["family_plus"] },
    });
  });

  it("denies the owner clearing their own child flag", async () => {
    await assertFails(
      updateDoc(doc(registered("kid"), "users/kid"), { isChildAccount: false })
    );
  });

  it("denies the owner setting the child flag (server writes only)", async () => {
    await assertFails(
      updateDoc(doc(registered("adult"), "users/adult"), { isChildAccount: true })
    );
  });

  it("denies removing the flag via full set (affectedKeys catches deletes)", async () => {
    await assertFails(
      setDoc(doc(registered("kid"), "users/kid"), { userName: "Kid v2" })
    );
  });

  it("still denies entitlementTags changes (regression)", async () => {
    await assertFails(
      updateDoc(doc(registered("adult"), "users/adult"), { entitlementTags: [] })
    );
  });

  it("allows a benign profile update that leaves both fields untouched", async () => {
    await assertSucceeds(
      updateDoc(doc(registered("kid"), "users/kid"), { userName: "Kid v2" })
    );
  });

  it("denies creates that smuggle either server-controlled key in", async () => {
    await assertFails(
      setDoc(doc(registered("fresh1"), "users/fresh1"), {
        userName: "F1",
        isChildAccount: false,
      })
    );
    await assertFails(
      setDoc(doc(registered("fresh2"), "users/fresh2"), {
        userName: "F2",
        entitlementTags: ["family_plus"],
      })
    );
    await assertSucceeds(
      setDoc(doc(registered("fresh3"), "users/fresh3"), { userName: "F3" })
    );
  });
});

// ---------------------------------------------------------------------------
// FR-8 — member docs are client write:false
// ---------------------------------------------------------------------------

describe("FR-8: family member docs reject every client write", () => {
  beforeEach(async () => {
    await seed({
      "families/fam1": { name: "Fam", creatorId: "creator", status: "active" },
      "families/fam1/members/creator": { role: "creator" },
      "families/fam1/members/kid": { role: "scout", isChild: true },
    });
  });

  it("denies even the creator creating, updating, or deleting member docs", async () => {
    const db = registered("creator");
    await assertFails(
      setDoc(doc(db, "families/fam1/members/newguy"), { role: "scout" })
    );
    await assertFails(
      updateDoc(doc(db, "families/fam1/members/kid"), { isChild: false })
    );
    await assertFails(deleteDoc(doc(db, "families/fam1/members/kid")));
  });

  it("denies the member flipping their own isChild projection", async () => {
    await assertFails(
      updateDoc(doc(registered("kid"), "families/fam1/members/kid"), {
        isChild: false,
      })
    );
  });

  it("family members can still read member docs (regression)", async () => {
    await assertSucceeds(
      getDoc(doc(registered("kid"), "families/fam1/members/creator"))
    );
    await assertFails(
      getDoc(doc(registered("outsider"), "families/fam1/members/kid"))
    );
  });
});

// ---------------------------------------------------------------------------
// FR-16(b) / G-6 — pending join-request forgery denial
// ---------------------------------------------------------------------------

describe("G-6: pending join requests must name their own author", () => {
  beforeEach(async () => {
    await seed({
      "families/fam1": { name: "Fam", creatorId: "creator", status: "active" },
      "families/fam1/members/creator": { role: "creator" },
    });
  });

  it("allows a registered user creating a request for themselves", async () => {
    await assertSucceeds(
      setDoc(doc(collection(registered("joiner"), "families/fam1/pending")), {
        userId: "joiner",
        status: "pending",
      })
    );
  });

  it("denies a forged request naming another uid", async () => {
    await assertFails(
      setDoc(doc(collection(registered("stranger"), "families/fam1/pending")), {
        userId: "victim-child",
        status: "pending",
      })
    );
  });

  it("denies a request with no userId at all", async () => {
    await assertFails(
      setDoc(doc(collection(registered("stranger"), "families/fam1/pending")), {
        status: "pending",
      })
    );
  });

  it("denies anonymous callers even for their own uid", async () => {
    await assertFails(
      setDoc(doc(collection(anonymous("anon1"), "families/fam1/pending")), {
        userId: "anon1",
        status: "pending",
      })
    );
  });
});

// ---------------------------------------------------------------------------
// FR-28 — unconsented-child gates on client-writable social surfaces
// ---------------------------------------------------------------------------

describe("FR-28: unconsented children cannot write friends or share_codes", () => {
  beforeEach(async () => {
    await seed({
      // Unconsented: flag true, no activeFamilyId.
      "users/lonekid": { userName: "LoneKid", isChildAccount: true },
      // Consented: flag true with an active family.
      "users/famkid": { userName: "FamKid", isChildAccount: true, activeFamilyId: "fam1" },
      "users/adult": { userName: "Grown" },
      "share_codes/ownedByLonekid": {
        type: "friend",
        createdBy: "lonekid",
        isRevoked: false,
      },
      "friends/edge1": { userA: "lonekid", userB: "adult", status: "pending" },
    });
  });

  it("denies an unconsented child creating a friend edge", async () => {
    await assertFails(
      setDoc(doc(registered("lonekid"), "friends/newEdge"), {
        userA: "lonekid",
        userB: "adult",
        status: "pending",
      })
    );
  });

  it("denies an unconsented child updating a friend edge", async () => {
    await assertFails(
      updateDoc(doc(registered("lonekid"), "friends/edge1"), { status: "accepted" })
    );
  });

  it("denies an unconsented child creating or updating share codes", async () => {
    await assertFails(
      setDoc(doc(registered("lonekid"), "share_codes/newCode"), {
        type: "friend",
        createdBy: "lonekid",
        isRevoked: false,
      })
    );
    await assertFails(
      updateDoc(doc(registered("lonekid"), "share_codes/ownedByLonekid"), {
        isRevoked: true,
      })
    );
  });

  it("adults keep both surfaces (regression), even with no users doc at all", async () => {
    await assertSucceeds(
      setDoc(doc(registered("adult"), "friends/adultEdge"), {
        userA: "adult",
        userB: "lonekid",
        status: "pending",
      })
    );
    await assertSucceeds(
      setDoc(doc(registered("adult"), "share_codes/adultCode"), {
        type: "friend",
        createdBy: "adult",
        isRevoked: false,
      })
    );
    // Registered caller with no users/{uid} doc: the guard must not error-deny.
    await assertSucceeds(
      setDoc(doc(registered("docless"), "share_codes/doclessCode"), {
        type: "friend",
        createdBy: "docless",
        isRevoked: false,
      })
    );
  });

  it("a consented child passes the rules gate (stricter callable gates land in F-5b)", async () => {
    await assertSucceeds(
      setDoc(doc(registered("famkid"), "share_codes/famkidCode"), {
        type: "friend",
        createdBy: "famkid",
        isRevoked: false,
      })
    );
  });
});

// ---------------------------------------------------------------------------
// FR-28 enumeration pin — gameplay collections stay client write:false
// ---------------------------------------------------------------------------

describe("FR-28 pin: gameplay collections reject client writes for everyone", () => {
  beforeEach(async () => {
    await seed({
      "users/lonekid": { userName: "LoneKid", isChildAccount: true },
      "trip_sessions/s1": { name: "Trip", createdBy: "adult" },
      "trip_sessions/s1/members/adult": { role: "owner" },
      "trip_sessions/s1/members/lonekid": { role: "member" },
    });
  });

  const gameplayWrites: Array<[string, string, Record<string, unknown>]> = [
    ["trip_sessions", "trip_sessions/new1", { name: "X", createdBy: "SELF" }],
    [
      "activity_events",
      "trip_sessions/s1/activity_events/e1",
      { kind: "plate_found", actorId: "SELF" },
    ],
    ["games", "trip_sessions/s1/games/g1", { definitionId: "license_plate" }],
    [
      "participant_prefs",
      "trip_sessions/s1/participant_prefs/SELF",
      { userId: "SELF" },
    ],
    [
      "fairness_ack_watermarks",
      "trip_sessions/s1/games/g1/fairness_ack_watermarks/SELF",
      { lastAckAt: 1 },
    ],
    ["user_progression", "user_progression/SELF", { totalXp: 999999 }],
    [
      "user_achievements",
      "user_achievements/SELF/achievements/a1",
      { unlocked: true },
    ],
    ["public_lifetime_stats", "public_lifetime_stats/SELF", { platesFound: 1 }],
  ];

  for (const uid of ["lonekid", "adult"]) {
    for (const [label, pathTemplate, dataTemplate] of gameplayWrites) {
      it(`${label}: client write denied for ${uid}`, async () => {
        const path = pathTemplate.replace(/SELF/g, uid);
        const data = JSON.parse(
          JSON.stringify(dataTemplate).replace(/SELF/g, uid)
        ) as Record<string, unknown>;
        await assertFails(setDoc(doc(registered(uid), path), data));
      });
    }
  }
});

// ---------------------------------------------------------------------------
// audit_logs — fully client-inaccessible
// ---------------------------------------------------------------------------

describe("audit_logs stay fully client-inaccessible", () => {
  beforeEach(async () => {
    await seed({
      "audit_logs/row1": {
        eventType: "AUDIT_PARENTAL_CONSENT_GRANTED",
        actorId: "parent",
        subjectType: "user",
        subjectId: "kid",
        metadata: { familyId: "fam1", childUserId: "kid" },
      },
    });
  });

  it("denies reads even to the subject and the actor", async () => {
    await assertFails(getDoc(doc(registered("kid"), "audit_logs/row1")));
    await assertFails(getDoc(doc(registered("parent"), "audit_logs/row1")));
  });

  it("denies create, update, and delete", async () => {
    await assertFails(
      setDoc(doc(registered("parent"), "audit_logs/forged"), {
        eventType: "AUDIT_PARENTAL_CONSENT_GRANTED",
        subjectId: "kid",
      })
    );
    await assertFails(
      updateDoc(doc(registered("parent"), "audit_logs/row1"), {
        eventType: "AUDIT_PARENTAL_CONSENT_CORRECTED",
      })
    );
    await assertFails(deleteDoc(doc(registered("parent"), "audit_logs/row1")));
  });
});

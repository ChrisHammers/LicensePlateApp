/**
 * Firestore security-rules matrix — COPPA F-5a + F-5b (§14 rules section).
 *
 * F-5b adds, below the F-5a blocks:
 *  - FR-12 `users/{uid}` child exclusion + ordered family carve-out (four-case matrix plus
 *          the family-roster hydration regression the carve-out exists to protect);
 *  - FR-14 follow-up: `friends` is client write:false;
 *  - FR-16(a) `invites` client-create denial;
 *  - FR-37 `public_lifetime_stats` child exclusion + carve-out.
 *  - FR-48 `public_lifetime_stats` + `usernames/{usernameLower}` peer reads restricted to
 *          registered (non-anonymous) accounts (self-access stays unconditional).
 *
 * F-5a covers:
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
  deleteField,
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

  it("adults keep share_codes (regression), even with no users doc at all", async () => {
    // NB: `friends` is no longer part of this regression — F-5b closed it to clients
    // entirely (FR-14 follow-up, matrix below).
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
// FR-12 (F-5b) — users/{uid} child exclusion + ordered family carve-out
// ---------------------------------------------------------------------------

/**
 * fam1 = parent + famkid (a consented child). `orphankid` is the sticky post-exit case:
 * flag still true, `activeFamilyId` deleted by the membership-leave update — which is what
 * the key-presence guard in the FR-12 expression has to catch before it builds a path.
 */
async function seedChildVisibilityFixtures(): Promise<void> {
  await seed({
    "users/parent": { userName: "Parent", activeFamilyId: "fam1" },
    "users/famkid": {
      userName: "FamKid",
      isChildAccount: true,
      activeFamilyId: "fam1",
    },
    "users/orphankid": { userName: "OrphanKid", isChildAccount: true },
    "users/ghostfamilykid": {
      userName: "GhostKid",
      isChildAccount: true,
      activeFamilyId: "deleted-family",
    },
    "users/adultNoFamily": { userName: "Solo" },
    "users/adultInFamily": { userName: "Grown", activeFamilyId: "fam1" },
    "users/stranger": { userName: "Stranger" },
    "families/fam1": { name: "Fam", creatorId: "parent", status: "active" },
    "families/fam1/members/parent": { role: "creator" },
    "families/fam1/members/famkid": { role: "scout", isChild: true },
    "families/fam1/members/adultInFamily": { role: "scout" },
  });
}

describe("FR-12: a child's user doc is family-only", () => {
  beforeEach(seedChildVisibilityFixtures);

  it("denies a stranger reading a consented child", async () => {
    await assertFails(getDoc(doc(registered("stranger"), "users/famkid")));
  });

  it("allows a member of the child's active family (the carve-out)", async () => {
    await assertSucceeds(getDoc(doc(registered("parent"), "users/famkid")));
    await assertSucceeds(getDoc(doc(registered("adultInFamily"), "users/famkid")));
  });

  it("denies an ORPHANED child to everyone, including their ex-family", async () => {
    await assertFails(getDoc(doc(registered("parent"), "users/orphankid")));
    await assertFails(getDoc(doc(registered("stranger"), "users/orphankid")));
  });

  it("denies a child whose activeFamilyId points at a family that no longer exists", async () => {
    await assertFails(getDoc(doc(registered("parent"), "users/ghostfamilykid")));
  });

  it("lets a child always read their own doc, orphaned or not", async () => {
    await assertSucceeds(getDoc(doc(registered("famkid"), "users/famkid")));
    await assertSucceeds(getDoc(doc(registered("orphankid"), "users/orphankid")));
  });

  it("denies anonymous callers a child doc, but not their own", async () => {
    await assertFails(getDoc(doc(anonymous("anon1"), "users/famkid")));
    await seed({ "users/anon1": { userName: "Anon", isRegistered: false } });
    await assertSucceeds(getDoc(doc(anonymous("anon1"), "users/anon1")));
  });

  it("REGRESSION: an adult with no activeFamilyId is still readable", async () => {
    // The key-presence guard must never fire for adults — it sits behind the child check.
    await assertSucceeds(getDoc(doc(registered("stranger"), "users/adultNoFamily")));
    await assertSucceeds(getDoc(doc(registered("stranger"), "users/adultInFamily")));
  });

  it("REGRESSION: family-roster hydration still reads every member, child included", async () => {
    // This is the whole reason the carve-out exists: family screens fetch each member's
    // users/{uid} doc by uid. Flagging a child must not blank out their own family's roster.
    const parent = registered("parent");
    for (const memberId of ["parent", "famkid", "adultInFamily"]) {
      await assertSucceeds(getDoc(doc(parent, `users/${memberId}`)));
    }
    const kid = registered("famkid");
    for (const memberId of ["parent", "famkid", "adultInFamily"]) {
      await assertSucceeds(getDoc(doc(kid, `users/${memberId}`)));
    }
  });

  it("REGRESSION: the anonymous-target exclusion still applies", async () => {
    await seed({ "users/anonTarget": { userName: "A", isRegistered: false } });
    await assertFails(getDoc(doc(registered("stranger"), "users/anonTarget")));
  });
});

// ---------------------------------------------------------------------------
// FR-37 (F-5b) — public_lifetime_stats mirrors the FR-12 carve-out
// ---------------------------------------------------------------------------

describe("FR-37: public_lifetime_stats hides children from strangers", () => {
  beforeEach(async () => {
    await seedChildVisibilityFixtures();
    await seed({
      "public_lifetime_stats/famkid": { platesFound: 12 },
      "public_lifetime_stats/orphankid": { platesFound: 3 },
      "public_lifetime_stats/adultNoFamily": { platesFound: 40 },
      "public_lifetime_stats/ghostuser": { platesFound: 1 }, // no users/{uid} doc
    });
  });

  it("denies a stranger the stats of a consented child", async () => {
    await assertFails(
      getDoc(doc(registered("stranger"), "public_lifetime_stats/famkid"))
    );
  });

  it("denies a stranger AND the ex-family the stats of an orphaned child", async () => {
    await assertFails(
      getDoc(doc(registered("stranger"), "public_lifetime_stats/orphankid"))
    );
    await assertFails(
      getDoc(doc(registered("parent"), "public_lifetime_stats/orphankid"))
    );
  });

  it("allows the child's family, and the child themselves", async () => {
    await assertSucceeds(
      getDoc(doc(registered("parent"), "public_lifetime_stats/famkid"))
    );
    await assertSucceeds(
      getDoc(doc(registered("famkid"), "public_lifetime_stats/famkid"))
    );
    await assertSucceeds(
      getDoc(doc(registered("orphankid"), "public_lifetime_stats/orphankid"))
    );
  });

  it("REGRESSION: adult stats stay readable for a registered peer", async () => {
    await assertSucceeds(
      getDoc(doc(registered("stranger"), "public_lifetime_stats/adultNoFamily"))
    );
  });

  // FR-48 (COPPA F-11, deliberate semantics change — ui-refactor-parity does not apply,
  // this is the acceptance criterion): an anonymous peer used to read any adult's stats;
  // now peer reads require a registered (non-anonymous) account.
  it("FR-48: an anonymous peer can no longer read another account's stats", async () => {
    await assertFails(
      getDoc(doc(anonymous("anon1"), "public_lifetime_stats/adultNoFamily"))
    );
  });

  it("REGRESSION: a residual stats row with no user doc does not error-deny", async () => {
    await assertSucceeds(
      getDoc(doc(registered("stranger"), "public_lifetime_stats/ghostuser"))
    );
  });

  it("writes remain server-only", async () => {
    await assertFails(
      setDoc(doc(registered("famkid"), "public_lifetime_stats/famkid"), {
        platesFound: 9999,
      })
    );
  });

  // FR-48 (COPPA F-11): self-access is unconditional — an anonymous account may always
  // read its OWN stats row, mirroring isDiscoverableUserProfile's self clause. Only the
  // peer branch requires a registered account (see the dedicated FR-48 block below).
  it("FR-48: an anonymous caller still reads their own stats", async () => {
    await seed({ "users/anon1": { userName: "Anon", isRegistered: false } });
    await assertSucceeds(
      getDoc(doc(anonymous("anon1"), "public_lifetime_stats/anon1"))
    );
  });
});

// ---------------------------------------------------------------------------
// FR-48 (F-11) — adult discoverability controls: registered-only reads
// ---------------------------------------------------------------------------

describe("FR-48: public_lifetime_stats and usernames are registered-only for peers", () => {
  beforeEach(async () => {
    await seed({
      "users/grown": { userName: "Grown" },
      "public_lifetime_stats/grown": { platesFound: 7 },
      "usernames/grown": { userId: "grown" },
    });
  });

  it("denies an anonymous caller reading public_lifetime_stats for another account", async () => {
    await assertFails(getDoc(doc(anonymous("anon1"), "public_lifetime_stats/grown")));
  });

  it("allows a registered caller reading public_lifetime_stats for another account", async () => {
    await assertSucceeds(getDoc(doc(registered("stranger"), "public_lifetime_stats/grown")));
  });

  it("denies an anonymous caller reading the usernames index", async () => {
    await assertFails(getDoc(doc(anonymous("anon1"), "usernames/grown")));
  });

  it("allows a registered caller reading the usernames index", async () => {
    await assertSucceeds(getDoc(doc(registered("stranger"), "usernames/grown")));
  });

  it("usernames writes remain server-only, for both anonymous and registered callers", async () => {
    await assertFails(
      setDoc(doc(anonymous("anon1"), "usernames/hijacked"), { userId: "anon1" })
    );
    await assertFails(
      setDoc(doc(registered("stranger"), "usernames/hijacked"), { userId: "stranger" })
    );
  });
});

// ---------------------------------------------------------------------------
// FR-14 follow-up (F-5b) — friends is client write:false
// ---------------------------------------------------------------------------

describe("FR-14 follow-up: friend edges are server-written only", () => {
  beforeEach(async () => {
    await seed({
      "users/adult": { userName: "Grown" },
      "users/other": { userName: "Other" },
      "friends/adult_other": {
        userA: "adult",
        userB: "other",
        status: "accepted",
      },
    });
  });

  it("denies creates even from an adult naming themselves", async () => {
    await assertFails(
      setDoc(doc(registered("adult"), "friends/adult_third"), {
        userA: "adult",
        userB: "third",
        status: "pending",
      })
    );
  });

  it("denies updates and deletes from a party to the edge", async () => {
    await assertFails(
      updateDoc(doc(registered("adult"), "friends/adult_other"), {
        status: "pending",
      })
    );
    await assertFails(deleteDoc(doc(registered("adult"), "friends/adult_other")));
  });

  it("REGRESSION: both parties can still READ their edge; outsiders cannot", async () => {
    await assertSucceeds(getDoc(doc(registered("adult"), "friends/adult_other")));
    await assertSucceeds(getDoc(doc(registered("other"), "friends/adult_other")));
    await assertFails(getDoc(doc(registered("stranger"), "friends/adult_other")));
  });
});

// ---------------------------------------------------------------------------
// FR-16(a) (F-5b) — invites are created server-side only
// ---------------------------------------------------------------------------

describe("FR-16(a): clients cannot create invites", () => {
  beforeEach(async () => {
    await seed({
      "families/fam1": { name: "Fam", creatorId: "creator", status: "active" },
      "families/fam1/members/creator": { role: "creator" },
      "invites/inv1": {
        type: "family",
        fromUserId: "creator",
        toUserId: "invitee",
        familyId: "fam1",
        status: "pending",
      },
    });
  });

  it("denies an honest self-named create", async () => {
    await assertFails(
      setDoc(doc(collection(registered("creator"), "invites")), {
        type: "family",
        fromUserId: "creator",
        toUserId: "invitee",
        familyId: "fam1",
        status: "pending",
      })
    );
  });

  it("denies a forged create naming someone else as sender", async () => {
    await assertFails(
      setDoc(doc(collection(registered("stranger"), "invites")), {
        type: "friend",
        fromUserId: "victim",
        toUserId: "stranger",
        status: "pending",
      })
    );
  });

  it("REGRESSION: parties can still read and respond to an existing invite", async () => {
    await assertSucceeds(getDoc(doc(registered("invitee"), "invites/inv1")));
    await assertSucceeds(
      updateDoc(doc(registered("invitee"), "invites/inv1"), { status: "accepted" })
    );
    await assertFails(
      updateDoc(doc(registered("stranger"), "invites/inv1"), { status: "accepted" })
    );
  });

  it("REGRESSION: a family member can still read their family's invites", async () => {
    await assertSucceeds(getDoc(doc(registered("creator"), "invites/inv1")));
  });

  it("deletes remain closed", async () => {
    await assertFails(deleteDoc(doc(registered("creator"), "invites/inv1")));
  });
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

// ---------------------------------------------------------------------------
// FR-24 (F-6 rework) — direct `families` creation cannot bypass the createFamily
// callable's child gate
// ---------------------------------------------------------------------------

describe("FR-24 (F-6): child accounts cannot create family docs directly", () => {
  const familyDoc = { name: "New Fam", creatorId: "x", status: "active" };

  it("denies an unconsented child", async () => {
    await seed({ "users/kid": { userName: "Kid", isChildAccount: true } });
    await assertFails(
      setDoc(doc(registered("kid"), "families/famNew1"), familyDoc)
    );
  });

  it("denies a consented child too (family membership does not help)", async () => {
    await seed({
      "users/kid": { userName: "Kid", isChildAccount: true, activeFamilyId: "fam1" },
    });
    await assertFails(
      setDoc(doc(registered("kid"), "families/famNew2"), familyDoc)
    );
  });

  it("allows a registered adult", async () => {
    await seed({ "users/adult": { userName: "Grown" } });
    await assertSucceeds(
      setDoc(doc(registered("adult"), "families/famNew3"), familyDoc)
    );
  });

  it("allows a registered caller with no user doc (missing flag means adult)", async () => {
    await assertSucceeds(
      setDoc(doc(registered("docless"), "families/famNew4"), familyDoc)
    );
  });

  it("still denies anonymous callers (registered-account gate)", async () => {
    await assertFails(
      setDoc(doc(anonymous("anon9"), "families/famNew5"), familyDoc)
    );
  });
});

// ---------------------------------------------------------------------------
// F-6 rework — users docs can never reintroduce real-name fields
// ---------------------------------------------------------------------------

describe("F-6 rework: users docs reject firstName/lastName", () => {
  beforeEach(async () => {
    await seed({
      "users/named": { userName: "Named", firstName: "Ada", lastName: "Lovelace" },
    });
  });

  it("denies creates carrying a name field", async () => {
    await assertFails(
      setDoc(doc(registered("fresh9"), "users/fresh9"), {
        userName: "F9",
        firstName: "Ada",
      })
    );
  });

  it("denies updates reintroducing a name field", async () => {
    await assertFails(
      updateDoc(doc(registered("named"), "users/named"), { lastName: "Byron" })
    );
  });

  it("allows the migration write that strips names via FieldValue.delete()", async () => {
    await assertSucceeds(
      updateDoc(doc(registered("named"), "users/named"), {
        firstName: deleteField(),
        lastName: deleteField(),
        userName: "Named v2",
      })
    );
  });
});

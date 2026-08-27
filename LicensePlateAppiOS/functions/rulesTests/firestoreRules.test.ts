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
 * F-22/F-23 (COPPA v3) add:
 *  - FR-66(a) `families/{id}/pending` client-create denial — SUPERSEDES the F-5a G-6
 *          self-naming rule, which an attacker satisfied honestly (see the block comment);
 *  - FR-66(c) `invites` party updates limited to `status` / `updatedAt`;
 *  - FR-66(d) `share_codes` writes barred to ALL children (not just unconsented ones) and
 *          bound to a familyId the creator belongs to;
 *  - FR-67  `share_codes` reads scoped to the creator or the named family — the collection
 *          was world-listable, which made the 6-character code space irrelevant.
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
  getDocs,
  query,
  setDoc,
  updateDoc,
  where,
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

  /**
   * AGEOUT FR-110(a)/(c) (2026-08-27): `ageOutYearMonth` is stamped at declaration and
   * drives age-out detection. A client that could write it could fake an age; one that
   * could clear it could make a child undetectable at 13. Server-controlled, both twins.
   */
  it("denies clients writing or clearing ageOutYearMonth (FR-110)", async () => {
    await seed({
      "users/marked": { userName: "Kid", isChildAccount: true, ageOutYearMonth: 203703 },
    });
    await assertFails(
      updateDoc(doc(registered("marked"), "users/marked"), { ageOutYearMonth: 209912 })
    );
    // Full set omitting the key = clearing it via affectedKeys.
    await assertFails(
      setDoc(doc(registered("marked"), "users/marked"), { userName: "Kid v2" })
    );
    await assertFails(
      setDoc(doc(registered("fresh4"), "users/fresh4"), {
        userName: "F4",
        ageOutYearMonth: 203703,
      })
    );
  });

  /**
   * FR-59.1 (2026-08-27): consent_requests carry the guardian's email and the hashed
   * confirmation nonce. Server-only, full stop — the GUARDIAN's own client included
   * (their credential is the emailed link, never a Firestore read).
   */
  it("denies every client read and write of consent_requests", async () => {
    await seed({
      "consent_requests/req1": {
        familyId: "fam1",
        childUserId: "kid",
        guardianUid: "adult",
        status: "pending",
      },
    });
    await assertFails(getDoc(doc(registered("adult"), "consent_requests/req1")));
    await assertFails(getDoc(doc(registered("kid"), "consent_requests/req1")));
    await assertFails(
      updateDoc(doc(registered("adult"), "consent_requests/req1"), { status: "confirmed" })
    );
    await assertFails(
      setDoc(doc(registered("adult"), "consent_requests/req2"), { status: "pending" })
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

  /**
   * FR-60(c): `childDeclaredAt` opens the redemption window and, once deleted at admission,
   * closes it. It is what the transient-account sweep reads, so a client that could write or
   * clear it could delete its own pre-consent footprint on demand, or keep an unconsented
   * account alive past the window by re-stamping it.
   */
  it("denies clients writing, changing or clearing childDeclaredAt (FR-60)", async () => {
    await seed({
      "users/provisional": { userName: "Kid", isChildAccount: true, childDeclaredAt: 1000 },
    });

    await assertFails(
      updateDoc(doc(registered("provisional"), "users/provisional"), { childDeclaredAt: 5000 })
    );
    await assertFails(
      setDoc(doc(registered("provisional"), "users/provisional"), { userName: "Kid v2" })
    );
    await assertFails(
      setDoc(doc(registered("fresh4"), "users/fresh4"), {
        userName: "F4",
        childDeclaredAt: 1000,
      })
    );

    // The child's own ordinary profile sync, which never touches the key, still lands.
    await assertSucceeds(
      updateDoc(doc(registered("provisional"), "users/provisional"), { userName: "Kid v2" })
    );
  });

  /**
   * FR-88: `pendingFamilyRequest` is the child's only way to verify that a family really is
   * deciding about them — `families/{id}/pending` is member-read-only and a pending child is
   * not a member. A client that could WRITE it could manufacture a consent request that no
   * captain ever received; one that could CLEAR it could hide a real one, or paper over the
   * decline this field exists to make visible. Server-written only, on the same batch as the
   * pending row, so the two can never disagree.
   */
  it("denies clients writing, changing or clearing pendingFamilyRequest (FR-88)", async () => {
    await seed({
      "users/waiting": {
        userName: "Kid",
        isChildAccount: true,
        pendingFamilyRequest: { familyId: "fam1", requestId: "req1", createdAt: 1000 },
      },
    });

    // Re-point it at a family that never asked.
    await assertFails(
      updateDoc(doc(registered("waiting"), "users/waiting"), {
        pendingFamilyRequest: { familyId: "attacker", requestId: "req9", createdAt: 5000 },
      })
    );
    // Clear it outright — the "make the decline disappear" write.
    await assertFails(
      updateDoc(doc(registered("waiting"), "users/waiting"), {
        pendingFamilyRequest: deleteField(),
      })
    );
    // Clear it by omission on a full set (affectedKeys catches deletes).
    await assertFails(
      setDoc(doc(registered("waiting"), "users/waiting"), { userName: "Kid v2" })
    );
    // Smuggle it in on create, forging a request in flight from the first write.
    await assertFails(
      setDoc(doc(registered("fresh5"), "users/fresh5"), {
        userName: "F5",
        pendingFamilyRequest: { familyId: "fam1", requestId: "req1", createdAt: 1000 },
      })
    );

    // The child's own ordinary profile sync, which never touches the key, still lands.
    await assertSucceeds(
      updateDoc(doc(registered("waiting"), "users/waiting"), { userName: "Kid v2" })
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

describe("FR-66(a): pending join requests are server-minted only", () => {
  beforeEach(async () => {
    await seed({
      "families/fam1": { name: "Fam", creatorId: "creator", status: "active" },
      "families/fam1/members/creator": { role: "creator" },
      "families/fam1/pending/req1": { userId: "joiner", status: "pending" },
    });
  });

  /**
   * SUPERSEDES the G-6 self-naming rule. Self-naming was never sufficient, because family
   * membership is this app's parental-consent object: a child could found a family from a
   * throwaway "adult" account, write a TRUTHFULLY self-named request from their real flagged
   * account, and approve themselves out of every child protection (CB-7). The honest request
   * and the laundering request were byte-identical, so no content check could separate them.
   */
  it("denies a registered user creating a request for themselves (was allowed pre-FR-66)", async () => {
    await assertFails(
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

  it("denies a family member and the creator too — there is no privileged writer", async () => {
    for (const uid of ["creator", "joiner"]) {
      await assertFails(
        setDoc(doc(collection(registered(uid), "families/fam1/pending")), {
          userId: uid,
          status: "pending",
        })
      );
    }
  });

  it("denies anonymous callers even for their own uid", async () => {
    await assertFails(
      setDoc(doc(collection(anonymous("anon1"), "families/fam1/pending")), {
        userId: "anon1",
        status: "pending",
      })
    );
  });

  it("REGRESSION: family members can still READ the queue (the client's only use)", async () => {
    await assertSucceeds(getDoc(doc(registered("creator"), "families/fam1/pending/req1")));
    await assertFails(getDoc(doc(registered("stranger"), "families/fam1/pending/req1")));
  });

  it("REGRESSION: a captain can still resolve a request", async () => {
    await assertSucceeds(
      updateDoc(doc(registered("creator"), "families/fam1/pending/req1"), {
        status: "declined",
      })
    );
  });
});

// ---------------------------------------------------------------------------
// FR-66(c) — invite party updates are limited to the response itself
// ---------------------------------------------------------------------------

describe("FR-66(c): invite updates cannot retarget the invite", () => {
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

  it("allows a party to write status (+ updatedAt) and nothing else", async () => {
    await assertSucceeds(
      updateDoc(doc(registered("invitee"), "invites/inv1"), { status: "accepted" })
    );
  });

  /**
   * The residual this closes (v2.1 §18(a)/G53): either party could rewrite ANY field.
   * Retargeting `familyId` pointed an already-accepted invite at a family the sender had no
   * rights over — and a family invite is the front half of the consent boundary.
   */
  it("denies retargeting familyId, type, or the counterparty", async () => {
    for (const patch of [
      { familyId: "someone-elses-family" },
      { status: "accepted", familyId: "someone-elses-family" },
      { type: "friend" },
      { fromUserId: "invitee" },
      { toUserId: "someone-else" },
      { status: "accepted", codeId: "forged" },
    ]) {
      await assertFails(updateDoc(doc(registered("invitee"), "invites/inv1"), patch));
    }
  });

  it("still denies a non-party entirely", async () => {
    await assertFails(
      updateDoc(doc(registered("stranger"), "invites/inv1"), { status: "accepted" })
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

  /**
   * FR-66(d) flips this case. `!callerIsUnconsentedChild()` let a CONSENTED child mint share
   * codes, but minting one is stranger-contact initiation — outside `consentScope` no matter
   * what a parent agreed to, and exactly the axis `assertCallerIsNotChild` already enforces
   * in the callable. Rules and callable now agree.
   */
  it("FR-66(d): a CONSENTED child is now refused too (was allowed under FR-28)", async () => {
    await assertFails(
      setDoc(doc(registered("famkid"), "share_codes/famkidCode"), {
        type: "friend",
        createdBy: "famkid",
        isRevoked: false,
      })
    );
  });
});

// ---------------------------------------------------------------------------
// FR-66(d) + FR-67 — share_codes write binding and read scoping
// ---------------------------------------------------------------------------

describe("FR-66(d): a share code must name a family the creator belongs to", () => {
  beforeEach(async () => {
    await seed({
      "users/member": { userName: "Member" },
      "users/outsider": { userName: "Outsider" },
      "families/fam1": { name: "Fam", creatorId: "member", status: "active" },
      "families/fam1/members/member": { role: "creator" },
      "share_codes/memberCode": {
        type: "family",
        createdBy: "member",
        familyId: "fam1",
        isRevoked: false,
      },
    });
  });

  it("allows a member to mint a code for their own family", async () => {
    await assertSucceeds(
      setDoc(doc(registered("member"), "share_codes/newCode"), {
        type: "family",
        createdBy: "member",
        familyId: "fam1",
        isRevoked: false,
      })
    );
  });

  /** Adult-reachable forgery: `activeFamilyId` is readable on peer user docs. */
  it("denies a non-member minting a code for a family they merely named", async () => {
    await assertFails(
      setDoc(doc(registered("outsider"), "share_codes/forged"), {
        type: "family",
        createdBy: "outsider",
        familyId: "fam1",
        isRevoked: false,
      })
    );
  });

  it("REGRESSION: friend codes carry no familyId and stay unaffected", async () => {
    await assertSucceeds(
      setDoc(doc(registered("outsider"), "share_codes/friendCode"), {
        type: "friend",
        createdBy: "outsider",
        isRevoked: false,
      })
    );
  });

  it("REGRESSION: the owner can still revoke their own code", async () => {
    await assertSucceeds(
      updateDoc(doc(registered("member"), "share_codes/memberCode"), { isRevoked: true })
    );
  });

  it("denies retargeting an existing code at a family the owner is not in", async () => {
    await assertFails(
      updateDoc(doc(registered("member"), "share_codes/memberCode"), {
        familyId: "fam-someone-else",
      })
    );
  });
});

describe("FR-67: share codes are not enumerable", () => {
  beforeEach(async () => {
    await seed({
      "families/fam1": { name: "Fam", creatorId: "member", status: "active" },
      "families/fam1/members/member": { role: "creator" },
      "share_codes/famCode": {
        type: "family",
        code: "FAM111",
        createdBy: "member",
        familyId: "fam1",
        isRevoked: false,
      },
      "share_codes/friendCode": {
        type: "friend",
        code: "FRD222",
        createdBy: "member",
        isRevoked: false,
      },
    });
  });

  /**
   * The hole: `allow read: if isSignedIn()` made the whole collection listable by any
   * account, so the six-character code space was irrelevant — you did not have to guess a
   * code, you could read them all. A stranger holding a code still redeems it through the
   * `redeemShareCode` callable (Admin SDK, rules-exempt, now rate-limited).
   */
  it("denies a stranger reading a code document", async () => {
    await assertFails(getDoc(doc(registered("stranger"), "share_codes/famCode")));
    await assertFails(getDoc(doc(registered("stranger"), "share_codes/friendCode")));
  });

  it("denies a stranger LISTING the collection, filtered or not", async () => {
    await assertFails(getDocs(collection(registered("stranger"), "share_codes")));
    await assertFails(
      getDocs(
        query(
          collection(registered("stranger"), "share_codes"),
          where("familyId", "==", "fam1")
        )
      )
    );
  });

  it("allows the creator to read their own code", async () => {
    await assertSucceeds(getDoc(doc(registered("member"), "share_codes/friendCode")));
  });

  /** The client's ONLY live query (`FamilyRepository.getActiveShareCode`). */
  it("REGRESSION: a family member can still query their family's codes by familyId", async () => {
    await assertSucceeds(
      getDocs(
        query(
          collection(registered("member"), "share_codes"),
          where("familyId", "==", "fam1")
        )
      )
    );
  });

  it("denies anonymous callers outright", async () => {
    await assertFails(getDoc(doc(anonymous("anon1"), "share_codes/famCode")));
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
// FR-85 (F-42) — a consented child is a full member, not a second-class anonymous session
// ---------------------------------------------------------------------------

/**
 * FR-60 made consented children ANONYMOUS Firebase accounts, so every rule that used
 * `isRegisteredAccount()` as a proxy for "legitimate member" started denying them. These
 * fixtures use the real FR-60 shape — note `isRegistered: false` on the child docs, which
 * `FirebaseAuthService.saveUserDataToFirestore` writes for any anonymous session, and which
 * used to hide a consented child from their OWN family through the FR-48 target clause.
 *
 * fam1: parent (creator) + famkid (consented child) + adultInFamily + retiredGeneral.
 * `retiredGeneral` is the member who holds a member doc but carries NO `activeFamilyId` —
 * the case that forces membership to be proved by the member doc rather than by the peer's
 * own `activeFamilyId` field.
 * `forgedkid` is the attack: a child who self-wrote `activeFamilyId: "fam1"` (the one field
 * of the three a client CAN write on its own user doc) with no member doc to back it.
 */
async function seedFr85Fixtures(): Promise<void> {
  await seed({
    "users/parent": { userName: "Parent", activeFamilyId: "fam1" },
    "users/adultInFamily": { userName: "Grown", activeFamilyId: "fam1" },
    "users/retiredGeneral": { userName: "Retired", isRetiredGeneral: true },
    "users/famkid": {
      userName: "FamKid",
      isChildAccount: true,
      activeFamilyId: "fam1",
      isRegistered: false,
      entitlementTags: ["signedUpEquivalent"],
    },
    "users/sibkid": {
      userName: "SibKid",
      isChildAccount: true,
      activeFamilyId: "fam1",
      isRegistered: false,
    },
    "users/orphankid": {
      userName: "OrphanKid",
      isChildAccount: true,
      isRegistered: false,
    },
    "users/forgedkid": {
      userName: "ForgedKid",
      isChildAccount: true,
      activeFamilyId: "fam1",
      isRegistered: false,
    },
    "users/anonStranger": { userName: "Anon", isRegistered: false },
    "users/adultNoFamily": { userName: "Solo" },
    "users/otherParent": { userName: "OtherParent", activeFamilyId: "fam2" },
    "families/fam1": { name: "Fam", creatorId: "parent", status: "active" },
    "families/fam1/members/parent": { role: "creator" },
    "families/fam1/members/adultInFamily": { role: "scout" },
    "families/fam1/members/retiredGeneral": { role: "retired_general" },
    "families/fam1/members/famkid": { role: "scout", isChild: true },
    "families/fam1/members/sibkid": { role: "scout", isChild: true },
    "families/fam2": { name: "Other", creatorId: "otherParent", status: "active" },
    "families/fam2/members/otherParent": { role: "creator" },
    "public_lifetime_stats/parent": { platesFound: 40 },
    "public_lifetime_stats/adultInFamily": { platesFound: 22 },
    "public_lifetime_stats/retiredGeneral": { platesFound: 9 },
    "public_lifetime_stats/sibkid": { platesFound: 5 },
    "public_lifetime_stats/adultNoFamily": { platesFound: 77 },
  });
}

/**
 * The five callers of the acceptance matrix. `famkid` is the population FR-85 is about:
 * anonymous, flagged, and holding a server-written member doc in fam1.
 */
const FR85_CALLERS = {
  consentedChild: () => anonymous("famkid"),
  anonymousStranger: () => anonymous("anonStranger"),
  unconsentedChild: () => anonymous("orphankid"),
  registeredFamilyAdult: () => registered("parent"),
  registeredNonFamilyAdult: () => registered("adultNoFamily"),
} as const;

/** Exactly the two reads FR-85 grants, and the two writes it must NOT. */
const FR85_MATRIX: Array<{
  caller: keyof typeof FR85_CALLERS;
  peerUserDoc: boolean;
  peerStats: boolean;
}> = [
  { caller: "consentedChild", peerUserDoc: true, peerStats: true },
  { caller: "anonymousStranger", peerUserDoc: false, peerStats: false },
  { caller: "unconsentedChild", peerUserDoc: false, peerStats: false },
  { caller: "registeredFamilyAdult", peerUserDoc: true, peerStats: true },
  // A registered non-family adult reads adult profiles/stats but not the family's children.
  { caller: "registeredNonFamilyAdult", peerUserDoc: true, peerStats: true },
];

describe("FR-85: consented-child capability parity", () => {
  beforeEach(seedFr85Fixtures);

  describe("matrix: (caller) x (peer user doc, public_lifetime_stats)", () => {
    for (const row of FR85_MATRIX) {
      it(`${row.caller}: peer user doc read ${row.peerUserDoc ? "allowed" : "denied"}`, async () => {
        const read = getDoc(doc(FR85_CALLERS[row.caller](), "users/adultInFamily"));
        await (row.peerUserDoc ? assertSucceeds(read) : assertFails(read));
      });

      it(`${row.caller}: peer stats read ${row.peerStats ? "allowed" : "denied"}`, async () => {
        const read = getDoc(
          doc(FR85_CALLERS[row.caller](), "public_lifetime_stats/adultInFamily")
        );
        await (row.peerStats ? assertSucceeds(read) : assertFails(read));
      });
    }
  });

  describe("matrix: (caller) x (families create, share_codes create) — nobody gains these", () => {
    for (const caller of Object.keys(FR85_CALLERS) as Array<keyof typeof FR85_CALLERS>) {
      const allowed = caller === "registeredFamilyAdult" || caller === "registeredNonFamilyAdult";

      it(`${caller}: families create ${allowed ? "allowed" : "denied"}`, async () => {
        const write = setDoc(doc(FR85_CALLERS[caller](), `families/new_${caller}`), {
          name: "New",
          creatorId: "whoever",
          status: "active",
        });
        await (allowed ? assertSucceeds(write) : assertFails(write));
      });

      it(`${caller}: share_codes create ${allowed ? "allowed" : "denied"}`, async () => {
        const uid = {
          consentedChild: "famkid",
          anonymousStranger: "anonStranger",
          unconsentedChild: "orphankid",
          registeredFamilyAdult: "parent",
          registeredNonFamilyAdult: "adultNoFamily",
        }[caller];
        const write = setDoc(doc(FR85_CALLERS[caller](), `share_codes/code_${caller}`), {
          type: "friend",
          createdBy: uid,
          isRevoked: false,
        });
        await (allowed ? assertSucceeds(write) : assertFails(write));
      });
    }
  });

  // -------------------------------------------------------------------------
  // The grant, in detail
  // -------------------------------------------------------------------------

  it("hydrates the child's ENTIRE own-family roster, retired generals included", async () => {
    const kid = FR85_CALLERS.consentedChild();
    for (const memberId of ["parent", "adultInFamily", "retiredGeneral", "sibkid", "famkid"]) {
      await assertSucceeds(getDoc(doc(kid, `users/${memberId}`)));
    }
  });

  it("reads own-family stats, including another child's", async () => {
    const kid = FR85_CALLERS.consentedChild();
    for (const memberId of ["parent", "adultInFamily", "retiredGeneral", "sibkid"]) {
      await assertSucceeds(getDoc(doc(kid, `public_lifetime_stats/${memberId}`)));
    }
  });

  // The FR-48 target clause (`isRegistered != false`) was hiding consented children from
  // their own family, because FR-60 makes their account anonymous. This is the reverse of
  // the FR-12 degradation and the reason the target side had to be corrected too.
  it("REGRESSION (FR-85 target side): the family can read a consented child whose doc says isRegistered:false", async () => {
    await assertSucceeds(getDoc(doc(registered("parent"), "users/famkid")));
    await assertSucceeds(getDoc(doc(registered("adultInFamily"), "users/famkid")));
    await assertSucceeds(getDoc(doc(anonymous("famkid"), "users/sibkid")));
  });

  // -------------------------------------------------------------------------
  // The scope of the grant — everything the child must still NOT get
  // -------------------------------------------------------------------------

  it("scopes the widening to the child's OWN family, not a blanket anonymous read", async () => {
    const kid = FR85_CALLERS.consentedChild();
    await assertFails(getDoc(doc(kid, "users/adultNoFamily")));
    await assertFails(getDoc(doc(kid, "users/otherParent")));
    await assertFails(getDoc(doc(kid, "public_lifetime_stats/adultNoFamily")));
  });

  it("a forged activeFamilyId with no member doc behind it gains nothing", async () => {
    const forger = anonymous("forgedkid");
    await assertFails(getDoc(doc(forger, "users/parent")));
    await assertFails(getDoc(doc(forger, "users/adultInFamily")));
    await assertFails(getDoc(doc(forger, "public_lifetime_stats/parent")));
  });

  it("does not widen usernames, invites, or share-code reads", async () => {
    await seed({
      "usernames/parent": { userId: "parent" },
      "share_codes/parentCode": {
        type: "family",
        createdBy: "parent",
        familyId: "fam1",
        isRevoked: false,
      },
      "invites/inv1": {
        fromUserId: "parent",
        toUserId: "famkid",
        type: "family",
        familyId: "fam1",
        status: "pending",
      },
    });
    const kid = FR85_CALLERS.consentedChild();
    // usernames maps a name straight to a uid — registration stays the gate (FR-48).
    await assertFails(getDoc(doc(kid, "usernames/parent")));
    // Invite responses are Admin-SDK only for a child; the client rule stays registered-only.
    await assertFails(updateDoc(doc(kid, "invites/inv1"), { status: "accepted" }));
    // Share-code READS are family-scoped, not registration-scoped, so this one is not a
    // widening — pinned here so a future change cannot quietly move it either way.
    await assertSucceeds(getDoc(doc(kid, "share_codes/parentCode")));
    await assertFails(
      updateDoc(doc(kid, "share_codes/parentCode"), { isRevoked: true })
    );
  });

  it("still cannot write its own server-controlled fields, tag included", async () => {
    const kid = FR85_CALLERS.consentedChild();
    await assertFails(
      updateDoc(doc(kid, "users/famkid"), { entitlementTags: ["founder", "signedUpEquivalent"] })
    );
    await assertFails(updateDoc(doc(kid, "users/famkid"), { isChildAccount: false }));
  });

  // FR-70 / FR-11 pin: the tag must not become a back door into search. `usernames` is the
  // exact-match index the syncers strip for children; a child must own no row and be unable
  // to read one. (`user_lookup_email` / `user_lookup_phone` are read/write:false for all.)
  it("FR-70/FR-11: a consented child has no search-index row and cannot read the index", async () => {
    await seed({ "usernames/grown": { userId: "adultInFamily" } });
    const kid = FR85_CALLERS.consentedChild();
    await assertFails(getDoc(doc(kid, "usernames/grown")));
    await assertFails(getDoc(doc(kid, "usernames/famkid")));
    await assertFails(
      setDoc(doc(kid, "usernames/famkid"), { userId: "famkid" })
    );
    await assertFails(getDoc(doc(kid, "user_lookup_email/kid@example.com")));
    await assertFails(getDoc(doc(kid, "user_lookup_phone/15555550100")));
  });

  it("REGRESSION: an unconsented (orphaned) child stays fully excluded", async () => {
    const orphan = FR85_CALLERS.unconsentedChild();
    await assertFails(getDoc(doc(orphan, "users/parent")));
    await assertFails(getDoc(doc(orphan, "public_lifetime_stats/parent")));
    // ...and is still unreadable to their own ex-family (FR-12 unchanged).
    await assertFails(getDoc(doc(registered("parent"), "users/orphankid")));
  });

  it("REGRESSION: a registered non-family adult still cannot see the family's children", async () => {
    const outsider = FR85_CALLERS.registeredNonFamilyAdult();
    await assertFails(getDoc(doc(outsider, "users/famkid")));
    await assertFails(getDoc(doc(outsider, "public_lifetime_stats/sibkid")));
  });

  it("REGRESSION: a plain anonymous NON-child target stays undiscoverable", async () => {
    await assertFails(getDoc(doc(registered("parent"), "users/anonStranger")));
    await assertFails(getDoc(doc(anonymous("famkid"), "users/anonStranger")));
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

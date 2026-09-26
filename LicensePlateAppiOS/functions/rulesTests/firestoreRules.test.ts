/**
 * Firestore security-rules matrix — COPPA F-5a + F-5b (§14 rules section).
 *
 * F-5b adds, below the F-5a blocks:
 *  - FR-12 `users/{uid}` child exclusion + ordered family carve-out (four-case matrix plus
 *          the family-roster hydration regression the carve-out exists to protect);
 *  - FR-14 follow-up: `friends` is client write:false;
 *  - FR-16(a) `invites` client-create denial;
 *  - FR-37 `public_lifetime_stats` child exclusion + carve-out.
 *  - FR-48 `public_lifetime_stats` peer reads restricted to registered (non-anonymous)
 *          accounts (self-access stays unconditional). `usernames/{usernameLower}` was
 *          also registered-only here — FR-71 below closes it to deny outright.
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
 * F-27 (COPPA v3) adds:
 *  - FR-71 `usernames/{usernameLower}` reads move from FR-48's "any registered account" to
 *          deny for everyone — SUPERSEDES the FR-48 usernames sub-clause above. Exact-match
 *          lookup lives server-side in the `searchUsers` callable (Admin SDK, bypasses these
 *          rules) and the shipped client never read this collection directly, so closing it
 *          is zero-regression and removes an enumeration path with none of `searchUsers`'
 *          protections (no rate limit, no audit row).
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

import { beforeAll, afterAll, beforeEach, describe, expect, it } from "vitest";
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
  collectionGroup,
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

/**
 * Custom-token caller — FR-84 (F-41). This is what a child's session looks like AFTER a
 * parent-initiated device transfer: `createCustomToken` is the only way to assume a
 * credential-less child uid on a new device, and it stamps `sign_in_provider == "custom"`.
 */
function customToken(uid: string): Firestore {
  return testEnv
    .authenticatedContext(uid, {
      firebase: { sign_in_provider: "custom" },
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
      setDoc(doc(registered("kid"), "users/kid"), { userName: "Kid_v2" })
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
      setDoc(doc(registered("marked"), "users/marked"), { userName: "Kid_v2" })
    );
    await assertFails(
      setDoc(doc(registered("fresh4"), "users/fresh4"), {
        userName: "Fresh4",
        ageOutYearMonth: 203703,
      })
    );
  });

  /**
   * FR-63(b) (2026-08-29): `pendingDeletionRequestedBy` is the deletion-intent marker
   * a retry authorizes off after a partial failure. A client that could write it could
   * forge a parent's deletion request; one that could clear it could strand a
   * half-deleted account unresumable. Server-controlled, both twins.
   */
  it("denies clients writing or clearing the deletion-intent marker (FR-63)", async () => {
    await seed({
      // Deliberately NO other server-controlled keys: the clear-twin below must be
      // denied by THIS key alone, not masked by isChildAccount's own guard.
      "users/pending": {
        userName: "Kid",
        pendingDeletionRequestedBy: "parentUid",
      },
    });
    await assertFails(
      updateDoc(doc(registered("pending"), "users/pending"), {
        pendingDeletionRequestedBy: "attacker",
      })
    );
    // Full set omitting the key = clearing it via affectedKeys.
    await assertFails(
      setDoc(doc(registered("pending"), "users/pending"), { userName: "Kid_v2" })
    );
    await assertFails(
      setDoc(doc(registered("fresh5"), "users/fresh5"), {
        userName: "Fresh5",
        pendingDeletionRequestedAtMillis: 1,
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
      updateDoc(doc(registered("kid"), "users/kid"), { userName: "Kid_v2" })
    );
  });

  it("denies creates that smuggle either server-controlled key in", async () => {
    await assertFails(
      setDoc(doc(registered("fresh1"), "users/fresh1"), {
        userName: "Fresh1",
        isChildAccount: false,
      })
    );
    await assertFails(
      setDoc(doc(registered("fresh2"), "users/fresh2"), {
        userName: "Fresh2",
        entitlementTags: ["family_plus"],
      })
    );
    await assertSucceeds(
      setDoc(doc(registered("fresh3"), "users/fresh3"), { userName: "Fresh3" })
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
      setDoc(doc(registered("provisional"), "users/provisional"), { userName: "Kid_v2" })
    );
    await assertFails(
      setDoc(doc(registered("fresh4"), "users/fresh4"), {
        userName: "Fresh4",
        childDeclaredAt: 1000,
      })
    );

    // The child's own ordinary profile sync, which never touches the key, still lands.
    await assertSucceeds(
      updateDoc(doc(registered("provisional"), "users/provisional"), { userName: "Kid_v2" })
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
      setDoc(doc(registered("waiting"), "users/waiting"), { userName: "Kid_v2" })
    );
    // Smuggle it in on create, forging a request in flight from the first write.
    await assertFails(
      setDoc(doc(registered("fresh5"), "users/fresh5"), {
        userName: "Fresh5",
        pendingFamilyRequest: { familyId: "fam1", requestId: "req1", createdAt: 1000 },
      })
    );

    // The child's own ordinary profile sync, which never touches the key, still lands.
    await assertSucceeds(
      updateDoc(doc(registered("waiting"), "users/waiting"), { userName: "Kid_v2" })
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
// FR-73 / v2.1 FR-53(a) — the push token is not writable by an unconsented child
// ---------------------------------------------------------------------------

/**
 * An FCM token is a persistent identifier and therefore personal information, so an
 * UNCONSENTED child — provisional inside the FR-60 redemption window, or sticky after a
 * revocation — may not have one. The client eligibility guard
 * (`PushTokenEligibilityPolicy`) is the first line; this block is the server-side backstop
 * a tampered or stale client cannot get past.
 *
 * The gate is scoped to CREATE/UPDATE of `fcm`, and the three things it deliberately leaves
 * open are each pinned below, because getting any of them wrong breaks a path FR-53 needs:
 * DELETE (so `clearFCMToken` can still remove a token), READ (owner-only reads are what
 * `private/` is for), and the `contact` doc (an unrelated F-5a surface).
 *
 * Children are ANONYMOUS accounts under FR-60/FR-85, so the child callers here are too.
 */
describe("FR-73(a): private/fcm writes are barred to unconsented children", () => {
  beforeEach(async () => {
    await seed({
      // Unconsented: flag true, no activeFamilyId (provisional, or sticky post-revocation).
      "users/lonekid": { userName: "LoneKid", isChildAccount: true },
      "users/lonekid/private/fcm": { token: "stale-token" },
      "users/lonekid/private/contact": { email: "parent@example.com" },
      // Consented: flag true WITH an active family.
      "users/famkid": { userName: "FamKid", isChildAccount: true, activeFamilyId: "fam1" },
      "users/famkid/private/fcm": { token: "famkid-token" },
      "users/adult": { userName: "Grown" },
      "users/adult/private/fcm": { token: "adult-token" },
    });
  });

  it("denies an unconsented child CREATING a token doc", async () => {
    // The redemption-window shape: `provisionalChildAccounts` has provisioned the uid and
    // written `isChildAccount: true`, and no family has admitted them yet.
    await seed({ "users/newkid": { userName: "NewKid", isChildAccount: true } });
    await assertFails(
      setDoc(doc(anonymous("newkid"), "users/newkid/private/fcm"), { token: "t" })
    );
  });

  /**
   * `callerIsUnconsentedChild()` reads "a missing doc or missing flag means adult" — the
   * standing convention in this file (see FR-24's doc-less case), and not negotiable here:
   * `get()` on a missing document error-denies, so a doc-less DENY would break every
   * legitimate first write.
   *
   * That is not a hole in FR-73, because the two layers cover disjoint populations. Under
   * FR-60 a never-consented child has no uid at all, and the moment one exists
   * `declareChildRegistration` / `provisionalChildAccounts` has already written the flag —
   * so a uid with NO user doc is an age-UNKNOWN guest, not a known child, and that session
   * is held by the CLIENT gate instead (`DeferredSDKStartupPlan.startsMessaging` is false
   * until age resolution, per FR-46). Rules catch the flagged child; the client catches the
   * unresolved one. Pinned so the division of labour is deliberate rather than discovered.
   */
  it("treats a caller with no user doc as an adult (documented convention)", async () => {
    await assertSucceeds(
      setDoc(doc(anonymous("newkid"), "users/newkid/private/fcm"), { token: "t" })
    );
  });

  it("denies an unconsented child UPDATING an existing token doc", async () => {
    await assertFails(
      updateDoc(doc(anonymous("lonekid"), "users/lonekid/private/fcm"), {
        token: "fresh-token",
      })
    );
    await assertFails(
      setDoc(
        doc(anonymous("lonekid"), "users/lonekid/private/fcm"),
        { token: "fresh-token" },
        { merge: true }
      )
    );
  });

  /**
   * Load-bearing: `clearFCMToken` runs on sign-out, and a sticky post-revocation child is
   * precisely the session that most needs to be able to drop a token it should not hold.
   * Denying delete would strand the very document this rule exists to prevent.
   */
  it("still lets an unconsented child DELETE their token doc", async () => {
    await assertSucceeds(
      deleteDoc(doc(anonymous("lonekid"), "users/lonekid/private/fcm"))
    );
  });

  it("still lets an unconsented child READ their own token doc", async () => {
    await assertSucceeds(getDoc(doc(anonymous("lonekid"), "users/lonekid/private/fcm")));
  });

  /**
   * FR-53(c): the family-trip categories stay available to a CONSENTED child, which means
   * their device must be able to register a token. If this ever fails, consent has stopped
   * buying the child anything.
   */
  it("allows a CONSENTED child to write their token doc", async () => {
    await assertSucceeds(
      setDoc(doc(anonymous("famkid"), "users/famkid/private/fcm"), { token: "fresh" })
    );
  });

  it("leaves adults alone (regression)", async () => {
    await assertSucceeds(
      setDoc(doc(registered("adult"), "users/adult/private/fcm"), { token: "fresh" })
    );
    // No users/{uid} doc at all: a missing flag means adult, and the guard must not
    // error-deny on the absent document.
    await assertSucceeds(
      setDoc(doc(registered("docless"), "users/docless/private/fcm"), { token: "t" })
    );
  });

  /**
   * FR-73 is about the push identifier only. Re-gating `contact` here would silently change
   * an unrelated F-5a surface, so the child's contact doc must behave exactly as before.
   */
  it("does not touch the contact doc (F-5a surface unchanged)", async () => {
    await assertSucceeds(
      setDoc(doc(anonymous("lonekid"), "users/lonekid/private/contact"), {
        email: "parent2@example.com",
      })
    );
    await assertSucceeds(
      getDoc(doc(anonymous("lonekid"), "users/lonekid/private/contact"))
    );
  });

  it("nobody writes or reads another user's token doc (regression)", async () => {
    await assertFails(
      setDoc(doc(registered("adult"), "users/famkid/private/fcm"), { token: "stolen" })
    );
    await assertFails(getDoc(doc(registered("adult"), "users/famkid/private/fcm")));
    await assertFails(
      deleteDoc(doc(registered("adult"), "users/lonekid/private/fcm"))
    );
  });

  /** The `private/` allowlist is unchanged: only `contact` and `fcm` are reachable. */
  it("keeps every other private doc id closed (regression)", async () => {
    await assertFails(
      setDoc(doc(registered("adult"), "users/adult/private/guardianship"), { x: 1 })
    );
    await assertFails(
      setDoc(doc(registered("adult"), "users/adult/private/lastLoginLocationData"), { x: 1 })
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

  // Owner device log 2026-09-08 ("getUser failed … Missing or insufficient permissions", one
  // line per uid at launch): those uids were since-DELETED accounts still named by resolved
  // rows in `families/{id}/pending`. This pins WHY a client sees that as a permission error
  // and never as "not found": the peer branch dereferences `resource.data`, and on a missing
  // document `resource` is null, so the rule errors — reported as PERMISSION_DENIED. A client
  // therefore cannot tell "deleted" from "hidden" and must not read docs it has no reason to
  // (`FamilyRepository.pendingUserIdsToHydrate`). The self clause short-circuits first, so a
  // fresh account still reads its own not-yet-written doc — the other half of the contract.
  it("a peer read of a uid with NO user doc is denied, not not-found (deleted requester)", async () => {
    await assertFails(getDoc(doc(registered("parent"), "users/deletedRequester")));
    await assertFails(getDoc(doc(registered("stranger"), "users/deletedRequester")));
    await assertSucceeds(getDoc(doc(registered("deletedRequester"), "users/deletedRequester")));
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

describe("FR-48: public_lifetime_stats is registered-only for peers", () => {
  beforeEach(async () => {
    await seed({
      "users/grown": { userName: "Grown" },
      "public_lifetime_stats/grown": { platesFound: 7 },
    });
  });

  it("denies an anonymous caller reading public_lifetime_stats for another account", async () => {
    await assertFails(getDoc(doc(anonymous("anon1"), "public_lifetime_stats/grown")));
  });

  it("allows a registered caller reading public_lifetime_stats for another account", async () => {
    await assertSucceeds(getDoc(doc(registered("stranger"), "public_lifetime_stats/grown")));
  });
});

// FR-71 (F-27, COPPA v3): usernames/{usernameLower} moves from FR-48's "registered-only" to
// deny for EVERYONE — self included, anonymous included. There is no more "for peers" carve
// -out to test; the collection has exactly one live reader now (the searchUsers callable,
// via the Admin SDK, which never goes through these rules at all).
describe("FR-71: usernames index is closed to every client read", () => {
  beforeEach(async () => {
    await seed({
      "users/grown": { userName: "Grown" },
      "usernames/grown": { userId: "grown" },
    });
  });

  it("denies an anonymous caller reading the usernames index", async () => {
    await assertFails(getDoc(doc(anonymous("anon1"), "usernames/grown")));
  });

  it("denies a registered caller reading the usernames index (closed by FR-71 — was allowed under FR-48)", async () => {
    await assertFails(getDoc(doc(registered("stranger"), "usernames/grown")));
  });

  it("denies the owner's own account reading its own usernames row — no self-carve-out was ever added", async () => {
    await assertFails(getDoc(doc(registered("grown"), "usernames/grown")));
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
    // usernames maps a name straight to a uid — closed to every client read (FR-71; was
    // registration-gated under FR-48 before v3, so a consented child was already excluded
    // either way — this pin now rests on the stronger deny-all rule).
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
        userName: "Named_v2",
      })
    );
  });
});

// ---------------------------------------------------------------------------
// FR-80 (F-36, fresh-audit finding M-2) — username content policy is enforced
// server-side, not just by the client's `UsernameProfanityFilter` /
// `UsernameValidation` (Core/Utilities/UsernameProfanityFilter.swift). Every real
// write goes through `FirebaseAuthService.saveUserDataToFirestore`'s direct
// `setData(merge:true)` — there is no callable in this path — so this rules block
// is the only boundary a modified client cannot bypass.
//
// The profanity check mirrors the client filter's blocklist, single-valued leet
// substitution, and separator-stripping tolerance -- but deliberately no stronger
// (FR-80's no-multi-candidate-expansion decision, owner-reaffirmed 2026-08-26): a
// known client-side gap like "f4ck" (the leet map has no substitute for 'u', so it
// normalizes to "fack", not "fuck") is preserved here on purpose, and is pinned by
// a test below so nobody "fixes" the server without the client agreeing first.
// ---------------------------------------------------------------------------

describe("FR-80: username format is validated server-side on write", () => {
  it("denies create with a username under 3 characters", async () => {
    await assertFails(
      setDoc(doc(registered("shortu"), "users/shortu"), { userName: "ab" })
    );
  });

  it("denies create with a username over 24 characters", async () => {
    await assertFails(
      setDoc(doc(registered("longu"), "users/longu"), { userName: "a".repeat(25) })
    );
  });

  it("allows create at the 3-character and 24-character boundaries", async () => {
    await assertSucceeds(
      setDoc(doc(registered("minlen"), "users/minlen"), { userName: "abc" })
    );
    await assertSucceeds(
      setDoc(doc(registered("maxlen"), "users/maxlen"), { userName: "a".repeat(24) })
    );
  });

  it("denies create with characters outside the allowed charset", async () => {
    await assertFails(
      setDoc(doc(registered("spacey"), "users/spacey"), { userName: "cool name" })
    );
    await assertFails(
      setDoc(doc(registered("atsign"), "users/atsign"), { userName: "kid@example.com" })
    );
    await assertFails(
      setDoc(doc(registered("emoji1"), "users/emoji1"), { userName: "roadtrip🚗fan" })
    );
  });

  it("denies create with a bare-digit phone-shaped username", async () => {
    await assertFails(
      setDoc(doc(registered("phone1"), "users/phone1"), { userName: "5551234567" })
    );
  });

  it("denies create with a separator-grouped phone-shaped username", async () => {
    await assertFails(
      setDoc(doc(registered("phone2"), "users/phone2"), { userName: "555-123-4567" })
    );
  });

  it("allows create with a short numeric username that is not phone-shaped", async () => {
    await assertSucceeds(
      setDoc(doc(registered("num1"), "users/num1"), { userName: "123" })
    );
  });

  it("denies create with a plain blocked term, case-insensitively", async () => {
    await assertFails(
      setDoc(doc(registered("prof1"), "users/prof1"), { userName: "fuck" })
    );
    await assertFails(
      setDoc(doc(registered("prof2"), "users/prof2"), { userName: "xFUCKx" })
    );
  });

  it("denies create with a leet-obfuscated blocked term (client-filter parity)", async () => {
    await assertFails(
      setDoc(doc(registered("prof3"), "users/prof3"), { userName: "assh0le" })
    );
  });

  it("denies create with a separator-broken blocked term (client-filter parity)", async () => {
    await assertFails(
      setDoc(doc(registered("prof4"), "users/prof4"), { userName: "s-h-i-t" })
    );
  });

  it("allows the known leet gap the client filter also allows (no-expansion pin, owner-reaffirmed 2026-08-26)", async () => {
    await assertSucceeds(
      setDoc(doc(registered("gap1"), "users/gap1"), { userName: "f4ckable" })
    );
  });

  it("allows create with an ordinary valid username", async () => {
    await assertSucceeds(
      setDoc(doc(registered("good1"), "users/good1"), { userName: "RoadTripper_42" })
    );
  });

  it("denies update changing username to an invalid value", async () => {
    await seed({ "users/renamer": { userName: "Valid1" } });
    await assertFails(
      updateDoc(doc(registered("renamer"), "users/renamer"), { userName: "@@" })
    );
  });

  it("allows update changing username to a new valid value", async () => {
    await seed({ "users/renamer2": { userName: "Valid1" } });
    await assertSucceeds(
      updateDoc(doc(registered("renamer2"), "users/renamer2"), { userName: "Valid2" })
    );
  });

  it("allows an unrelated update without re-validating a pre-existing non-conforming username (pre-release: no migration)", async () => {
    await seed({ "users/legacy1": { userName: "x", avatarId: "old-avatar" } });
    await assertSucceeds(
      updateDoc(doc(registered("legacy1"), "users/legacy1"), { avatarId: "new-avatar" })
    );
  });

  it("allows resaving a pre-existing non-conforming username unchanged (grandfathered)", async () => {
    await seed({ "users/legacy2": { userName: "x" } });
    await assertSucceeds(
      setDoc(doc(registered("legacy2"), "users/legacy2"), { userName: "x", lastUpdated: new Date() }, { merge: true })
    );
  });
});

// ---------------------------------------------------------------------------
// FR-84 (F-41) — parent-initiated device transfer
// ---------------------------------------------------------------------------

/**
 * Two boundaries, which are separate concerns that happen to arrive together.
 *
 * (1) `device_transfer_codes` — a row here is a BEARER CREDENTIAL for one named consented
 *     child's account: whoever presents the code to `redeemDeviceTransferCode` receives a
 *     custom token for that uid. So it is deliberately NOT a third `share_codes` type.
 *     `share_codes` is readable by the whole named family (FR-67) and writable by any
 *     registered non-child; either property applied here would be a hole, the first being
 *     FR-84 future-item (iii)'s child-to-child account-sharing vector handed out by the
 *     ruleset itself.
 *
 * (2) `isRegisteredAccount()` now excludes `custom` as well as `anonymous`. Without that, a
 *     transfer would PROMOTE the child it moves: a `custom` session would satisfy every
 *     registration gate FR-85(a) deliberately declined to widen for consented children. The
 *     matrix below re-runs FR-85's own question against the new provider — a transferred child
 *     must do exactly what an anonymous consented child could do, and nothing more.
 */
describe("FR-84: device transfer codes and the custom-token provider", () => {
  beforeEach(async () => {
    await seed({
      "users/parent": { userName: "Parent", activeFamilyId: "fam1" },
      "users/sibling": { userName: "Sib", isChildAccount: true, activeFamilyId: "fam1" },
      "users/famkid": { userName: "Kid", isChildAccount: true, activeFamilyId: "fam1" },
      "users/stranger": { userName: "Stranger" },
      "families/fam1": { name: "Fam", creatorId: "parent", status: "active" },
      "families/fam1/members/parent": { role: "creator" },
      "families/fam1/members/famkid": { role: "member", isChild: true },
      "families/fam1/members/sibling": { role: "member", isChild: true },
      "device_transfer_codes/t1": {
        code: "TRN111",
        childUserId: "famkid",
        familyId: "fam1",
        createdBy: "parent",
        expiresAtMillis: Date.now() + 900000,
        isRevoked: false,
      },
    });
  });

  it("lets the minting guardian re-read the code they are reading aloud", async () => {
    await assertSucceeds(getDoc(doc(registered("parent"), "device_transfer_codes/t1")));
  });

  /** The vector FR-84 future-item (iii) names, closed by the rules rather than by a callable. */
  it("denies a SIBLING in the same family — this is not a share code", async () => {
    await assertFails(getDoc(doc(anonymous("sibling"), "device_transfer_codes/t1")));
  });

  it("denies the child the code is FOR (they redeem through the callable, never the doc)", async () => {
    await assertFails(getDoc(doc(anonymous("famkid"), "device_transfer_codes/t1")));
  });

  it("denies a stranger and an anonymous caller", async () => {
    await assertFails(getDoc(doc(registered("stranger"), "device_transfer_codes/t1")));
    await assertFails(getDoc(doc(anonymous("anon1"), "device_transfer_codes/t1")));
  });

  /**
   * Enumeration is denied OUTRIGHT, not merely scoped as FR-67 scoped `share_codes`. There a
   * harvest yields invites somebody still has to approve; here it would yield live account
   * credentials, so no query shape is worth permitting — including the creator's own, which
   * needs no listing because the mint callable returns the code.
   */
  it("denies listing to everyone, including the creator", async () => {
    await assertFails(getDocs(collection(registered("parent"), "device_transfer_codes")));
    await assertFails(
      getDocs(
        query(
          collection(registered("parent"), "device_transfer_codes"),
          where("createdBy", "==", "parent")
        )
      )
    );
    await assertFails(getDocs(collection(registered("stranger"), "device_transfer_codes")));
  });

  it("denies every client write — the callables are the only writers", async () => {
    await assertFails(
      setDoc(doc(registered("parent"), "device_transfer_codes/forged"), {
        code: "FORGED",
        childUserId: "famkid",
        familyId: "fam1",
        createdBy: "parent",
        isRevoked: false,
      })
    );
    await assertFails(
      updateDoc(doc(registered("parent"), "device_transfer_codes/t1"), { isRevoked: true })
    );
    await assertFails(deleteDoc(doc(registered("parent"), "device_transfer_codes/t1")));
  });

  /**
   * A child who cannot read the collection must not be able to mint into it either — the
   * sibling's route to their brother's account, tried from the write side.
   */
  it("denies a consented child creating a transfer code for another child", async () => {
    await assertFails(
      setDoc(doc(anonymous("sibling"), "device_transfer_codes/sneaky"), {
        code: "SNEAK1",
        childUserId: "famkid",
        familyId: "fam1",
        createdBy: "sibling",
        isRevoked: false,
      })
    );
  });

  describe("a transferred child gains nothing an anonymous consented child lacked", () => {
    it("still cannot create a family", async () => {
      await assertFails(
        setDoc(doc(customToken("famkid"), "families/newfam"), {
          name: "Mine",
          creatorId: "famkid",
          status: "active",
        })
      );
    });

    it("still cannot create a share code", async () => {
      await assertFails(
        setDoc(doc(customToken("famkid"), "share_codes/kidcode"), {
          type: "friend",
          createdBy: "famkid",
          isRevoked: false,
        })
      );
    });

    it("still cannot read a NON-family peer's user doc", async () => {
      await seed({ "users/outsiderAdult": { userName: "Outsider" } });
      await assertFails(getDoc(doc(customToken("famkid"), "users/outsiderAdult")));
    });

    /**
     * The other direction, and the one a hardening pass breaks by accident: FR-85(a)'s
     * `callerIsConsentedChildMemberOf` keys off the child flag and real membership, never the
     * provider, so the roster must still hydrate to names. An implementer who "fixed" the
     * custom provider by tightening that helper instead would silently restore the raw-uid
     * degradation FR-93 exists to prevent.
     */
    it("STILL reads their own family's peer docs — FR-85 is not provider-keyed", async () => {
      await assertSucceeds(getDoc(doc(customToken("famkid"), "users/parent")));
    });

    it("still reads its own user doc", async () => {
      await assertSucceeds(getDoc(doc(customToken("famkid"), "users/famkid")));
    });

    it("cannot read a device transfer code, even for itself", async () => {
      await assertFails(getDoc(doc(customToken("famkid"), "device_transfer_codes/t1")));
    });
  });
});

// ---------------------------------------------------------------------------
// §3.1.1 item 19 — account-scoped trip discovery
// ---------------------------------------------------------------------------

/**
 * The first recursive-wildcard block in `firestore.rules`:
 *
 *     match /{path=**}/members/{memberId} {
 *       allow read: if isSignedIn() && resource.data.memberUserId == uid();
 *       allow create, update, delete: if false;
 *     }
 *
 * It authorizes exactly one query — `collectionGroup("members").where("memberUserId","==",me)`
 * — which is how a trip finally follows an account to a second device. Three things have to
 * stay true for that to be safe, and each has tests below:
 *
 *  1. THE FILTER IS THE SECURITY PROPERTY. `resource.data.memberUserId == uid()` is evaluated
 *     per document, so an UNFILTERED collection-group query, or one naming another uid, is
 *     denied outright. There is no enumeration.
 *  2. THE WILDCARD IS PATH-AGNOSTIC, so it is also evaluated against
 *     `families/{familyId}/members/{memberId}`. Family member docs carry no `memberUserId`
 *     (`functions/src/family.ts`) and the field is deliberately NOT named `userId`, which is
 *     the repo convention elsewhere — a family member doc carrying `userId` is still
 *     unreadable through the block, and that is the assertion documenting the name.
 *  3. THE WRITE SIDE MUST NEVER BE RELAXED — and this block does NOT enforce that. Firestore
 *     rules union their allow expressions and have no deny, so the `allow create, update,
 *     delete: if false` in the block contributes nothing against a permissive rule elsewhere.
 *     What actually keeps the read rule safe is a standing invariant: every `members` write
 *     path in this file is server-only, so no client can forge `memberUserId`. The write
 *     denials below pin the invariant while it holds (on the trip path, the family path and an
 *     arbitrary third path); they would NOT catch someone adding a permissive rule under a new
 *     `members` collection. The second half of the invariant — that no document outside
 *     `trip_sessions/{id}/members` may carry `memberUserId` — has an honest positive pin below:
 *     a seeded doc at an arbitrary path carrying `memberUserId` IS readable by that uid. That
 *     test documents the real behaviour, and it is the one that would fail loudly if anyone
 *     came to believe the wildcard's write denials are a containment boundary.
 */
describe("item 19: collection-group trip discovery on members.memberUserId", () => {
  beforeEach(async () => {
    await seed({
      // Two of MINE (one created, one joined) and one that is not.
      "trip_sessions/mine1": { name: "Solo", createdBy: "me" },
      "trip_sessions/mine1/members/me": { role: "owner", memberUserId: "me" },
      "trip_sessions/mine2": { name: "Joined", createdBy: "other" },
      "trip_sessions/mine2/members/me": { role: "member", memberUserId: "me" },
      "trip_sessions/mine2/members/other": { role: "owner", memberUserId: "other" },
      "trip_sessions/theirs": { name: "Not mine", createdBy: "other" },
      "trip_sessions/theirs/members/other": { role: "owner", memberUserId: "other" },
      // The other `members` collection in the database. `stranger` is NOT in fam1, so the
      // path-scoped family rule cannot be what denies them — only the wildcard is in play.
      "families/fam1": { name: "Fam", status: "active" },
      "families/fam1/members/famkid": { role: "scout", userId: "stranger" },
    });
  });

  it("allows a signed-in user to query their OWN membership across every trip", async () => {
    const snap = await assertSucceeds(
      getDocs(
        query(collectionGroup(registered("me"), "members"), where("memberUserId", "==", "me"))
      )
    );
    // Only their own rows come back — never a co-member's, never a family doc.
    expect(
      (snap as { docs: { ref: { path: string } }[] }).docs.map((d) => d.ref.path).sort()
    ).toEqual(["trip_sessions/mine1/members/me", "trip_sessions/mine2/members/me"]);
  });

  it("denies the UNFILTERED collection-group query — the where clause IS the control", async () => {
    await assertFails(getDocs(collectionGroup(registered("me"), "members")));
  });

  it("denies the same query filtered on ANOTHER user's uid", async () => {
    await assertFails(
      getDocs(
        query(
          collectionGroup(registered("me"), "members"),
          where("memberUserId", "==", "other")
        )
      )
    );
  });

  it("denies a direct get of a member doc that names someone else", async () => {
    await assertFails(getDoc(doc(registered("me"), "trip_sessions/theirs/members/other")));
  });

  it("denies an anonymous-but-unauthenticated caller outright", async () => {
    await assertFails(
      getDocs(
        query(
          collectionGroup(testEnv.unauthenticatedContext().firestore() as unknown as Firestore, "members"),
          where("memberUserId", "==", "me")
        )
      )
    );
  });

  /**
   * The assertion that documents the field NAME. `userId` is this repo's convention
   * (participant_prefs.userId, private.userId), and had the field been called that, a family
   * member doc carrying a `userId` would have become self-readable through this block by
   * accident. It carries one here deliberately, and is still denied.
   */
  it("does not make a family member doc readable, even one carrying a userId field", async () => {
    await assertFails(getDoc(doc(registered("stranger"), "families/fam1/members/famkid")));
    const snap = await assertSucceeds(
      getDocs(
        query(
          collectionGroup(registered("stranger"), "members"),
          where("memberUserId", "==", "stranger")
        )
      )
    );
    expect((snap as { docs: unknown[] }).docs).toHaveLength(0);
  });

  it("denies client CREATES under any members subcollection, with or without a forged field", async () => {
    const forged = { role: "owner", memberUserId: "me" };
    await assertFails(setDoc(doc(registered("me"), "trip_sessions/fresh/members/me"), forged));
    await assertFails(setDoc(doc(registered("me"), "families/fam1/members/me"), forged));
    // An arbitrary third path. This one passes by DEFAULT DENY — no rule permits it — not
    // because the wildcard block denies writes; rules union allows and cannot deny. It pins
    // the standing invariant (no client write path under any `members` collection) for as long
    // as the invariant holds, and would NOT catch a permissive rule added elsewhere later.
    await assertFails(setDoc(doc(registered("me"), "widgets/w1/members/me"), forged));
  });

  /**
   * THE HONEST PIN, and the counterpart to the denial test above. The wildcard is
   * path-agnostic, so the read rule is satisfied by ANY document under ANY collection named
   * `members` that carries `memberUserId == me` — not only by trip member docs. The denial
   * test above passes today by DEFAULT DENY (no rule anywhere permits that create), which is
   * the invariant that makes the feature safe; it is not something this block enforces, since
   * rules union allow expressions and have no deny.
   *
   * This asserts what the rules actually do, so the invariant has to be maintained where it
   * really lives: no rule may ever let a client write under a `members` collection, and no
   * server code may ever stamp `memberUserId` outside `trip_sessions/{id}/members`.
   */
  it("DOCUMENTS THE REAL BEHAVIOUR: any doc anywhere carrying memberUserId == me is readable", async () => {
    // Written with rules disabled — no client can create this today, which is the point.
    await seed({ "widgets/w1/members/forged": { memberUserId: "me" } });

    await assertSucceeds(getDoc(doc(registered("me"), "widgets/w1/members/forged")));
    const snap = await assertSucceeds(
      getDocs(
        query(collectionGroup(registered("me"), "members"), where("memberUserId", "==", "me"))
      )
    );
    expect(
      (snap as { docs: { ref: { path: string } }[] }).docs.map((d) => d.ref.path)
    ).toContain("widgets/w1/members/forged");

    // Still scoped to the caller: the same forged doc is invisible to anyone else.
    await assertFails(getDoc(doc(registered("stranger"), "widgets/w1/members/forged")));
  });

  it("denies client UPDATES and DELETES of an existing member doc, including one's own", async () => {
    await assertFails(
      updateDoc(doc(registered("me"), "trip_sessions/mine1/members/me"), {
        memberUserId: "other",
      })
    );
    await assertFails(
      updateDoc(doc(registered("me"), "trip_sessions/mine1/members/me"), { role: "member" })
    );
    await assertFails(deleteDoc(doc(registered("me"), "trip_sessions/mine1/members/me")));
  });

  it("REGRESSION: the path-scoped roster read still works for a member and still fails for a stranger", async () => {
    // What TripInviteRepository's roster listener needs. A collection-group query is NOT
    // authorized by this block, which is why the wildcard had to be added beside it.
    await assertSucceeds(getDoc(doc(registered("me"), "trip_sessions/mine2/members/other")));
    await assertSucceeds(getDocs(collection(registered("me"), "trip_sessions/mine2/members")));
    await assertFails(getDocs(collection(registered("stranger"), "trip_sessions/mine2/members")));
  });

  it("REGRESSION: trip_sessions/{id} get is unchanged — creator and member yes, stranger no", async () => {
    await assertSucceeds(getDoc(doc(registered("other"), "trip_sessions/theirs")));
    await assertSucceeds(getDoc(doc(registered("me"), "trip_sessions/mine2")));
    await assertFails(getDoc(doc(registered("stranger"), "trip_sessions/mine1")));
  });
});

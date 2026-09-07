/**
 * COPPA F-5b end-to-end enforcement in `userSearch.ts`, run against the REAL exported
 * handlers (`CloudFunction.run` is the raw handler in firebase-functions v1) with
 * `firebase-admin` replaced by a `FakeFirestore`.
 *
 * FR-11 — the index syncers treat a child exactly like a non-registered account: they never
 * create `usernames` / `user_lookup_email` / `user_lookup_phone` entries, and they remove
 * any that already exist. The load-bearing case is the **purge-failure backstop** (§14,
 * FR-4): the flag-set batch's follow-on purge is deliberately non-atomic, so this trigger —
 * the one place every `users/{uid}` write funnels through — must repair the residue on the
 * child's next profile write. Those tests seed the store as if the purge never ran.
 *
 * FR-9 / FR-24 — `searchUsers` itself: a child is invisible on every modality *including*
 * the raw `userNameLower` prefix scan (which reads user docs directly and so survives index
 * removal), and a child caller gets an empty result set.
 *
 * FR-71 (F-27, COPPA v3) extends this file with two more properties `searchUsers` must hold:
 *  - the `user_search` rate limit (`consumeInviteRateLimit`, same primitive as the invite
 *    callables) — exhaustion, per-caller isolation, window recovery;
 *  - the child-caller short-circuit runs BEFORE `classifySearchQuery` ever sees the query
 *    string, and before the rate-limit budget is touched at all. The `./userSearchCore`
 *    partial mock below records every `classifySearchQuery` call (delegating straight
 *    through to the real implementation, same "spy that calls straight through" shape as
 *    `familyJoinRequestDuplicates.test.ts`'s provisional-account mock) so that ordering is a
 *    property of the call graph, not inferred from the (already-empty, already-pinned)
 *    result shape.
 */

import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";

const holder = vi.hoisted(() => ({ db: undefined as any, classifyCalls: [] as string[] }));

vi.mock("firebase-admin", async () => {
  const { FakeFirestore } = await import("./testSupport/fakeFirestore");
  holder.db = new FakeFirestore();
  const firestore: any = () => holder.db;
  firestore.FieldValue = {
    serverTimestamp: () => "__serverTimestamp__",
    delete: () => "__delete__",
  };
  firestore.Timestamp = {
    fromMillis: (ms: number) => ({ toMillis: () => ms }),
    fromDate: (date: Date) => ({ toMillis: () => date.getTime() }),
  };
  return { default: { firestore }, firestore };
});

// FR-71: records every call `userSearch.ts` makes into `classifySearchQuery`, without
// changing its behavior — real classification still runs via `actual`. This is the "unit
// seam" the child-caller ordering test needs: `classifySearchQuery` never touches Firestore,
// so there is no read/write on the FakeFirestore to observe its absence with directly.
vi.mock("./userSearchCore", async (importOriginal) => {
  const actual = await importOriginal<typeof import("./userSearchCore")>();
  return {
    ...actual,
    classifySearchQuery: (query: string) => {
      holder.classifyCalls.push(query);
      return actual.classifySearchQuery(query);
    },
  };
});

import type { FakeFirestore } from "./testSupport/fakeFirestore";
import {
  onUserContactSearchIndexSync,
  onUserProfileSearchIndexSync,
  searchUsers,
} from "./userSearch";
import {
  USER_SEARCH_RATE_LIMITED_MESSAGE,
  INVITE_RATE_LIMITED_REASON,
  INVITE_RATE_LIMIT_COLLECTION,
  INVITE_RATE_LIMIT_WINDOW_MS,
  USER_SEARCH_MAX_PER_WINDOW,
  inviteRateLimitDocId,
} from "./inviteRateLimitCore";

function db(): FakeFirestore {
  return holder.db as FakeFirestore;
}

function rateLimitCounter(uid: string) {
  return db().store.get(`${INVITE_RATE_LIMIT_COLLECTION}/${inviteRateLimitDocId("user_search", uid)}`);
}

interface Snap {
  exists: boolean;
  data: () => Record<string, unknown> | undefined;
}

function snap(data: Record<string, unknown> | null): Snap {
  return { exists: data !== null, data: () => data ?? undefined };
}

async function fireProfileWrite(
  userId: string,
  before: Record<string, unknown> | null,
  after: Record<string, unknown> | null
): Promise<void> {
  await (onUserProfileSearchIndexSync as unknown as {
    run: (change: unknown, context: unknown) => Promise<void>;
  }).run({ before: snap(before), after: snap(after) }, { params: { userId } });
}

async function fireContactWrite(
  userId: string,
  before: Record<string, unknown> | null,
  after: Record<string, unknown> | null
): Promise<void> {
  await (onUserContactSearchIndexSync as unknown as {
    run: (change: unknown, context: unknown) => Promise<void>;
  }).run({ before: snap(before), after: snap(after) }, { params: { userId } });
}

interface SearchResponse {
  results: Array<{ userId: string; userName: string; matchedField: string }>;
}

async function runSearch(callerId: string, query: string): Promise<SearchResponse> {
  return (searchUsers as unknown as {
    run: (data: unknown, context: unknown) => Promise<SearchResponse>;
  }).run(
    { query },
    {
      auth: {
        uid: callerId,
        token: { firebase: { sign_in_provider: "password" } },
      },
    }
  );
}

/** Index rows exactly as a successful FR-4 purge would have removed them. */
function seedStaleIndexResidue(userId: string): void {
  db().seed(`usernames/kidracer`, { userId });
  db().seed(`user_lookup_email/kid@example.com`, { userId });
  db().seed(`user_lookup_phone/p12035551111`, {
    userId,
    phoneE164: "+12035551111",
  });
}

function indexRows(): string[] {
  return db().docPathsMatching(
    (path) =>
      path.startsWith("usernames/") ||
      path.startsWith("user_lookup_email/") ||
      path.startsWith("user_lookup_phone/")
  );
}

beforeEach(() => {
  db().store.clear();
  db().writeCount = 0;
  holder.classifyCalls = [];
});

afterEach(() => {
  vi.useRealTimers();
});

describe("FR-11: index syncers exclude children (profile trigger)", () => {
  it("creates no index entries for a child, on a first-ever profile write", async () => {
    const child = {
      userName: "KidRacer",
      isRegistered: true,
      isChildAccount: true,
      email: "kid@example.com",
      phoneNumber: "+12035551111",
    };
    db().seed("users/kid", child);

    await fireProfileWrite("kid", null, child);

    expect(indexRows()).toEqual([]);
  });

  it("PURGE-FAILURE BACKSTOP: removes residue the FR-4 purge left behind", async () => {
    // Contact identifiers live in private/contact after FR-43, so the trigger has to
    // resolve the delete keys from there — exactly like the FR-4 purge does.
    db().seed("users/kid", {
      userName: "KidRacer",
      userNameLower: "kidracer",
      isRegistered: true,
      isChildAccount: true,
      activeFamilyId: "fam1",
    });
    db().seed("users/kid/private/contact", {
      email: "kid@example.com",
      emailLower: "kid@example.com",
      phoneNumber: "+12035551111",
      phoneE164: "+12035551111",
    });
    seedStaleIndexResidue("kid");
    expect(indexRows()).toHaveLength(3);

    await fireProfileWrite("kid", null, db().store.get("users/kid")!);

    expect(indexRows()).toEqual([]);
  });

  it("removes residue for a provisional child with legacy top-level contact fields", async () => {
    const child = {
      userName: "KidRacer",
      userNameLower: "kidracer",
      isRegistered: true,
      isChildAccount: true,
      email: "kid@example.com",
      phoneNumber: "+12035551111",
    };
    db().seed("users/kid", child);
    seedStaleIndexResidue("kid");

    await fireProfileWrite("kid", null, child);

    expect(indexRows()).toEqual([]);
  });

  it("is idempotent — a second write finds nothing left to do", async () => {
    const child = {
      userName: "KidRacer",
      isRegistered: true,
      isChildAccount: true,
    };
    db().seed("users/kid", child);
    db().seed("users/kid/private/contact", {
      emailLower: "kid@example.com",
      phoneE164: "+12035551111",
    });
    seedStaleIndexResidue("kid");

    await fireProfileWrite("kid", null, child);
    expect(indexRows()).toEqual([]);

    // Re-running must never resurrect an entry (the trigger fires again on its own
    // userNameLower stamp, so this is the real production sequence, not a synthetic one).
    await fireProfileWrite("kid", child, child);
    expect(indexRows()).toEqual([]);
  });

  it("leaves contact lookup rows owned by SOMEONE ELSE alone", async () => {
    // syncContactLookupIndexes deletes only rows whose `userId` matches. (The `usernames`
    // delete in the not-registered branch is unconditional — pre-existing behavior shared
    // with anonymous accounts, and safe because usernames are unique-per-owner.)
    const child = {
      isRegistered: true,
      isChildAccount: true,
      email: "kid@example.com",
    };
    db().seed("users/kid", child);
    db().seed("user_lookup_email/kid@example.com", { userId: "someone-else" });

    await fireProfileWrite("kid", null, child);

    expect(indexRows()).toEqual(["user_lookup_email/kid@example.com"]);
  });

  it("regression: an adult still gets username + contact index entries", async () => {
    const adult = {
      userName: "Grown",
      isRegistered: true,
      email: "grown@example.com",
      phoneNumber: "+12035552222",
    };
    db().seed("users/adult", adult);

    await fireProfileWrite("adult", null, adult);

    expect(indexRows()).toEqual([
      "user_lookup_email/grown@example.com",
      "user_lookup_phone/p12035552222",
      "usernames/grown",
    ]);
    expect(db().store.get("usernames/grown")).toMatchObject({ userId: "adult" });
  });

  it("regression: an explicit isChildAccount:false adult is unaffected", async () => {
    const adult = { userName: "Grown", isRegistered: true, isChildAccount: false };
    db().seed("users/adult", adult);

    await fireProfileWrite("adult", null, adult);

    expect(indexRows()).toEqual(["usernames/grown"]);
  });
});

describe("FR-11: index syncers exclude children (contact trigger)", () => {
  it("does not re-create lookup rows the profile syncer just removed", async () => {
    db().seed("users/kid", {
      userName: "KidRacer",
      isRegistered: true,
      isChildAccount: true,
    });

    await fireContactWrite("kid", null, {
      email: "kid@example.com",
      emailLower: "kid@example.com",
      phoneNumber: "+12035551111",
      phoneE164: "+12035551111",
    });

    expect(indexRows()).toEqual([]);
  });

  it("removes existing lookup rows when the contact doc is rewritten for a child", async () => {
    db().seed("users/kid", { isRegistered: true, isChildAccount: true });
    db().seed("user_lookup_email/kid@example.com", { userId: "kid" });
    db().seed("user_lookup_phone/p12035551111", { userId: "kid" });

    await fireContactWrite("kid", null, {
      email: "kid@example.com",
      emailLower: "kid@example.com",
      phoneNumber: "+12035551111",
      phoneE164: "+12035551111",
    });

    expect(indexRows()).toEqual([]);
  });

  it("regression: an adult contact write still creates lookup rows", async () => {
    db().seed("users/adult", { isRegistered: true });

    await fireContactWrite("adult", null, {
      email: "grown@example.com",
      emailLower: "grown@example.com",
    });

    expect(indexRows()).toEqual(["user_lookup_email/grown@example.com"]);
  });
});

describe("FR-9 / FR-24: searchUsers end to end", () => {
  beforeEach(() => {
    db().seed("users/kid", {
      userName: "KidRacer",
      userNameLower: "kidracer",
      isRegistered: true,
      isChildAccount: true,
      activeFamilyId: "fam1",
      email: "kid@example.com",
      emailLower: "kid@example.com",
      privacy: { emailSearchable: true, phoneSearchable: true },
    });
    db().seed("users/grown", {
      userName: "KidRacerSenior",
      userNameLower: "kidracersenior",
      isRegistered: true,
      privacy: { emailSearchable: true },
    });
    db().seed("users/seeker", { userName: "Seeker", isRegistered: true });
  });

  it("hides a child from the raw userNameLower PREFIX scan", async () => {
    // The child owns no `usernames` index row, but `userNameLower` is still stamped on the
    // user doc — this is exactly the hole index removal alone cannot close (§8.4).
    const response = await runSearch("seeker", "kidrac");
    expect(response.results.map((hit) => hit.userId)).toEqual(["grown"]);
  });

  it("hides a child from the exact usernames-index lookup", async () => {
    db().seed("usernames/kidracer", { userId: "kid" }); // stale row, e.g. purge failed
    const response = await runSearch("seeker", "kidracer");
    // "kidracersenior" legitimately prefix-matches; the child must not be there at all.
    expect(response.results.map((hit) => hit.userId)).toEqual(["grown"]);
  });

  it("hides a child from the email modality despite emailSearchable: true", async () => {
    db().seed("user_lookup_email/kid@example.com", { userId: "kid" });
    const response = await runSearch("seeker", "kid@example.com");
    expect(response.results).toEqual([]);
  });

  it("FR-24: a child caller gets zero hits even for a perfectly searchable adult", async () => {
    const response = await runSearch("kid", "kidracersenior");
    expect(response.results).toEqual([]);
  });

  it("FR-24: the empty child search still audits like any other search", async () => {
    await runSearch("kid", "kidracersenior");
    const rows = db()
      .docPathsMatching((path) => path.startsWith("audit_logs/"))
      .map((path) => db().store.get(path)!);
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({
      eventType: "user_search_performed",
      actorId: "kid",
      metadata: { resultCount: 0 },
    });
    // uid-only: no plaintext query anywhere in the row.
    expect(JSON.stringify(rows[0])).not.toContain("kidracersenior");
  });

  it("regression: an adult caller still finds an adult target", async () => {
    const response = await runSearch("seeker", "kidracersenior");
    expect(response.results.map((hit) => hit.userId)).toEqual(["grown"]);
  });
});

// FR-48 (COPPA F-11): username search honors a per-user searchability opt-out. The three
// tests below exercise every path `searchByUsername` has — exact via the `usernames`
// index, exact via the `userNameLower` fallback query, and the raw prefix scan — because
// only the prefix scan bypasses `loadUserHit` and calls `toPublicSearchHit` directly; a fix
// that only guarded the exact-match paths would still leak an opted-out user there.
describe("FR-48: searchUsers honors the username searchability opt-out end to end", () => {
  beforeEach(() => {
    db().seed("users/optedout", {
      userName: "PrefixMatchOptOut",
      userNameLower: "prefixmatchoptout",
      isRegistered: true,
      privacy: { usernameSearchable: false },
    });
    // The `usernames` index doc is written regardless of the opt-out (index eligibility
    // depends only on isRegistered/isChildAccount, mirroring the email/phone lookup
    // indexes) — seeded here to prove the query-time check, not index absence, is doing
    // the work.
    db().seed("usernames/prefixmatchoptout", { userId: "optedout" });
    db().seed("users/seeker", { userName: "Seeker", isRegistered: true });
  });

  it("hides an opted-out user from the exact usernames-index lookup", async () => {
    const response = await runSearch("seeker", "prefixmatchoptout");
    expect(response.results).toEqual([]);
  });

  it("hides an opted-out user from the raw userNameLower PREFIX scan", async () => {
    // "prefixmatch" does not equal the full username, so neither exact-match branch
    // fires — only the prefix scan (calling toPublicSearchHit directly) can find this row.
    const response = await runSearch("seeker", "prefixmatch");
    expect(response.results).toEqual([]);
  });

  it("regression: a user who has NOT opted out is still found on every path", async () => {
    db().seed("users/findable", {
      userName: "PrefixMatchFindable",
      userNameLower: "prefixmatchfindable",
      isRegistered: true,
      privacy: { usernameSearchable: true },
    });
    db().seed("usernames/prefixmatchfindable", { userId: "findable" });

    const exact = await runSearch("seeker", "prefixmatchfindable");
    expect(exact.results.map((hit) => hit.userId)).toEqual(["findable"]);

    const prefix = await runSearch("seeker", "prefixmatch");
    expect(prefix.results.map((hit) => hit.userId)).toEqual(["findable"]);
  });
});

describe("§3.1.1 item 9: a stale sync execution can never resurrect a deleted user doc", () => {
  // The deletion flow's own users-doc writes (deletion-intent marker, membership exit)
  // each enqueue a trigger execution; Firestore gives no cross-event ordering guarantee,
  // so one can be processed AFTER executeAccountDeletionForUser removed `users/{uid}`.
  // Observed live 2026-08-29: the stamp's old set(merge:true) recreated the deleted doc
  // as exactly `{userNameLower}` — reaper-blind (no child flag survives) and matchable
  // by the userNameLower fallback query. These pin: a missing doc STAYS missing.

  it("a stale child-branch event processed after account deletion does not recreate users/{uid}", async () => {
    seedStaleIndexResidue("kid");
    const staleAfter = {
      userName: "KidRacer",
      isRegistered: true,
      isChildAccount: true,
      email: "kid@example.com",
      phoneNumber: "+12035551111",
    };
    await fireProfileWrite("kid", staleAfter, staleAfter);

    expect(db().store.has("users/kid")).toBe(false);
    // The stale index rows are still cleaned — refusing to resurrect must not
    // weaken the FR-11 removal the child branch exists for.
    expect(indexRows()).toEqual([]);
  });

  it("a stale registered-adult event processed after deletion does not recreate users/{uid} either", async () => {
    const staleAfter = { userName: "GoneAdult", isRegistered: true };
    await fireProfileWrite("gone", staleAfter, staleAfter);
    expect(db().store.has("users/gone")).toBe(false);
  });

  it("a child's live doc never receives the userNameLower stamp (children are never findable)", async () => {
    const child = { userName: "KidRacer", isRegistered: true, isChildAccount: true };
    db().seed("users/kid", child);
    await fireProfileWrite("kid", null, child);
    expect(db().store.get("users/kid")).not.toHaveProperty("userNameLower");
  });

  it("a registered adult's live doc still gets the stamp (update path, doc present)", async () => {
    const adult = { userName: "RoadKing", isRegistered: true };
    db().seed("users/adult", adult);
    await fireProfileWrite("adult", null, adult);
    expect(
      (db().store.get("users/adult") as Record<string, unknown>).userNameLower
    ).toBe("roadking");
  });
});

// ---------------------------------------------------------------------------
// FR-71 (F-27): the child-caller short-circuit runs ahead of classification and budget
// ---------------------------------------------------------------------------

describe("FR-71: child callers short-circuit before classifySearchQuery or the rate limit", () => {
  beforeEach(() => {
    db().seed("users/kid", {
      userName: "KidRacer",
      isRegistered: true,
      isChildAccount: true,
    });
    db().seed("users/grown", { userName: "Grown", isRegistered: true });
  });

  it("never calls classifySearchQuery for a child caller", async () => {
    const response = await runSearch("kid", "grown");
    expect(response.results).toEqual([]);
    expect(holder.classifyCalls).toEqual([]);
  });

  it("control: classifySearchQuery DOES run for a non-child caller (proves the spy is live)", async () => {
    await runSearch("grown", "somebody-else");
    expect(holder.classifyCalls).toEqual(["somebody-else"]);
  });

  it("spends no user_search rate-limit budget for a child caller", async () => {
    await runSearch("kid", "grown");
    expect(rateLimitCounter("kid")).toBeUndefined();
  });

  it("a child caller with an exhausted OTHER user's budget is unaffected — the gate never reaches the budget check either way", async () => {
    // Not a realistic state (a child cannot have spent user_search budget, since it is only
    // ever consumed past the child gate) — seeded anyway to prove the child branch does not
    // even LOOK at the counter doc for its own uid.
    db().seed(
      `${INVITE_RATE_LIMIT_COLLECTION}/${inviteRateLimitDocId("user_search", "kid")}`,
      { userId: "kid", scope: "user_search", windowStartAtMs: Date.now(), count: 999 }
    );
    const response = await runSearch("kid", "grown");
    expect(response.results).toEqual([]);
    // Untouched — still whatever nonsense was seeded, never read or rewritten by a decision.
    expect(rateLimitCounter("kid")).toMatchObject({ count: 999 });
  });

  it("still enforces the length floor for a NON-child caller (unchanged behavior)", async () => {
    await expect(runSearch("grown", "ab")).rejects.toMatchObject({
      code: "invalid-argument",
    });
    // The length floor already ran ahead of classification before FR-71 — still true.
    expect(holder.classifyCalls).toEqual([]);
  });
});

// ---------------------------------------------------------------------------
// FR-71 (F-27): searchUsers rate limiting
// ---------------------------------------------------------------------------

describe("FR-71: searchUsers rate limiting", () => {
  beforeEach(() => {
    db().seed("users/seeker", { userName: "Seeker", isRegistered: true });
  });

  it("allows exactly the configured number of searches, then refuses", async () => {
    for (let i = 0; i < USER_SEARCH_MAX_PER_WINDOW; i += 1) {
      await expect(runSearch("seeker", "nomatchquery")).resolves.toMatchObject({
        results: [],
      });
    }
    expect(rateLimitCounter("seeker")).toMatchObject({
      count: USER_SEARCH_MAX_PER_WINDOW,
    });

    const error = await runSearch("seeker", "nomatchquery").catch((e) => e);
    expect(error.code).toBe("resource-exhausted");
    // Search-scoped wording (owner-found 2026-09-07: the limit read "Too many invites").
    expect(error.message).toBe(USER_SEARCH_RATE_LIMITED_MESSAGE);
    expect(error.details).toMatchObject({ reason: INVITE_RATE_LIMITED_REASON });
    expect(rateLimitCounter("seeker")).toMatchObject({
      count: USER_SEARCH_MAX_PER_WINDOW,
    });
  });

  it("is per-caller: exhausting one searcher does not block another", async () => {
    db().seed(
      `${INVITE_RATE_LIMIT_COLLECTION}/${inviteRateLimitDocId("user_search", "seeker")}`,
      {
        userId: "seeker",
        scope: "user_search",
        windowStartAtMs: Date.now(),
        count: USER_SEARCH_MAX_PER_WINDOW,
      }
    );
    await expect(runSearch("seeker", "nomatchquery")).rejects.toMatchObject({
      code: "resource-exhausted",
    });

    db().seed("users/otherseeker", { userName: "OtherSeeker", isRegistered: true });
    await expect(runSearch("otherseeker", "nomatchquery")).resolves.toMatchObject({
      results: [],
    });
  });

  it("recovers once the window lapses", async () => {
    vi.useFakeTimers();
    const start = new Date("2026-08-13T12:00:00Z");
    vi.setSystemTime(start);

    for (let i = 0; i < USER_SEARCH_MAX_PER_WINDOW; i += 1) {
      await runSearch("seeker", "nomatchquery");
    }
    await expect(runSearch("seeker", "nomatchquery")).rejects.toMatchObject({
      code: "resource-exhausted",
    });

    vi.setSystemTime(new Date(start.getTime() + INVITE_RATE_LIMIT_WINDOW_MS));
    await expect(runSearch("seeker", "nomatchquery")).resolves.toMatchObject({
      results: [],
    });
    expect(rateLimitCounter("seeker")).toMatchObject({ count: 1 });
  });

  it("a rate-limited search writes nothing (refusal spends no budget beyond the cap)", async () => {
    db().seed(
      `${INVITE_RATE_LIMIT_COLLECTION}/${inviteRateLimitDocId("user_search", "seeker")}`,
      {
        userId: "seeker",
        scope: "user_search",
        windowStartAtMs: Date.now(),
        count: USER_SEARCH_MAX_PER_WINDOW,
      }
    );
    const writesBefore = db().writeCount;
    await runSearch("seeker", "nomatchquery").catch(() => undefined);
    expect(db().writeCount).toBe(writesBefore);
    expect(rateLimitCounter("seeker")).toMatchObject({
      count: USER_SEARCH_MAX_PER_WINDOW,
    });
  });
});

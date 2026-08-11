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
  };
  firestore.Timestamp = {
    fromMillis: (ms: number) => ({ toMillis: () => ms }),
    fromDate: (date: Date) => ({ toMillis: () => date.getTime() }),
  };
  return { default: { firestore }, firestore };
});

import type { FakeFirestore } from "./testSupport/fakeFirestore";
import {
  onUserContactSearchIndexSync,
  onUserProfileSearchIndexSync,
  searchUsers,
} from "./userSearch";

function db(): FakeFirestore {
  return holder.db as FakeFirestore;
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

/**
 * FR-70: `scripts/backfillUserSearchIndexes.ts` must use the same search-index eligibility
 * predicate as production (`isSearchIndexEligible`, not the registration-only
 * `isRegisteredForSearch`) so it never re-indexes a child account. Mocks `firebase-admin`
 * with a `FakeFirestore` (see `userSearchChildEnforcement.test.ts` for the same pattern
 * against the production trigger) plus a spyable `auth().getUser`, since the defect this
 * guards against is specifically: (1) a child reaching `usernames` / `user_lookup_email` /
 * `user_lookup_phone`, and (2) a child's Auth email being fetched as a fallback at all.
 */
import { describe, it, expect, beforeEach, vi } from "vitest";

const holder = vi.hoisted(() => ({
  db: undefined as any,
  getUser: undefined as any,
}));

vi.mock("firebase-admin", async () => {
  const { FakeFirestore } = await import("./testSupport/fakeFirestore");
  holder.db = new FakeFirestore();
  holder.getUser = vi.fn(async () => ({ email: undefined as string | undefined }));

  const firestore: any = () => holder.db;
  firestore.FieldValue = {
    serverTimestamp: () => "__serverTimestamp__",
    delete: () => "__delete__",
  };
  firestore.Timestamp = {
    fromMillis: (ms: number) => ({ toMillis: () => ms }),
    fromDate: (date: Date) => ({ toMillis: () => date.getTime() }),
  };
  firestore.FieldPath = { documentId: () => "__name__" };

  const apps: unknown[] = [];
  const initializeApp = () => {
    apps.push({});
  };
  const auth = () => ({ getUser: holder.getUser });

  return {
    default: { apps, initializeApp, firestore, auth },
    apps,
    initializeApp,
    firestore,
    auth,
  };
});

import type { FakeFirestore } from "./testSupport/fakeFirestore";
import { processUser } from "../scripts/backfillUserSearchIndexes";

function db(): FakeFirestore {
  return holder.db as FakeFirestore;
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
  holder.getUser.mockClear();
});

describe("backfillUserSearchIndexes: processUser eligibility (FR-70)", () => {
  it("a child fixture produces zero index rows and never fetches an Auth-email fallback", async () => {
    const child = {
      userName: "KidRacer",
      isRegistered: true,
      isChildAccount: true,
      // Deliberately no top-level email/phoneNumber: this is exactly the case the old
      // isRegisteredForSearch() predicate could poison, by reaching into Auth for contact
      // data the child had no discoverable copy of anywhere else.
    };

    const result = await processUser("kid", child);

    expect(result).toEqual({ indexed: false, skippedAnon: true });
    expect(indexRows()).toEqual([]);
    expect(holder.getUser).not.toHaveBeenCalled();
  });

  it("a consented child (active family) still produces zero index rows", async () => {
    const child = {
      userName: "KidRacer",
      isRegistered: true,
      isChildAccount: true,
      activeFamilyId: "fam1",
      email: "kid@example.com",
      phoneNumber: "+12035551111",
    };

    const result = await processUser("kid", child);

    expect(result).toEqual({ indexed: false, skippedAnon: true });
    expect(indexRows()).toEqual([]);
  });

  it("regression: an adult fixture is still indexed via the Auth-email fallback", async () => {
    holder.getUser.mockResolvedValueOnce({ email: "grown@example.com" });
    const adult = {
      userName: "Grown",
      isRegistered: true,
      // No top-level email — exercises the Auth fallback path this script relies on for
      // adults, which must keep working even though children must never reach it.
    };

    const result = await processUser("adult", adult);

    expect(result).toEqual({ indexed: true, skippedAnon: false });
    expect(holder.getUser).toHaveBeenCalledWith("adult");
    expect(indexRows()).toEqual(["user_lookup_email/grown@example.com", "usernames/grown"]);
  });
});

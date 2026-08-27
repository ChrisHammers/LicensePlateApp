import { describe, it, expect } from "vitest";
import * as functions from "firebase-functions/v1";
import type * as admin from "firebase-admin";
import {
  REGISTERED_ACCOUNT_REQUIRED_MESSAGE,
  assertAuthenticated,
  assertNotUnconsentedChild,
  assertRegisteredAccount,
  assertRegisteredAccountOrDeclaredChild,
} from "./callableAuth";
import { FakeFirestore } from "./testSupport/fakeFirestore";

function asFirestore(db: FakeFirestore): admin.firestore.Firestore {
  return db as unknown as admin.firestore.Firestore;
}

function makeContext(
  auth: functions.https.CallableContext["auth"]
): functions.https.CallableContext {
  return { auth } as functions.https.CallableContext;
}

describe("callableAuth", () => {
  it("assertAuthenticated rejects missing auth", () => {
    expect(() => assertAuthenticated(makeContext(undefined))).toThrowError(
      /authenticated/i
    );
  });

  it("assertAuthenticated returns uid for signed-in users", () => {
    expect(
      assertAuthenticated(
        makeContext({
          uid: "user-123",
          token: { firebase: { sign_in_provider: "password" } },
        } as functions.https.CallableContext["auth"])
      )
    ).toBe("user-123");
  });

  it("assertRegisteredAccount rejects anonymous Firebase accounts", () => {
    expect(() =>
      assertRegisteredAccount(
        makeContext({
          uid: "anon-123",
          token: { firebase: { sign_in_provider: "anonymous" } },
        } as functions.https.CallableContext["auth"])
      )
    ).toThrowError(/registered account/i);
  });

  it("assertRegisteredAccount allows linked OAuth accounts", () => {
    expect(
      assertRegisteredAccount(
        makeContext({
          uid: "signed-123",
          token: { firebase: { sign_in_provider: "google.com" } },
        } as functions.https.CallableContext["auth"])
      )
    ).toBe("signed-123");
  });
});

describe("assertRegisteredAccountOrDeclaredChild (COPPA FR-60, F-18)", () => {
  function anonymous(uid: string): functions.https.CallableContext {
    return makeContext({
      uid,
      token: { firebase: { sign_in_provider: "anonymous" } },
    } as functions.https.CallableContext["auth"]);
  }
  function registered(uid: string): functions.https.CallableContext {
    return makeContext({
      uid,
      token: { firebase: { sign_in_provider: "password" } },
    } as functions.https.CallableContext["auth"]);
  }

  function seededDb(): FakeFirestore {
    const db = new FakeFirestore();
    db.seed("users/declared-kid", { isChildAccount: true });
    db.seed("users/sticky-kid", { isChildAccount: true, wasEverInFamily: true });
    db.seed("users/consented-kid", { isChildAccount: true, activeFamilyId: "fam1" });
    db.seed("users/plain-anon", { userName: "Guest" });
    return db;
  }

  it("passes an anonymous caller whose users/{uid} is a declared child", async () => {
    await expect(
      assertRegisteredAccountOrDeclaredChild(asFirestore(seededDb()), anonymous("declared-kid"))
    ).resolves.toBe("declared-kid");
  });

  it("passes a STICKY post-revocation child — re-admission is their exit too", async () => {
    await expect(
      assertRegisteredAccountOrDeclaredChild(asFirestore(seededDb()), anonymous("sticky-kid"))
    ).resolves.toBe("sticky-kid");
  });

  it("passes a consented child (the flag, not the family, is the credential)", async () => {
    await expect(
      assertRegisteredAccountOrDeclaredChild(asFirestore(seededDb()), anonymous("consented-kid"))
    ).resolves.toBe("consented-kid");
  });

  it("fails a plain anonymous caller, and one with no user doc at all", async () => {
    await expect(
      assertRegisteredAccountOrDeclaredChild(asFirestore(seededDb()), anonymous("plain-anon"))
    ).rejects.toMatchObject({ code: "failed-precondition" });
    await expect(
      assertRegisteredAccountOrDeclaredChild(asFirestore(seededDb()), anonymous("nobody"))
    ).rejects.toMatchObject({ code: "failed-precondition" });
  });

  it("passes registered accounts without reading the user doc at all", async () => {
    const db = new FakeFirestore(); // deliberately empty
    await expect(
      assertRegisteredAccountOrDeclaredChild(asFirestore(db), registered("grown-up"))
    ).resolves.toBe("grown-up");
    expect(db.store.size).toBe(0);
  });

  it("still rejects an unauthenticated caller", async () => {
    await expect(
      assertRegisteredAccountOrDeclaredChild(asFirestore(new FakeFirestore()), makeContext(undefined))
    ).rejects.toMatchObject({ code: "unauthenticated" });
  });

  /**
   * FR-24 indistinguishability. If the carve-out's refusal differed from the plain
   * registered-account refusal by so much as a `details` key, an anonymous caller could diff
   * the two replies and learn whether the uid it holds is a declared child — the same oracle
   * FR-24 closes on the invite surfaces, rebuilt on the auth gate.
   */
  it("refuses byte-identically to assertRegisteredAccount", async () => {
    const carveOutError = await assertRegisteredAccountOrDeclaredChild(
      asFirestore(seededDb()),
      anonymous("plain-anon")
    ).catch((error) => error as functions.https.HttpsError);

    let baselineError: functions.https.HttpsError;
    try {
      assertRegisteredAccount(anonymous("plain-anon"));
      throw new Error("expected assertRegisteredAccount to throw");
    } catch (error) {
      baselineError = error as functions.https.HttpsError;
    }

    expect(carveOutError.code).toBe(baselineError.code);
    expect(carveOutError.message).toBe(baselineError.message);
    expect(carveOutError.message).toBe(REGISTERED_ACCOUNT_REQUIRED_MESSAGE);
    expect(carveOutError.details).toBeUndefined();
    expect(baselineError.details).toBeUndefined();
    expect(carveOutError.httpErrorCode.status).toBe(baselineError.httpErrorCode.status);
  });
});

describe("assertNotUnconsentedChild (COPPA FR-28)", () => {
  it("rejects a flagged child with no active family, with a client-mappable reason", async () => {
    const db = new FakeFirestore();
    db.seed("users/kid", { isChildAccount: true });

    await expect(
      assertNotUnconsentedChild(asFirestore(db), "kid")
    ).rejects.toMatchObject({
      code: "failed-precondition",
      details: { reason: "unconsented_child" },
    });
  });

  it("allows a consented child (active family present)", async () => {
    const db = new FakeFirestore();
    db.seed("users/kid", { isChildAccount: true, activeFamilyId: "fam1" });
    await expect(
      assertNotUnconsentedChild(asFirestore(db), "kid")
    ).resolves.toBeUndefined();
  });

  it("allows adults and treats a missing doc or missing flag as adult", async () => {
    const db = new FakeFirestore();
    db.seed("users/adult", { userName: "grown" });
    await expect(
      assertNotUnconsentedChild(asFirestore(db), "adult")
    ).resolves.toBeUndefined();
    await expect(
      assertNotUnconsentedChild(asFirestore(db), "nobody")
    ).resolves.toBeUndefined();
  });
});

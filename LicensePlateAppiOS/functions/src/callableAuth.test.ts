import { describe, it, expect } from "vitest";
import * as functions from "firebase-functions";
import type * as admin from "firebase-admin";
import {
  assertAuthenticated,
  assertNotUnconsentedChild,
  assertRegisteredAccount,
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

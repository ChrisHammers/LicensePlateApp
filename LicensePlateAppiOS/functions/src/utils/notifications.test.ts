import { describe, it, expect, beforeEach, vi } from "vitest";

/**
 * FR-43 / audit E1: the push token lives at users/{uid}/private/fcm, never on the
 * peer-readable users/{uid} doc. These tests pin the read path and the migration fallback.
 */

type DocData = Record<string, unknown> | undefined;

const store: { user: DocData; privateFcm: DocData } = {
  user: undefined,
  privateFcm: undefined,
};

/** Paths touched by `.get()`, in call order — proves where the token is read from. */
const readPaths: string[] = [];

function docSnapshot(path: string, data: DocData) {
  return {
    exists: data !== undefined,
    data: () => data,
    get id() {
      return path;
    },
  };
}

function privateCollection(userId: string) {
  return {
    doc: (docId: string) => ({
      get: async () => {
        const path = `users/${userId}/private/${docId}`;
        readPaths.push(path);
        return docSnapshot(path, docId === "fcm" ? store.privateFcm : undefined);
      },
    }),
  };
}

vi.mock("firebase-admin", () => {
  const firestore = () => ({
    collection: (collectionId: string) => ({
      doc: (userId: string) => ({
        get: async () => {
          const path = `${collectionId}/${userId}`;
          readPaths.push(path);
          return docSnapshot(path, store.user);
        },
        collection: (subId: string) => {
          if (subId !== "private") {
            throw new Error(`unexpected subcollection ${subId}`);
          }
          return privateCollection(userId);
        },
      }),
    }),
  });
  return { default: { firestore }, firestore };
});

const { getFCMToken, getFCMTokenForPush, resolveFCMToken, FCM_PRIVATE_DOC_ID } = await import(
  "./notifications"
);

beforeEach(() => {
  store.user = undefined;
  store.privateFcm = undefined;
  readPaths.length = 0;
});

describe("resolveFCMToken", () => {
  it("prefers the private doc token", () => {
    expect(resolveFCMToken({ token: "private-token" }, { fcmToken: "legacy-token" })).toBe(
      "private-token"
    );
  });

  it("falls back to the legacy public field for unmigrated docs", () => {
    expect(resolveFCMToken(undefined, { fcmToken: "legacy-token" })).toBe("legacy-token");
    expect(resolveFCMToken({}, { fcmToken: "legacy-token" })).toBe("legacy-token");
  });

  it("returns null when neither location has a usable token", () => {
    expect(resolveFCMToken(undefined, undefined)).toBeNull();
    expect(resolveFCMToken({ token: "" }, { fcmToken: "" })).toBeNull();
    expect(resolveFCMToken({ token: 42 }, { fcmToken: null })).toBeNull();
  });
});

describe("getFCMTokenForPush", () => {
  it("reads the token from users/{uid}/private/fcm", async () => {
    store.user = { userName: "Ada" };
    store.privateFcm = { token: "private-token" };

    await expect(getFCMTokenForPush("u1", "tripInvite")).resolves.toBe("private-token");
    expect(readPaths).toContain(`users/u1/private/${FCM_PRIVATE_DOC_ID}`);
  });

  it("never returns a token when the public doc is the only source and it is empty", async () => {
    store.user = { userName: "Ada" };
    store.privateFcm = undefined;

    await expect(getFCMTokenForPush("u1", "tripInvite")).resolves.toBeNull();
  });

  it("still delivers for a not-yet-migrated doc carrying the legacy field", async () => {
    store.user = { userName: "Ada", fcmToken: "legacy-token" };

    await expect(getFCMTokenForPush("u1", "friend")).resolves.toBe("legacy-token");
  });

  it("honors notificationPrefs before returning the private token", async () => {
    store.user = { notificationPrefs: { tripInvite: false } };
    store.privateFcm = { token: "private-token" };

    await expect(getFCMTokenForPush("u1", "tripInvite")).resolves.toBeNull();
    await expect(getFCMTokenForPush("u1", "friend")).resolves.toBe("private-token");
  });

  it("returns null when the user doc is missing even if a token doc lingers", async () => {
    store.privateFcm = { token: "private-token" };

    await expect(getFCMTokenForPush("u1", "friend")).resolves.toBeNull();
  });

  it("defaults promotionsAndNews to off", async () => {
    store.user = { userName: "Ada" };
    store.privateFcm = { token: "private-token" };

    await expect(getFCMTokenForPush("u1", "promotionsAndNews")).resolves.toBeNull();
  });
});

describe("getFCMToken", () => {
  it("reads the private doc without pref gating", async () => {
    store.user = { notificationPrefs: { friend: false } };
    store.privateFcm = { token: "private-token" };

    await expect(getFCMToken("u1")).resolves.toBe("private-token");
    expect(readPaths).toContain(`users/u1/private/${FCM_PRIVATE_DOC_ID}`);
  });
});

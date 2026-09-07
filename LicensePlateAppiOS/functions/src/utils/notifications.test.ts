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

// ---------------------------------------------------------------------------
// FR-73(c) — marketing suppression for child accounts
// ---------------------------------------------------------------------------

describe("FR-73(c): a child account is never sent the marketing category", () => {
  /**
   * The sharp case, and the reason the gate cannot live on the preference default: an
   * explicit `promotionsAndNews: true` is exactly what an older client, a dev fixture, or a
   * parent tapping the toggle before the child flag landed would leave behind. The
   * preference gate would honour it; the child gate must not.
   */
  it("refuses the promo category even when the pref is explicitly ON", async () => {
    store.user = {
      userName: "Kid",
      isChildAccount: true,
      notificationPrefs: { promotionsAndNews: true },
    };
    store.privateFcm = { token: "private-token" };

    await expect(getFCMTokenForPush("u1", "promotionsAndNews")).resolves.toBeNull();
  });

  /**
   * FR-73(c)'s scope, pinned in both directions: consent covers the bounded family-trip
   * categories (FR-38), so a CONSENTED child keeps every transactional push. If this ever
   * goes null the suppression has over-reached and children have silently lost the pushes
   * their parents consented to.
   */
  it("leaves a consented child's transactional categories untouched", async () => {
    store.user = {
      userName: "Kid",
      isChildAccount: true,
      activeFamilyId: "fam1",
    };
    store.privateFcm = { token: "private-token" };

    for (const category of ["family", "tripInvite", "tripEnded"] as const) {
      await expect(getFCMTokenForPush("u1", category)).resolves.toBe("private-token");
    }
  });

  /**
   * v3 §5 R-15: the per-category engagement defaults for consented children were considered
   * and DECLINED, and FR-73(c) narrows to the marketing category only. This pins that
   * boundary so a later widening is a deliberate owner decision rather than a silent drift.
   */
  it("does NOT suppress the engagement reminder categories (R-15 stands)", async () => {
    store.user = { userName: "Kid", isChildAccount: true, activeFamilyId: "fam1" };
    store.privateFcm = { token: "private-token" };

    await expect(getFCMTokenForPush("u1", "inactiveTripReminder")).resolves.toBe(
      "private-token"
    );
    await expect(getFCMTokenForPush("u1", "returnStreakReminder")).resolves.toBe(
      "private-token"
    );
  });

  it("still delivers the marketing category to an adult who opted in", async () => {
    store.user = { userName: "Ada", notificationPrefs: { promotionsAndNews: true } };
    store.privateFcm = { token: "private-token" };

    await expect(getFCMTokenForPush("u1", "promotionsAndNews")).resolves.toBe(
      "private-token"
    );
  });

  /**
   * An explicit `false` is what a manager CORRECTION writes (`familyChildStatusFlows.ts`),
   * so a corrected account must get its marketing category back rather than staying
   * suppressed on a stale reading of the flag.
   */
  it("restores the marketing category to an explicitly corrected account", async () => {
    store.user = {
      userName: "WasKid",
      isChildAccount: false,
      notificationPrefs: { promotionsAndNews: true },
    };
    store.privateFcm = { token: "private-token" };

    await expect(getFCMTokenForPush("u1", "promotionsAndNews")).resolves.toBe(
      "private-token"
    );
  });

  /**
   * The legacy top-level token is a second source `resolveFCMToken` still honours, so the
   * child gate has to sit ABOVE resolution rather than beside the private-doc read.
   */
  it("refuses the promo category for a child on the legacy token path too", async () => {
    store.user = {
      userName: "Kid",
      isChildAccount: true,
      fcmToken: "legacy-token",
      notificationPrefs: { promotionsAndNews: true },
    };

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

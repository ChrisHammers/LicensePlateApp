/**
 * FR-59/FR-59.1 email_plus — the consent-request lifecycle, end to end against the real
 * callables and the real confirmation transaction (§3.1.2 steps 1–3 + the expiry sweep).
 *
 * The properties a reviewer has to trust:
 *  1. APPROVE DOES NOT ADMIT. The captain's tap opens a guardian confirmation; no
 *     membership, no activeFamilyId, no consent record exists until the link is clicked.
 *  2. THE LINK IS SINGLE-USE AND HASHED. The stored document never holds a usable
 *     credential once the email is claimed; a wrong nonce is refused uniformly.
 *  3. FR-64 ATOMICITY. Consent record + guardianship + membership + activeFamilyId
 *     commit together — and REFUSE together when FR-110's marker is missing.
 *  4. THE DELETION TRAP IS CLOSED. An awaiting-guardian child is invisible to the FR-77
 *     sweep, and a second redemption dedupes against the awaiting row.
 *  5. EXPIRY IS REFUSAL BY SILENCE. The sweep retires the row, purges the guardian's
 *     email, and deletes the never-consented account inline.
 */

import { describe, it, expect, beforeEach, vi } from "vitest";

const holder = vi.hoisted(() => ({
  db: undefined as any,
  deletedAuthUsers: [] as string[],
}));

vi.mock("firebase-admin", async () => {
  const { FakeFirestore } = await import("./testSupport/fakeFirestore");
  holder.db = new FakeFirestore();
  const firestore: any = () => holder.db;
  firestore.FieldValue = {
    serverTimestamp: () => "__serverTimestamp__",
    delete: () => "__delete__",
    arrayUnion: (...values: unknown[]) => ({ __arrayUnion__: values }),
    increment: (n: number) => ({ __increment__: n }),
  };
  firestore.Timestamp = {
    fromMillis: (ms: number) => ms,
    fromDate: (date: Date) => date.getTime(),
    now: () => Date.now(),
  };
  const auth: any = () => ({
    deleteUser: async (uid: string) => {
      holder.deletedAuthUsers.push(uid);
    },
  });
  const messaging: any = () => ({ send: async () => "sent" });
  return { default: { firestore, auth, messaging }, firestore, auth, messaging };
});

import type { FakeFirestore } from "./testSupport/fakeFirestore";
import {
  approveFamilyJoinRequest_CaptainStep,
  createFamily,
  respondToFamilyInvite_UserStep,
} from "./family";
import { createShareCode, redeemShareCode } from "./shareCodes";
import {
  commitGuardianConfirmation,
  sweepExpiredConsentRequests,
  type ConfirmableRequest,
} from "./consentRequests";
import {
  CONSENT_REQUESTS_COLLECTION,
  CONSENT_REQUEST_TTL_MS,
  JOIN_REQUEST_AWAITING_GUARDIAN_STATUS,
  decideConsentConfirmation,
  hashConsentNonce,
  isValidAgeOutYearMonth,
  parseConsentToken,
} from "./consentRequestsCore";
import {
  confirmGuardianConsent,
  findLiveConsentRequest,
} from "./testSupport/consentTestHelpers";

function db(): FakeFirestore {
  return holder.db as FakeFirestore;
}

type Runnable = { run: (data: unknown, context: unknown) => Promise<unknown> };

function context(uid: string): unknown {
  return { auth: { uid, token: { firebase: { sign_in_provider: "password" } } } };
}

const run = {
  createFamily: (uid: string, name: string) =>
    (createFamily as unknown as Runnable).run({ name }, context(uid)) as Promise<{
      familyId: string;
    }>,
  createShareCode: (uid: string, familyId: string) =>
    (createShareCode as unknown as Runnable).run(
      { type: "family", familyId },
      context(uid)
    ) as Promise<{ codeId: string; code: string }>,
  redeemShareCode: (uid: string, code: string) =>
    (redeemShareCode as unknown as Runnable).run(
      { code, expectedType: "family" },
      context(uid)
    ) as Promise<{ inviteId: string }>,
  acceptInvite: (uid: string, inviteId: string) =>
    (respondToFamilyInvite_UserStep as unknown as Runnable).run(
      { inviteId, response: "accept" },
      context(uid)
    ),
  approve: (uid: string, payload: Record<string, unknown>) =>
    (approveFamilyJoinRequest_CaptainStep as unknown as Runnable).run(
      { response: "approve", ...payload },
      context(uid)
    ),
  decline: (uid: string, payload: Record<string, unknown>) =>
    (approveFamilyJoinRequest_CaptainStep as unknown as Runnable).run(
      { response: "decline", ...payload },
      context(uid)
    ),
};

const CHILD_APPROVAL = {
  isChild: true,
  consentAcknowledged: true,
  guardianAffirmed: true,
};

async function childAwaiting(): Promise<{ familyId: string; requestId: string }> {
  const { familyId } = await run.createFamily("captain", "Hammers");
  const { code } = await run.createShareCode("captain", familyId);
  const { inviteId } = await run.redeemShareCode("kid", code);
  await run.acceptInvite("kid", inviteId);
  const rows = [...db().store.entries()].filter(
    ([path, data]) =>
      path.startsWith(`families/${familyId}/pending/`) && data.status === "pending"
  );
  expect(rows).toHaveLength(1);
  const requestId = rows[0][0].split("/").pop()!;
  await run.approve("captain", { familyId, requestId, ...CHILD_APPROVAL });
  return { familyId, requestId };
}

beforeEach(() => {
  db().store.clear();
  db().writeCount = 0;
  holder.deletedAuthUsers.length = 0;

  db().seed("users/captain", { userName: "Captain" });
  db().seed("users/captain/private/contact", { email: "captain@example.com" });
  db().seed("users/kid", {
    userName: "Speedy",
    avatarId: "scout_otter",
    isChildAccount: true,
    childDeclaredAt: Date.now(),
    ageOutYearMonth: 203703,
  });
});

// ---------------------------------------------------------------------------
// 1. Approve opens a confirmation; it does not admit
// ---------------------------------------------------------------------------

describe("FR-59.1: approve creates the consent request and admits nobody", () => {
  it("row → awaiting_guardian; no membership, no activeFamilyId, no consent audit row", async () => {
    const { familyId, requestId } = await childAwaiting();

    expect(
      db().store.get(`families/${familyId}/pending/${requestId}`)?.status
    ).toBe(JOIN_REQUEST_AWAITING_GUARDIAN_STATUS);
    expect(db().store.get(`families/${familyId}/members/kid`)).toBeUndefined();
    expect(db().store.get("users/kid")?.activeFamilyId).toBeUndefined();
    const consentRows = [...db().store.entries()].filter(
      ([path, data]) =>
        path.startsWith("audit_logs/") &&
        data.eventType === "AUDIT_PARENTAL_CONSENT_GRANTED"
    );
    expect(consentRows).toHaveLength(0);
  });

  it("stores the nonce HASHED, with the raw copy only in the transient email field", async () => {
    const { familyId } = await childAwaiting();
    const found = findLiveConsentRequest(db(), { familyId, childUserId: "kid" })!;

    const raw = found.data.pendingLinkNonce as string;
    const stored = found.data.nonceHash as string;
    expect(raw).toMatch(/^[a-f0-9]{32}$/);
    expect(stored).not.toBe(raw);
    expect(stored).toBe(hashConsentNonce(raw));
    // The guardian's email lives on the server-only doc, §312.5(c)(1).
    expect(found.data.guardianEmail).toBe("captain@example.com");
  });

  it("re-approve reuses the live request — one request, no second email nonce", async () => {
    const { familyId, requestId } = await childAwaiting();
    const first = findLiveConsentRequest(db(), { familyId, childUserId: "kid" })!;

    await expect(
      run.approve("captain", { familyId, requestId, ...CHILD_APPROVAL })
    ).resolves.toMatchObject({ success: true, awaitingGuardianConfirmation: true });

    const requests = [...db().store.entries()].filter(([path]) =>
      path.startsWith(`${CONSENT_REQUESTS_COLLECTION}/`)
    );
    expect(requests).toHaveLength(1);
    expect(findLiveConsentRequest(db(), { familyId, childUserId: "kid" })!.requestId).toBe(
      first.requestId
    );
  });

  it("a captain with no resolvable email is refused before any state changes", async () => {
    db().seed("users/captain2", { userName: "NoMail" });
    const { familyId } = await run.createFamily("captain2", "Mailless");
    const { code } = await run.createShareCode("captain2", familyId);
    const { inviteId } = await run.redeemShareCode("kid", code);
    await run.acceptInvite("kid", inviteId);
    const rows = [...db().store.entries()].filter(
      ([path, data]) =>
        path.startsWith(`families/${familyId}/pending/`) && data.status === "pending"
    );
    const requestId = rows[0][0].split("/").pop()!;

    await expect(
      run.approve("captain2", { familyId, requestId, ...CHILD_APPROVAL })
    ).rejects.toMatchObject({ code: "failed-precondition" });
    expect(
      db().store.get(`families/${familyId}/pending/${requestId}`)?.status
    ).toBe("pending");
  });
});

// ---------------------------------------------------------------------------
// 2. The confirmation transaction (FR-64) and its refusals
// ---------------------------------------------------------------------------

describe("FR-64: the guardian's click commits everything together", () => {
  it("membership + activeFamilyId + guardianship + level-1 consent record, one commit", async () => {
    const { familyId, requestId } = await childAwaiting();

    const outcome = await confirmGuardianConsent(db(), { familyId, childUserId: "kid" });
    expect(outcome.committed).toBe(true);

    expect(db().store.get(`families/${familyId}/members/kid`)?.isChild).toBe(true);
    expect(db().store.get("users/kid")?.activeFamilyId).toBe(familyId);
    expect(db().store.get("users/kid")?.wasEverInFamily).toBe(true);
    expect(
      db().store.get(`families/${familyId}/pending/${requestId}`)?.status
    ).toBe("approved");

    // FR-62 groundwork: the durable guardianship record.
    expect(db().store.get("users/kid/private/guardianship")).toMatchObject({
      guardianUid: "captain",
      familyId,
      method: "email_plus",
      assuranceLevel: 1,
    });

    // The consent audit row, written INSIDE the transaction, carrying FR-108's level
    // and FR-110's marker.
    const consentRows = [...db().store.entries()].filter(
      ([path, data]) =>
        path.startsWith("audit_logs/") &&
        data.eventType === "AUDIT_PARENTAL_CONSENT_GRANTED"
    );
    expect(consentRows).toHaveLength(1);
    expect(consentRows[0][1].metadata).toMatchObject({
      childUserId: "kid",
      method: "email_plus",
      assuranceLevel: 1,
      ageOutYearMonth: 203703,
      guardianAffirmed: true,
    });

    // §312.5(c)(1) purpose served: the guardian's email does not outlive the grant.
    const request = [...db().store.entries()].find(([path]) =>
      path.startsWith(`${CONSENT_REQUESTS_COLLECTION}/`)
    )!;
    expect(request[1].status).toBe("confirmed");
    expect(request[1].guardianEmail).toBe("__delete__");
  });

  it("AGEOUT FR-110(b): a child doc without the marker refuses to commit — nothing admits", async () => {
    db().seed("users/kid", {
      userName: "Speedy",
      avatarId: "scout_otter",
      isChildAccount: true,
      childDeclaredAt: Date.now(),
      // no ageOutYearMonth — the pre-F-14b install shape
    });
    const { familyId } = await childAwaiting();

    const outcome = await confirmGuardianConsent(db(), { familyId, childUserId: "kid" });
    expect(outcome).toMatchObject({ committed: false, reason: "missing_age_out_marker" });
    expect(db().store.get(`families/${familyId}/members/kid`)).toBeUndefined();
    expect(db().store.get("users/kid")?.activeFamilyId).toBeUndefined();
  });

  it("a second click cannot double-admit: the request is no longer pending", async () => {
    const { familyId } = await childAwaiting();
    const found = findLiveConsentRequest(db(), { familyId, childUserId: "kid" })!;
    expect((await confirmGuardianConsent(db(), { familyId, childUserId: "kid" })).committed).toBe(
      true
    );

    // Drive the raw commit again against the now-confirmed request.
    const data = found.data;
    const request: ConfirmableRequest = {
      familyId,
      childUserId: "kid",
      joinRequestId: data.joinRequestId as string,
      guardianUid: "captain",
      guardianRole: "creator",
      newRole: "scout",
      expectedAgeOutYear: null,
      assuranceLevel: 1,
    };
    const again = await commitGuardianConfirmation(
      db() as never,
      db().collection(CONSENT_REQUESTS_COLLECTION).doc(found.requestId) as never,
      request,
      Date.now()
    );
    expect(again.committed).toBe(false);
  });

  it("a decline after approve cancels the request — the stale link refuses", async () => {
    const { familyId, requestId } = await childAwaiting();

    await run.decline("captain", { familyId, requestId });

    // The decline cancelled the consent request…
    expect(findLiveConsentRequest(db(), { familyId, childUserId: "kid" })).toBeNull();
    // …so the guardian's link has nothing to confirm.
    const outcome = await confirmGuardianConsent(db(), { familyId, childUserId: "kid" });
    expect(outcome.committed).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// 3. The endpoint's pure gate
// ---------------------------------------------------------------------------

describe("the confirmation gate is uniform and single-use", () => {
  const base = {
    status: "pending",
    expiresAtMillis: 10_000,
    attempts: 0,
    nowMillis: 5_000,
    presentedNonce: "aa".repeat(16),
    storedNonceHash: hashConsentNonce("aa".repeat(16)),
  };

  it("confirms a live request with the right nonce, refuses a wrong one uniformly", () => {
    expect(decideConsentConfirmation(base)).toEqual({ kind: "confirm" });
    expect(
      decideConsentConfirmation({ ...base, presentedNonce: "bb".repeat(16) })
    ).toEqual({ kind: "refused" });
    // Superseded reads as plain refusal — the link is a bearer credential and state
    // oracles are FR-24's disease on a new surface.
    expect(decideConsentConfirmation({ ...base, status: "superseded" })).toEqual({
      kind: "refused",
    });
  });

  it("tells a CORRECT link the truth: already confirmed, or expired", () => {
    expect(decideConsentConfirmation({ ...base, status: "confirmed" })).toEqual({
      kind: "already_confirmed",
    });
    expect(decideConsentConfirmation({ ...base, nowMillis: 20_000 })).toEqual({
      kind: "expired",
    });
  });

  it("attempt exhaustion closes the request to brute force", () => {
    expect(decideConsentConfirmation({ ...base, attempts: 20 })).toEqual({
      kind: "refused",
    });
  });

  it("token parsing rejects malformed shapes outright", () => {
    expect(parseConsentToken("abc.def")).toBeNull(); // nonce not 32 hex
    expect(parseConsentToken(`abc.${"aa".repeat(16)}`)).toMatchObject({
      requestId: "abc",
    });
    expect(parseConsentToken(`.${"aa".repeat(16)}`)).toBeNull();
    expect(parseConsentToken("noseparator")).toBeNull();
    expect(parseConsentToken(42)).toBeNull();
    expect(parseConsentToken("x".repeat(300))).toBeNull();
  });

  it("marker validation bounds the plausible", () => {
    expect(isValidAgeOutYearMonth(203703)).toBe(true);
    expect(isValidAgeOutYearMonth(203700)).toBe(false); // month 0
    expect(isValidAgeOutYearMonth(203713)).toBe(false); // month 13
    expect(isValidAgeOutYearMonth(190001)).toBe(false); // year 1900 < floor
    expect(isValidAgeOutYearMonth("203703")).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// 4. The deletion trap and dedupe honor the awaiting state
// ---------------------------------------------------------------------------

describe("an awaiting-guardian child is live to every predicate", () => {
  it("the FR-77 sweep veto sees the awaiting row and leaves the account alone", async () => {
    const { familyId } = await childAwaiting();
    const { deleteProvisionalChildAccountIfNeverConsented } = await import(
      "./provisionalChildAccounts"
    );

    const result = await deleteProvisionalChildAccountIfNeverConsented(db() as never, {
      userId: "kid",
      actorId: "system_retention",
      clientMetadata: null,
      revenueCatApiKey: null,
    });
    expect(result).toMatchObject({ deleted: false, reason: "live_join_request" });
    expect(db().store.get("users/kid")).toBeDefined();
    expect(findLiveConsentRequest(db(), { familyId, childUserId: "kid" })).not.toBeNull();
  });

  it("a re-redemption while awaiting does not reset the row or mint a rival", async () => {
    const { familyId, requestId } = await childAwaiting();
    const { code } = await run.createShareCode("captain", familyId);
    const { inviteId } = await run.redeemShareCode("kid", code);

    await expect(run.acceptInvite("kid", inviteId)).resolves.toMatchObject({
      success: true,
    });

    expect(
      db().store.get(`families/${familyId}/pending/${requestId}`)?.status
    ).toBe(JOIN_REQUEST_AWAITING_GUARDIAN_STATUS);
    const rows = [...db().store.entries()].filter(
      ([path, data]) =>
        path.startsWith(`families/${familyId}/pending/`) &&
        (data.status === "pending" ||
          data.status === JOIN_REQUEST_AWAITING_GUARDIAN_STATUS)
    );
    expect(rows).toHaveLength(1);
  });
});

// ---------------------------------------------------------------------------
// 5. Expiry — refusal by silence
// ---------------------------------------------------------------------------

describe("the expiry sweep closes a lapsed request per FR-60(c)", () => {
  it("request expired, email purged, row retired, account deleted inline", async () => {
    const { familyId, requestId } = await childAwaiting();
    const found = findLiveConsentRequest(db(), { familyId, childUserId: "kid" })!;

    const afterTtl =
      (found.data.requestedAtMillis as number) + CONSENT_REQUEST_TTL_MS + 1;
    const result = await sweepExpiredConsentRequests(db() as never, afterTtl);
    expect(result.expired).toBe(1);

    const request = db().store.get(`${CONSENT_REQUESTS_COLLECTION}/${found.requestId}`)!;
    expect(request.status).toBe("expired");
    expect(request.guardianEmail).toBe("__delete__");
    expect(
      db().store.get(`families/${familyId}/pending/${requestId}`)?.status
    ).toBe("expired");
    // FR-60(c): consent not obtained within a reasonable time — deleted, Auth included.
    expect(db().store.get("users/kid")).toBeUndefined();
    expect(holder.deletedAuthUsers).toContain("kid");
  });

  it("leaves unexpired requests untouched", async () => {
    const { familyId, requestId } = await childAwaiting();

    const result = await sweepExpiredConsentRequests(db() as never, Date.now());
    expect(result.expired).toBe(0);
    expect(
      db().store.get(`families/${familyId}/pending/${requestId}`)?.status
    ).toBe(JOIN_REQUEST_AWAITING_GUARDIAN_STATUS);
    expect(db().store.get("users/kid")).toBeDefined();
  });
});
